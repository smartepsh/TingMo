import Foundation

struct LLMInstance: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var displayName: String
    var provider: LLMProviderID
    var endpoint: String
    var model: String
    var keychainService: String

    init(
        id: UUID = UUID(),
        displayName: String? = nil,
        provider: LLMProviderID = .openAICompatible,
        endpoint: String? = nil,
        model: String? = nil,
        keychainService: String? = nil
    ) {
        let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        self.id = id
        self.displayName = trimmedName
        self.provider = provider
        self.endpoint = endpoint ?? ""
        self.model = model ?? ""
        self.keychainService = keychainService ?? Self.keychainService(for: id)
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

    static func defaultInstance(id: UUID = UUID()) -> LLMInstance {
        LLMInstance(id: id)
    }

    static func keychainService(for id: UUID) -> String {
        "tingmo.llm.instance.\(id.uuidString)"
    }
}
