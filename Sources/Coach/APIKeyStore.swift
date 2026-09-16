import Foundation
import Security

/// Secrets in the Keychain (Anthropic API key, Coach session token). Never on disk in plain text.
enum APIKeyStore {
    private static let service = "com.alan.autopiloto"
    static let anthropicKey = "anthropic-api-key"
    static let coachSession = "coach-session-token"
    static let appleUser = "apple-user-id"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func load(_ account: String = anthropicKey) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, account: String = anthropicKey) {
        let data = Data(value.utf8)
        var add = query(account)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
    }

    static func delete(_ account: String = anthropicKey) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
