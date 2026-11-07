import CryptoKit
import Foundation

/// 服务器合成：把文本发到用户自己的 Edge TTS 代理，拿回 MP3 再播。
///
/// 调用约定（已实测）：POST {base}/tts，JSON {"text","voice","rate_percent"}，
/// 200 返回 audio/mpeg；GET {base}/health 测活；单次最多 1000 字，超时 15 秒。
/// 地址留空表示只用系统语音。本接口不需要 Key。
final class ServerTTS {
    static let defaultBaseURL = "https://asr.ysloving.com"
    static let nanamiVoiceID = "ja-JP-NanamiNeural"
    static let maxTextLength = 1_000
    static let defaultTimeout: Double = 15

    enum Failure: LocalizedError {
        case notConfigured
        case invalidURL
        case http(status: Int, body: String)
        case emptyAudio
        case malformedAudio
        case textTooLong(limit: Int)
        case network(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "没有配置朗读服务器"
            case .invalidURL: return "朗读服务器地址无效"
            case .http(let status, let body):
                let snippet = body.isEmpty ? "" : "：\(body.prefix(120))"
                return "朗读服务器返回 \(status)\(snippet)"
            case .emptyAudio: return "朗读服务器没有返回音频"
            case .malformedAudio: return "朗读服务器返回的不是 MP3"
            case .textTooLong(let limit): return "这一段超过 \(limit) 字"
            case .network(let message): return "连接朗读服务器失败：\(message)"
            }
        }
    }

    var baseURL: String
    /// 测试可注入；返回响应体 + 状态码。
    var send: (URLRequest) async throws -> (Data, Int)

    init(
        baseURL: String,
        send: @escaping (URLRequest) async throws -> (Data, Int) = ServerTTS.defaultSend
    ) {
        self.baseURL = baseURL
        self.send = send
    }

    static func defaultSend(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Failure.network("响应不是 HTTP")
        }
        return (data, http.statusCode)
    }

    // MARK: - 纯函数（可单测）

    /// 接受 `https://host`、`https://host/`、无协议的 `host`、完整的 `…/tts`。
    /// 要求 http/https + 有 host，否则返回 nil。
    static func endpointURL(for base: String) -> URL? {
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty else { return nil }
        // 只有协议、没有 host 的输入（如 "https://" 去掉斜杠后剩 "https:"）不能当地址：
        // 不拦的话下一步会把它当裸 host 补成 "https://https:/tts"。
        guard !trimmed.hasSuffix(":") else { return nil }
        // 没写协议的裸地址最常见是手误，默认补 https 而不是直接报错。
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        if !trimmed.lowercased().hasSuffix("/tts") { trimmed += "/tts" }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    static func makeRequest(
        baseURL: String,
        text: String,
        voiceID: String,
        ratePercent: Int,
        timeout: Double
    ) throws -> URLRequest {
        guard text.count <= maxTextLength else {
            throw Failure.textTooLong(limit: maxTextLength)
        }
        guard let url = endpointURL(for: baseURL) else {
            throw baseURL.trimmingCharacters(in: .whitespaces).isEmpty
                ? Failure.notConfigured
                : Failure.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = min(max(timeout, 5), 30)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        let payload: [String: Any] = [
            "text": text,
            "voice": voiceID,
            "rate_percent": ratePercent
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    /// 便宜的嗅探：JSON 错误体绝不能交给播放器。
    /// ID3 标签开头，或 MPEG 帧同步（首字节 0xFF、第二字节高三位全 1）。
    static func looksLikeMP3(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        if data.count >= 3,
           data[data.startIndex] == 0x49,
           data[data.startIndex + 1] == 0x44,
           data[data.startIndex + 2] == 0x33 {
            return true
        }
        return data[data.startIndex] == 0xFF && (data[data.startIndex + 1] & 0xE0) == 0xE0
    }

    /// App 语速 0.45 → Edge +0%，每 0.05 → ±10%，夹在 -50…+50。
    static func ratePercent(forSpeechRate rate: Double) -> Int {
        let percent = (rate - 0.45) * 200
        return min(max(Int(percent.rounded()), -50), 50)
    }

    /// 按 。！？!? 与换行切成每段 ≤ limit 字的块；超长单句硬切。
    static func chunks(of text: String, limit: Int = maxTextLength) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed.isEmpty ? [] : [trimmed] }

        let terminators: Set<Character> = ["。", "！", "？", "!", "?", "\n"]
        var pieces: [String] = []
        var buffer = ""
        for character in trimmed {
            buffer.append(character)
            if terminators.contains(character) {
                pieces.append(buffer)
                buffer = ""
            }
        }
        if !buffer.isEmpty { pieces.append(buffer) }

        var result: [String] = []
        var current = ""
        for piece in pieces {
            if piece.count > limit {
                // 单句本身就超长：硬切。
                if !current.isEmpty { result.append(current); current = "" }
                var remaining = Substring(piece)
                while remaining.count > limit {
                    let cut = remaining.index(remaining.startIndex, offsetBy: limit)
                    result.append(String(remaining[..<cut]))
                    remaining = remaining[cut...]
                }
                current = String(remaining)
                continue
            }
            if current.count + piece.count > limit {
                result.append(current)
                current = piece
            } else {
                current += piece
            }
        }
        if !current.isEmpty { result.append(current) }
        return result.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    // MARK: - 调用

    func audio(text: String, voiceID: String, ratePercent: Int, timeout: Double = defaultTimeout) async throws -> Data {
        let request = try Self.makeRequest(
            baseURL: baseURL,
            text: text,
            voiceID: voiceID,
            ratePercent: ratePercent,
            timeout: timeout
        )
        let data: Data
        let status: Int
        do {
            (data, status) = try await send(request)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.network(error.localizedDescription)
        }
        guard (200...299).contains(status) else {
            throw Failure.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        guard !data.isEmpty else { throw Failure.emptyAudio }
        guard Self.looksLikeMP3(data) else { throw Failure.malformedAudio }
        return data
    }
}

// MARK: - 磁盘缓存

/// 合成 MP3 的文件缓存，键 = SHA256(voice|rate|text)。
/// 上限 200 个文件 / 50MB，按修改时间做 LRU 淘汰。
final class ServerTTSCache {
    static let shared = ServerTTSCache()

    static let maxFiles = 200
    static let limitBytes = 50 * 1024 * 1024

    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = base.appendingPathComponent("ServerTTS", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    static func key(text: String, voiceID: String, ratePercent: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let material = "\(voiceID)|\(ratePercent)|\(normalized)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func fileURL(forKey key: String) -> URL {
        directory.appendingPathComponent(key + ".mp3")
    }

    /// 缓存命中，同时刷新修改时间（LRU 用）。
    func existing(forKey key: String) -> Data? {
        let url = fileURL(forKey: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return try? Data(contentsOf: url)
    }

    @discardableResult
    func store(_ data: Data, forKey key: String) throws -> Data {
        let url = fileURL(forKey: key)
        try data.write(to: url, options: .atomic)
        evictIfNeeded()
        return data
    }

    func currentSize() -> Int {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return items.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + size
        }
    }

    /// 按修改时间从旧到新删，直到文件数与总字节都回到上限内。
    @discardableResult
    func evictIfNeeded() -> Int {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return 0 }

        struct Entry { let url: URL; let size: Int; let date: Date }
        var entries: [Entry] = items.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            return Entry(url: url, size: values.fileSize ?? 0, date: values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > Self.limitBytes || entries.count > Self.maxFiles else { return 0 }

        entries.sort { $0.date < $1.date }
        var removed = 0
        for entry in entries where total > Self.limitBytes || entries.count - removed > Self.maxFiles {
            if (try? FileManager.default.removeItem(at: entry.url)) != nil {
                total -= entry.size
                removed += 1
            }
        }
        return removed
    }
}
