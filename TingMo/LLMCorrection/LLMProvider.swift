import Foundation

/// Supported API wire formats for LLM correction.
enum LLMProviderID: String, CaseIterable, Codable, Identifiable, Sendable {
    case openAICompatible = "openai-compatible"
    case anthropic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAICompatible:
            "OpenAI-compatible"
        case .anthropic:
            "Anthropic"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .openAICompatible:
            "https://api.openai.com/v1/chat/completions"
        case .anthropic:
            "https://api.anthropic.com/v1/messages"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAICompatible:
            "gpt-4o-mini"
        case .anthropic:
            "claude-3-5-haiku-latest"
        }
    }

    var keychainService: String {
        switch self {
        case .openAICompatible:
            "tingmo.llm.openai-compatible"
        case .anthropic:
            "tingmo.llm.anthropic"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "openai", "openai-compatible", "openaiCompatible":
            self = .openAICompatible
        case "anthropic":
            self = .anthropic
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported LLM provider '\(rawValue)'"
            )
        }
    }
}

/// User-editable correction settings. API keys are intentionally referenced
/// by service identifier only; secret values never enter Codable presets.
struct LLMConfig: Codable, Equatable, Sendable {
    var enabled: Bool
    var provider: LLMProviderID
    var endpoint: String
    var model: String
    var systemPrompt: String
    var temperature: Double
    var keychainService: String?

    init(
        enabled: Bool = false,
        provider: LLMProviderID = .openAICompatible,
        endpoint: String? = nil,
        model: String? = nil,
        systemPrompt: String = Self.defaultSystemPrompt,
        temperature: Double = 0.3,
        keychainService: String? = nil
    ) {
        self.enabled = enabled
        self.provider = provider
        self.endpoint = endpoint ?? provider.defaultEndpoint
        self.model = model ?? provider.defaultModel
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.keychainService = keychainService
    }

    var effectiveEndpoint: String {
        endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? provider.defaultEndpoint
            : endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var effectiveModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? provider.defaultModel
            : model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var effectiveSystemPrompt: String {
        systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultSystemPrompt
            : systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var effectiveKeychainService: String {
        guard let keychainService,
              !keychainService.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return provider.keychainService
        }
        return keychainService.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedTemperature: Double {
        min(max(temperature, 0), 2)
    }

    var usesLocalEndpoint: Bool {
        guard let host = URL(string: effectiveEndpoint)?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    static let defaultSystemPrompt = """
You correct speech-to-text transcripts. Preserve the user's meaning, language, tone, and formatting intent. Fix recognition mistakes, punctuation, casing, and obvious homophones. Return only the corrected transcript.
"""
}

/// A single context fragment collected before correction.
struct LLMContextItem: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case selectedText
        case inputText
        case windowTitle
        case applicationName
        case clipboard
        case knowledgeBase
        case custom
    }

    var kind: Kind
    var text: String
    var priority: Int
    var isSensitive: Bool

    init(kind: Kind, text: String, priority: Int, isSensitive: Bool = false) {
        self.kind = kind
        self.text = text
        self.priority = priority
        self.isSensitive = isSensitive
    }
}

/// Provider-neutral request consumed by OpenAI-compatible, Anthropic, and
/// future adapters.
struct LLMCorrectionRequest: Equatable, Sendable {
    var transcript: String
    var context: [LLMContextItem]
    var config: LLMConfig

    init(transcript: String, context: [LLMContextItem] = [], config: LLMConfig) {
        self.transcript = transcript
        self.context = context
        self.config = config
    }

    var trimmedTranscript: String {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nonSensitiveContext: [LLMContextItem] {
        context.filter { !$0.isSensitive && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                lhs.priority == rhs.priority ? lhs.kind.rawValue < rhs.kind.rawValue : lhs.priority < rhs.priority
            }
    }
}

struct LLMUsage: Codable, Equatable, Sendable {
    var inputTokens: Int?
    var outputTokens: Int?
    var totalTokens: Int?
}

struct LLMCorrectionResponse: Equatable, Sendable {
    var correctedText: String
    var provider: LLMProviderID
    var model: String
    var usage: LLMUsage?
}

enum LLMCorrectionPrompt {
    static func userMessage(for request: LLMCorrectionRequest) -> String {
        let context = contextBlock(for: request.nonSensitiveContext)
        if context.isEmpty {
            return """
Correct this transcript. Return only the corrected transcript.

Transcript:
\(request.trimmedTranscript)
"""
        }

        return """
Use this context only when it helps correct the transcript:
\(context)

Correct this transcript. Return only the corrected transcript.

Transcript:
\(request.trimmedTranscript)
"""
    }

    private static func contextBlock(for items: [LLMContextItem]) -> String {
        guard !items.isEmpty else { return "" }
        return items.map { item in
            "- \(item.kind.rawValue): \(item.text.trimmingCharacters(in: .whitespacesAndNewlines))"
        }.joined(separator: "\n")
    }
}

/// Unified correction adapter protocol. Concrete network adapters arrive in
/// M3-2 and M3-3; this protocol is the contract the pipeline will use.
protocol LLMProvider: Sendable {
    var providerID: LLMProviderID { get }

    func correct(_ request: LLMCorrectionRequest) async throws -> LLMCorrectionResponse
    func validate(_ config: LLMConfig) throws
}

extension LLMProvider {
    func validate(_ config: LLMConfig) throws {
        guard config.enabled else { throw LLMProviderError.disabled }
        guard config.provider == providerID else { throw LLMProviderError.unsupportedProvider(config.provider) }
        guard let url = URL(string: config.effectiveEndpoint),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host?.isEmpty == false
        else {
            throw LLMProviderError.invalidEndpoint(config.effectiveEndpoint)
        }
        guard !config.effectiveModel.isEmpty else { throw LLMProviderError.missingModel }
    }
}

enum LLMProviderError: LocalizedError {
    case disabled
    case unsupportedProvider(LLMProviderID)
    case emptyTranscript
    case missingAPIKey
    case missingModel
    case invalidEndpoint(String)
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int, body: String?)
    case network(underlying: Error)
    case timeout
    case cancelled
    case invalidResponse
    case missingCorrectedText

    var errorDescription: String? {
        switch self {
        case .disabled:
            "LLM correction is disabled."
        case .unsupportedProvider(let provider):
            "Unsupported LLM provider: \(provider.displayName)."
        case .emptyTranscript:
            "Transcript is empty."
        case .missingAPIKey:
            "LLM API key is missing. Enter it in Settings."
        case .missingModel:
            "LLM model is missing."
        case .invalidEndpoint(let endpoint):
            "LLM endpoint is invalid: \(endpoint)"
        case .unauthorized:
            "LLM authentication failed - the API key is invalid."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                "LLM rate limit exceeded. Retry after \(Int(retryAfter))s."
            } else {
                "LLM rate limit exceeded."
            }
        case .server(let status, _):
            "LLM server returned an error (\(status))."
        case .network(let error):
            "LLM network error: \(error.localizedDescription)"
        case .timeout:
            "LLM request timed out."
        case .cancelled:
            "LLM request cancelled."
        case .invalidResponse:
            "Unexpected response from the LLM provider."
        case .missingCorrectedText:
            "LLM response did not include corrected text."
        }
    }
}
