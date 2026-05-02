import CryptoKit
import Foundation

struct LLMInstance: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var displayName: String
    var provider: LLMProviderID
    var endpoint: String
    var model: String
    var keychainService: String
    var verifiedFingerprint: String?

    init(
        id: UUID = UUID(),
        displayName: String? = nil,
        provider: LLMProviderID = .openAICompatible,
        endpoint: String? = nil,
        model: String? = nil,
        keychainService: String? = nil,
        verifiedFingerprint: String? = nil
    ) {
        let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        self.id = id
        self.displayName = trimmedName
        self.provider = provider
        self.endpoint = endpoint ?? ""
        self.model = model ?? ""
        self.keychainService = keychainService ?? Self.keychainService(for: id)
        self.verifiedFingerprint = verifiedFingerprint
    }

    /// The stored base URL, trimmed and stripped of the endpoint path if an
    /// older version saved the full URL.
    var effectiveBaseURL: String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return provider.defaultBaseURL }
        if trimmed.hasSuffix(provider.endpointPath) {
            return String(trimmed.dropLast(provider.endpointPath.count))
        }
        return trimmed
    }

    /// Full endpoint URL computed from the base URL and the provider's path.
    var effectiveEndpoint: String {
        effectiveBaseURL + provider.endpointPath
    }

    var effectiveModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? provider.defaultModel
            : model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Computes a fingerprint from the fields that determine connectivity.
    /// When the API key hint is nil (no key stored), the fingerprint uses an
    /// empty sentinel so it will never match a stored fingerprint that was
    /// computed with a real key.
    func computeFingerprint(apiKeyHint: String?) -> String {
        let raw = [
            provider.rawValue,
            effectiveBaseURL,
            effectiveModel,
            apiKeyHint ?? "__no_key__",
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Whether the stored verified fingerprint still matches the current
    /// configuration and key hint.
    func isVerified(apiKeyHint: String?) -> Bool {
        guard let stored = verifiedFingerprint, !stored.isEmpty else { return false }
        return stored == computeFingerprint(apiKeyHint: apiKeyHint)
    }

    /// Clears the verified fingerprint (e.g. when a field changes).
    mutating func clearVerified() {
        verifiedFingerprint = nil
    }

    static func defaultInstance(id: UUID = UUID()) -> LLMInstance {
        LLMInstance(id: id)
    }

    static func keychainService(for id: UUID) -> String {
        "tingmo.llm.instance.\(id.uuidString)"
    }
}
