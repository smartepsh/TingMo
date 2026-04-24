import Foundation
import Security

/// Minimal keychain wrapper for storing per-service secrets (API keys).
///
/// Values are stored under the app's bundle ID with a caller-supplied
/// `service` identifier (e.g. `"tingmo.groq"`), so each remote engine gets
/// its own slot. Only the current user / device can read them; nothing is
/// ever printed in logs.
enum KeychainStore {
    static let defaultAccount = "api-key"

    /// Save or update a secret for the given service. Passing an empty
    /// string deletes the entry instead, so "clear the key" is just
    /// `set("", for: …)`.
    @discardableResult
    static func set(_ value: String, for service: String, account: String = defaultAccount) -> Bool {
        if value.isEmpty {
            return delete(service: service, account: account)
        }
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    /// Read back a previously-saved secret; `nil` means no entry.
    static func get(service: String, account: String = defaultAccount) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    @discardableResult
    static func delete(service: String, account: String = defaultAccount) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
