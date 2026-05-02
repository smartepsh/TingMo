import CryptoKit
import Foundation

enum EncryptedKeyStore {
    private static let filename = "keys.enc"

    // MARK: - Public API

    @discardableResult
    static func set(_ value: String, for service: String) -> Bool {
        if value.isEmpty {
            return delete(service: service)
        }

        var entries = readEntries()
        let hint = String(value.suffix(4))
        let prefix = String(value.prefix(4))
        entries[service] = Entry(ciphertext: Data(), hint: hint, prefix: prefix, plaintext: value)

        guard let data = encrypt(entries) else { return false }
        return writeData(data)
    }

    static func get(service: String) -> String? {
        let entries = readEntries()
        return entries[service]?.plaintext
    }

    static func hint(service: String) -> String? {
        let entries = readEntries()
        return entries[service]?.hint
    }

    static func keyHint(service: String) -> String? {
        let entries = readEntries()
        guard let entry = entries[service] else { return nil }
        let suffix = entry.hint ?? ""
        let prefix = entry.prefix ?? String(entry.plaintext.prefix(4))
        guard !prefix.isEmpty || !suffix.isEmpty else { return nil }
        return "\(prefix)...\(suffix)"
    }

    @discardableResult
    static func delete(service: String) -> Bool {
        var entries = readEntries()
        guard entries.removeValue(forKey: service) != nil else { return true }
        guard let data = encrypt(entries) else { return false }
        return writeData(data)
    }

    // MARK: - Storage types

    private struct Entry: Codable {
        let ciphertext: Data
        let hint: String
        let prefix: String?
        let plaintext: String
    }

    // MARK: - Encryption

    private static func encryptionKey() -> SymmetricKey? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let salt = "tingmo.key.store.v1"
        let inputKey = SymmetricKey(data: Data(bundleID.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: Data(salt.utf8),
            info: Data("encrypted-api-keys".utf8),
            outputByteCount: 16
        )
    }

    private static func encrypt(_ entries: [String: Entry]) -> Data? {
        guard let key = encryptionKey() else { return nil }
        guard let plaintext = try? JSONEncoder().encode(entries) else { return nil }
        guard let sealed = try? AES.GCM.seal(plaintext, using: key) else { return nil }
        guard let combined = sealed.combined else { return nil }
        return combined
    }

    private static func decrypt(_ data: Data) -> [String: Entry]? {
        guard let key = encryptionKey() else { return nil }
        guard let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        guard let decrypted = try? AES.GCM.open(box, using: key) else { return nil }
        return try? JSONDecoder().decode([String: Entry].self, from: decrypted)
    }

    // MARK: - File I/O

    private static func fileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("TingMo")
            .appendingPathComponent(filename)
    }

    private static func readEntries() -> [String: Entry] {
        guard let url = fileURL(),
              let data = try? Data(contentsOf: url),
              let entries = decrypt(data)
        else { return [:] }
        return entries
    }

    private static func writeData(_ data: Data) -> Bool {
        guard let url = fileURL() else { return false }
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            NSLog("[TingMo][EncryptedKeyStore] write failed: \(error)")
            return false
        }
    }

}
