import Foundation
import Security

/// 密钥只放钥匙串：UserDefaults 是明文 plist，会随 iTunes/iCloud 备份一起被导出来。
enum Secrets {
    private static let service = "app.taosheng.secrets"

    private static let managedKeys = ["asrKey", "doubaoApiKey", "llmKey", "backupPass"]

    static func get(_ key: String) -> String? {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if #available(iOS 13.0, *) {
            q[kSecUseDataProtectionKeychain as String] = true
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ key: String, _ value: String) {
        if value.isEmpty {
            delete(key)
            return
        }
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            for (k, v) in attrs { add[k] = v }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// 把老版本留在 UserDefaults 里的明文密钥搬进钥匙串，搬完立刻抹掉
    static func migrateFromDefaults(_ d: UserDefaults) {
        for key in managedKeys {
            guard let plain = d.string(forKey: key), !plain.isEmpty else { continue }
            if get(key) == nil { set(key, plain) }
            d.removeObject(forKey: key)
        }
    }

    /// 清空所有数据时一并清掉
    static func wipeAll() {
        for key in managedKeys { delete(key) }
    }
}
