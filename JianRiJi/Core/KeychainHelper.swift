import Foundation
import Security

/// Keychain 操作失败的原因。带 `OSStatus`，出问题时能直接对着 `SecBase.h` 查。
enum KeychainError: LocalizedError {
    case emptyKey
    /// 设备锁着，Keychain 暂时不可读（`errSecInteractionNotAllowed`）。重试即可，不是配置错误。
    case locked
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            return "API Key 是空的。"
        case .locked:
            return "设备处于锁定状态，暂时读不到 Keychain。解锁后再试。"
        case .status(let code):
            return "Keychain 操作失败（OSStatus \(code)）。"
        }
    }

    var osStatus: OSStatus? {
        if case .status(let code) = self { return code }
        return nil
    }
}

/// API Key 只进系统 Keychain，不进 App 的 JSON 存档、不进日志、不显示明文。
/// 每个厂商一个条目：service 固定，account 是厂商 rawValue，换厂商就用对应厂商的 Key。
///
/// 可访问性用 `AfterFirstUnlockThisDeviceOnly`：
/// - `AfterFirstUnlock` 让后台朗读（锁屏后）仍能取到 Key；
/// - `ThisDeviceOnly` 阻止 Key 跟着 iCloud Keychain 同步、跟着备份迁到新设备 ——
///   原实现用的 `WhenUnlocked` 是「随备份/同步走」的档位，等于把用户的 API Key
///   悄悄复制到 iCloud 和每一台恢复过备份的设备上。
///
/// `accessGroup` 现在传 nil 即可；将来加 Widget / Share Extension 时，
/// 两边都用同一个 group 才能共享同一个 Key。
enum KeychainHelper {
    private static let service = "com.lpdada.jianriji.ai"

    /// 所有查询共用的基础字段。显式关闭同步，避免被 iCloud Keychain 带走。
    private static func baseQuery(account: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup, !accessGroup.isEmpty {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    // MARK: - 写

    @discardableResult
    static func save(_ key: String, account: String) -> Bool {
        do {
            try saveOrThrow(key, account: account)
            return true
        } catch {
            #if DEBUG
            print("[JianRiJi] Keychain 保存失败：\(error.localizedDescription)")
            #endif
            return false
        }
    }

    static func saveOrThrow(_ key: String, account: String, accessGroup: String? = nil) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw KeychainError.emptyKey }
        let data = Data(trimmed.utf8)
        let query = baseQuery(account: account, accessGroup: accessGroup)

        // 已存在就只更新值 + 可访问性；不存在才新增。
        // 直接 update 一份带 class 的 attributes 在部分系统上会返回 errSecParam。
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.status(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.status(addStatus)
        }
    }

    // MARK: - 读

    static func read(account: String) -> String? {
        try? readOrThrow(account: account)
    }

    static func has(account: String) -> Bool {
        read(account: account) != nil
    }

    static func readOrThrow(account: String, accessGroup: String? = nil) throws -> String {
        var query = baseQuery(account: account, accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let key = String(data: data, encoding: .utf8),
                  !key.isEmpty else {
                throw KeychainError.emptyKey
            }
            return key
        case errSecItemNotFound:
            throw KeychainError.status(status)
        case errSecInteractionNotAllowed:
            // 锁屏。后台任务里读不到 Key 是正常情况，不该被当成「没配置」。
            throw KeychainError.locked
        default:
            throw KeychainError.status(status)
        }
    }

    // MARK: - 删

    static func delete(account: String) {
        let query = baseQuery(account: account, accessGroup: nil)
        SecItemDelete(query as CFDictionary)
    }

    /// 换厂商 / 清空 Key 时一次清完，避免 Keychain 里留孤儿条目。
    static func deleteAll(accounts: [String]) {
        for account in accounts { delete(account: account) }
    }
}
