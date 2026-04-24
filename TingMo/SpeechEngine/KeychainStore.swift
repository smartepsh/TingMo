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
            NSLog("[TingMo][Keychain] set → delete (empty value) service=\(service)")
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
        if status == errSecSuccess {
            NSLog("[TingMo][Keychain] set updated service=\(service) bytes=\(data.count)")
            return true
        }
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            NSLog("[TingMo][Keychain] set inserted service=\(service) bytes=\(data.count) status=\(addStatus)")
            return addStatus == errSecSuccess
        }
        NSLog("[TingMo][Keychain] set FAILED service=\(service) status=\(status)")
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
        NSLog("[TingMo][Keychain] delete service=\(service) status=\(status)")
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
