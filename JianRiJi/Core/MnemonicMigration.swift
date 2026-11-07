import Foundation

/// AI 助记缓存的文件位置。`MnemonicAI` 与一次性迁移脚本共用同一份路径逻辑，
/// 迁移写的地方就是缓存读的地方，不会写丢。
enum MnemonicFiles {
    private static let directoryName = "Mnemonics"

    static var directory: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base
            .appendingPathComponent("JianRiJi", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 文件名直接用词条 id（id 只含字母数字与短横线，可安全当文件名）。
    static func fileURL(forWordID id: String) -> URL {
        directory.appendingPathComponent("\(sanitize(id)).txt")
    }

    private static func sanitize(_ id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(mapped)
    }
}

/// 把 v1 存在 UserDefaults 里的 AI 助记缓存搬到 Application Support。
/// 只跑一次，用 flag 记住；逐条搬，搬完立刻删旧键，中途被杀也不会丢数据。
enum MnemonicMigration {
    private static let doneKey = "migration.mnemonic.v2.done"

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        let prefix = "classic.mnemonic.ai."
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }
        for key in keys {
            guard let raw = defaults.string(forKey: key), !raw.isEmpty else {
                defaults.removeObject(forKey: key)
                continue
            }
            let id = String(key.dropFirst(prefix.count))
            let url = MnemonicFiles.fileURL(forWordID: id)
            try? raw.write(to: url, atomically: true, encoding: .utf8)
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: doneKey)
    }
}
