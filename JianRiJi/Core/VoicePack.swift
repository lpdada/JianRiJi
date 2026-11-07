import Foundation

/// 本地真人音频库。
///
/// 两种来源放在两个目录里，查找时都看：
/// - `Application Support/JianRiJi/Voice/`：App 自己录的、联网生成的；
/// - `Documents/Voice/`：用户用「文件」App 直接拖进来的（Info.plist 开了文件共享）。
///
/// 文件名就是 key：词条用 `w-<词条id>`，假名用 `k-<假名>`。
/// 只要找到对应音频，朗读就优先用它；找不到才回落到系统 TTS。
enum VoicePack {

    static let supportedExtensions = ["m4a", "mp3", "caf", "wav", "aiff", "aif"]

    // MARK: - 目录

    static var appDirectory: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base
            .appendingPathComponent("JianRiJi", isDirectory: true)
            .appendingPathComponent("Voice", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 需要 Info.plist 里的 UIFileSharingEnabled 才对外可见。
    static var documentsDirectory: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("Voice", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static var searchDirectories: [URL] { [documentsDirectory, appDirectory] }

    // MARK: - Key

    static func key(forWord id: String) -> String { "w-\(id)" }

    static func key(forKana kana: String) -> String { "k-\(kana)" }

    // MARK: - 查询

    static func url(for key: String) -> URL? {
        let fm = FileManager.default
        for dir in searchDirectories {
            for ext in supportedExtensions {
                let candidate = dir.appendingPathComponent("\(key).\(ext)")
                if fm.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }

    static func has(_ key: String) -> Bool { url(for: key) != nil }

    static func url(forWord id: String) -> URL? { url(for: key(forWord: id)) }

    /// 已经录/生成好的词条音频数量（设置页显示用）。
    static func wordAudioCount() -> Int {
        allKeys().filter { $0.hasPrefix("w-") }.count
    }

    static func allKeys() -> Set<String> {
        let fm = FileManager.default
        var keys = Set<String>()
        for dir in searchDirectories {
            guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in files {
                let url = URL(fileURLWithPath: name)
                if supportedExtensions.contains(url.pathExtension.lowercased()) {
                    keys.insert(url.deletingPathExtension().lastPathComponent)
                }
            }
        }
        return keys
    }

    static func totalBytes() -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        for dir in searchDirectories {
            guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in files {
                let path = dir.appendingPathComponent(name).path
                if let attrs = try? fm.attributesOfItem(atPath: path),
                   let size = attrs[.size] as? NSNumber {
                    total += size.int64Value
                }
            }
        }
        return total
    }

    // MARK: - 写入 / 删除

    static func write(data: Data, key: String, extension ext: String) throws {
        let target = appDirectory.appendingPathComponent("\(key).\(ext)")
        try data.write(to: target, options: .atomic)
    }

    /// 把外部文件拷进库里。同名旧文件先删。
    @discardableResult
    static func importAudio(from source: URL, key: String) throws -> URL {
        let fm = FileManager.default
        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            throw VoicePackError.unsupportedFormat(ext)
        }
        // 拖进来的文件可能在 Documents/Voice 里，先拷到安全位置再加锁。
        let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        try? fm.removeItem(at: staging)
        try fm.copyItem(at: source, to: staging)
        defer { try? fm.removeItem(at: staging) }

        for existing in searchDirectories {
            for oldExt in supportedExtensions {
                let old = existing.appendingPathComponent("\(key).\(oldExt)")
                if fm.fileExists(atPath: old.path) { try? fm.removeItem(at: old) }
            }
        }

        let target = appDirectory.appendingPathComponent("\(key).\(ext)")
        try fm.copyItem(at: staging, to: target)
        return target
    }

    static func remove(_ key: String) {
        let fm = FileManager.default
        for dir in searchDirectories {
            for ext in supportedExtensions {
                let file = dir.appendingPathComponent("\(key).\(ext)")
                if fm.fileExists(atPath: file.path) { try? fm.removeItem(at: file) }
            }
        }
    }

    static func removeAll() {
        let fm = FileManager.default
        for dir in searchDirectories {
            guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in files {
                try? fm.removeItem(at: dir.appendingPathComponent(name))
            }
        }
    }
}

/// 语音包里出现不支持的文件格式。
enum VoicePackError: LocalizedError {
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "不支持的音频格式 .\(ext)，用 m4a / mp3 / caf / wav。"
        }
    }
}