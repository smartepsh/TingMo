import CryptoKit
import Foundation

struct STTInstance: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var displayName: String
    var provider: STTProviderID
    var keychainService: String
    var verifiedFingerprint: String?

    init(
        id: UUID = UUID(),
        displayName: String? = nil,
        provider: STTProviderID = .groq,
        keychainService: String? = nil,
        verifiedFingerprint: String? = nil
    ) {
        let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        self.id = id
        self.displayName = trimmedName
        self.provider = provider
        self.keychainService = keychainService ?? Self.keychainService(for: id)
        self.verifiedFingerprint = verifiedFingerprint
    }

    func computeFingerprint(apiKeyHint: String?) -> String {
        let raw = [
            provider.rawValue,
            apiKeyHint ?? "__no_key__",
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func isVerified(apiKeyHint: String?) -> Bool {
        guard let stored = verifiedFingerprint, !stored.isEmpty else { return false }
        return stored == computeFingerprint(apiKeyHint: apiKeyHint)
    }

    mutating func clearVerified() {
        verifiedFingerprint = nil
    }

    static func keychainService(for id: UUID) -> String {
        "tingmo.stt.instance.\(id.uuidString)"
    }
}
