import Foundation
import Security

/// API Key 只进系统 Keychain，不进 App 的 JSON 存档、不进日志、不显示明文。
/// 每个厂商一个条目：service 固定，account 是厂商 rawValue，换厂商就用对应厂商的 Key。
enum KeychainHelper {
    private static let service = "com.lpdada.jianriji.ai"
    /// 云端登录 token 的条目，与 AI 的 Key 分开存。
    private static let cloudService = "com.lpdada.jianriji.cloud"
    private static let cloudTokenAccount = "token"

    @discardableResult
    static func save(_ key: String, account: String) -> Bool {
        save(key, account: account, service: service)
    }

    static func read(account: String) -> String? {
        read(account: account, service: service)
    }

    static func delete(account: String) {
        delete(account: account, service: service)
    }

    /// 云端登录 token：只进 Keychain，不进学习存档、不进日志。
    @discardableResult
    static func saveCloudToken(_ token: String) -> Bool {
        save(token, account: cloudTokenAccount, service: cloudService)
    }

    static func readCloudToken() -> String? {
        read(account: cloudTokenAccount, service: cloudService)
    }

    static func deleteCloudToken() {
        delete(account: cloudTokenAccount, service: cloudService)
    }

    @discardableResult
    private static func save(_ key: String, account: String, service: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let data = Data(trimmed.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return true
        }
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    private static func read(account: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    private static func delete(account: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
