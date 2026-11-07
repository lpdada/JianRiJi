import Foundation

/// 目录清单里的一个可下载语音包（对应服务器上的 catalog.json）。
struct RemoteVoicePack: Identifiable, Decodable, Hashable {
    let id: String
    let title: String
    let file: String
    let count: Int
    let bytes: Int64
}

/// `.voicepack` 里的清单。要能读也要能存（卸载时按它删），所以是 Codable。
struct VoicePackManifest: Codable {
    struct Entry: Codable {
        let key: String
        let offset: Int
        let length: Int
        let ext: String
    }

    let version: Int
    let pack: String
    let title: String
    let voice: String?
    let rate: String?
    let count: Int
    let generatedAt: String?
    let entries: [Entry]

    enum CodingKeys: String, CodingKey {
        case version, pack, title, voice, rate, count, entries
        case generatedAt = "generated_at"
    }
}

enum VoicePackFormatError: LocalizedError {
    case tooShort
    case badMagic
    case unsupportedVersion(Int)
    case truncatedManifest
    case truncatedPayload
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .tooShort:
            return "文件太小，不是语音包。"
        case .badMagic:
            return "不是有效的语音包（文件头不对）。"
        case .unsupportedVersion(let v):
            return "语音包版本 \(v) 太新，这个 App 读不了。"
        case .truncatedManifest:
            return "语音包清单被截断了，重新下载试试。"
        case .truncatedPayload:
            return "语音包内容不完整，重新下载试试。"
        case .decodeFailed(let detail):
            return "语音包清单解析失败：\(detail)"
        }
    }
}

/// `.voicepack` 的解析与安装。
///
/// 格式（由 `tools/voice/gen_pack.py` 生成）：
/// ```
/// magic    4 B   "JRJP"
/// version  2 B   uint16 大端
/// manLen   4 B   uint32 大端
/// manifest N B   UTF-8 JSON
/// payload  ...   各 mp3 按 offset 顺序拼接
/// ```
/// 不用 zip，是因为 iOS 没有公开的解压 API；这样 App 侧只用 Foundation 就能落地。
enum VoicePackInstaller {

    static let magic = Data("JRJP".utf8)
    static let supportedVersion = 1
    /// 单个语音包体积上限（防 OOM / 磁盘写爆）。
    static let maxPackBytes: Int64 = 512 * 1024 * 1024   // 512 MB

    // MARK: - 解析

    static func parseManifest(_ data: Data) throws -> (manifest: VoicePackManifest, payloadStart: Int) {
        guard data.count >= 10 else { throw VoicePackFormatError.tooShort }
        guard data.prefix(4) == magic else { throw VoicePackFormatError.badMagic }

        let (version, manifestLength): (UInt16, UInt32) = data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return (0, 0) }
            let v = UInt16(bigEndian: base.loadUnaligned(fromByteOffset: 4, as: UInt16.self))
            let n = UInt32(bigEndian: base.loadUnaligned(fromByteOffset: 6, as: UInt32.self))
            return (v, n)
        }

        let versionNumber = Int(version)
        guard versionNumber <= supportedVersion else {
            throw VoicePackFormatError.unsupportedVersion(versionNumber)
        }

        let length = Int(manifestLength)
        let start = 10
        guard length >= 0, data.count >= start + length else {
            throw VoicePackFormatError.truncatedManifest
        }

        let manifestData = data.subdata(in: (data.startIndex + start)..<(data.startIndex + start + length))
        do {
            let manifest = try JSONDecoder().decode(VoicePackManifest.self, from: manifestData)
            return (manifest, start + length)
        } catch {
            throw VoicePackFormatError.decodeFailed(error.localizedDescription)
        }
    }

    // MARK: - 安装

    /// 把整包写进 `VoicePack`，返回写入的条数。
    /// 先全部校验再落盘：中途出错不至于留下半个包。
    @discardableResult
    static func install(_ data: Data, packID: String) throws -> Int {
        let (manifest, payloadStart) = try parseManifest(data)

        // 先算一遍边界，任何一条越界就整体放弃。
        let base = data.startIndex + payloadStart
        for entry in manifest.entries {
            guard entry.offset >= 0, entry.length > 0 else {
                throw VoicePackFormatError.truncatedPayload
            }
            let end = base + entry.offset + entry.length
            guard end <= data.endIndex else {
                throw VoicePackFormatError.truncatedPayload
            }
        }

        for entry in manifest.entries {
            let begin = base + entry.offset
            let end = begin + entry.length
            let chunk = data.subdata(in: begin..<end)
            try VoicePack.write(data: chunk, key: entry.key, extension: entry.ext)
        }

        // 记一份清单，卸载时按它逐个删。
        try saveManifest(manifest, packID: packID)
        return manifest.entries.count
    }

    // MARK: - 已安装记录

    static var registryDirectory: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base
            .appendingPathComponent("JianRiJi", isDirectory: true)
            .appendingPathComponent("VoicePacks", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func manifestURL(packID: String) -> URL {
        registryDirectory.appendingPathComponent("\(packID).json")
    }

    private static func saveManifest(_ manifest: VoicePackManifest, packID: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL(packID: packID), options: .atomic)
    }

    static func installedPackIDs() -> [String] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: registryDirectory.path) else { return [] }
        return files
            .filter { $0.hasSuffix(".json") }
            .map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
            .sorted()
    }

    static func installedManifest(packID: String) -> VoicePackManifest? {
        guard let data = try? Data(contentsOf: manifestURL(packID: packID)) else { return nil }
        return try? JSONDecoder().decode(VoicePackManifest.self, from: data)
    }

    /// 卸载：按清单删掉这个包写进 VoicePack 的音频。
    static func uninstall(packID: String) {
        guard let manifest = installedManifest(packID: packID) else {
            try? FileManager.default.removeItem(at: manifestURL(packID: packID))
            return
        }
        for entry in manifest.entries {
            VoicePack.remove(entry.key)
        }
        try? FileManager.default.removeItem(at: manifestURL(packID: packID))
    }
}

// MARK: - 下载

/// 带进度的下载器：`URLSession.download(for:)` 没有进度回调，这里自己实现。
@unchecked Sendable
final class VoicePackDownloader: NSObject {

    private var continuation: CheckedContinuation<URL, Error>?
    private var onProgress: ((Double) -> Void)?
    private var destination: URL?
    private var session: URLSession?

    private func makeSession() -> URLSession {
        if let session { return session }
        // 回调统一放主线程：进度和 continuation 都在这条线上改，不用再加锁。
        let created = URLSession(
            configuration: .default,
            delegate: self,
            delegateQueue: .main
        )
        session = created
        return created
    }

    deinit { session?.invalidateAndCancel() }

    func download(
        from url: URL,
        to destination: URL,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {
        self.destination = destination
        self.onProgress = onProgress
        try? FileManager.default.removeItem(at: destination)

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let task = makeSession().downloadTask(with: url)
            task.resume()
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        switch result {
        case .success(let url):
            continuation.resume(returning: url)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

extension VoicePackDownloader: URLSessionDownloadDelegate {

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesWritten > VoicePackInstaller.maxPackBytes {
            downloadTask.cancel()
            finish(.failure(VoicePackFormatError.truncatedPayload))
            return
        }
        guard totalBytesExpectedToWrite > 0 else { return }
        let value = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress?(min(1, value))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let destination else {
            finish(.failure(VoicePackFormatError.tooShort))
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        }
    }
}

// MARK: - 界面用的状态

@MainActor
final class VoicePackStore: ObservableObject {

    @Published private(set) var catalog: [RemoteVoicePack] = []
    @Published private(set) var installed: Set<String> = []
    @Published private(set) var installedCounts: [String: Int] = [:]
    @Published private(set) var progress: Double = 0
    @Published private(set) var busyPackID: String?
    @Published private(set) var status: String?
    @Published private(set) var errorText: String?

    private let downloader = VoicePackDownloader()

    static let endpointKey = "speech.packEndpoint"

    var endpoint: String {
        get { UserDefaults.standard.string(forKey: Self.endpointKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.endpointKey) }
    }

    func refreshInstalled() {
        let ids = VoicePackInstaller.installedPackIDs()
        installed = Set(ids)
        var counts: [String: Int] = [:]
        for id in ids {
            if let count = VoicePackInstaller.installedManifest(packID: id)?.count {
                counts[id] = count
            }
        }
        installedCounts = counts
    }

    /// 从 `<endpoint>/catalog.json` 拉目录。
    func loadCatalog() async {
        errorText = nil
        guard let base = normalizedEndpoint() else {
            errorText = "先填一个语音包地址，形如 https://你的服务器/voice"
            return
        }
        guard let url = URL(string: base + "/catalog.json") else {
            errorText = "地址格式不对。"
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                errorText = "目录返回 HTTP \(http.statusCode)。"
                return
            }
            struct Catalog: Decodable {
                let version: Int
                let packs: [RemoteVoicePack]
            }
            let catalogFile = try JSONDecoder().decode(Catalog.self, from: data)
            catalog = catalogFile.packs
            status = "找到 \(catalogFile.packs.count) 个语音包。"
        } catch {
            errorText = "读目录失败：\(error.localizedDescription)"
        }
    }

    func install(_ pack: RemoteVoicePack) async {
        guard busyPackID == nil else { return }
        errorText = nil
        status = nil
        guard pack.bytes > 0, pack.bytes <= VoicePackInstaller.maxPackBytes else {
            errorText = "语音包体积异常（\(pack.bytes) B），已拒绝下载。"
            return
        }
        guard let base = normalizedEndpoint() else {
            errorText = "先填语音包地址。"
            return
        }
        guard let url = URL(string: base + "/" + pack.file) else {
            errorText = "语音包地址不合法。"
            return
        }

        busyPackID = pack.id
        progress = 0
        status = "正在下载 \(pack.title)…"

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(pack.id)-\(UUID().uuidString).voicepack")

        do {
            let fileURL = try await downloader.download(from: url, to: temp) { [weak self] value in
                self?.progress = value
            }
            status = "正在安装…"
            let count = try await Task.detached(priority: .utility) {
                let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                return try VoicePackInstaller.install(data, packID: pack.id)
            }.value
            try? FileManager.default.removeItem(at: fileURL)
            status = "已安装 \(pack.title)：\(count) 条读音。"
            refreshInstalled()
        } catch {
            errorText = "安装失败：\(error.localizedDescription)"
        }

        busyPackID = nil
        progress = 0
    }

    func uninstall(packID: String) {
        VoicePackInstaller.uninstall(packID: packID)
        status = "已卸载 \(packID.uppercased())。"
        refreshInstalled()
    }

    private func normalizedEndpoint() -> String? {
        var base = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }
}
