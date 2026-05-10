import Foundation

/// Wire format used to communicate with the LLM API.
enum WireFormat: String, Codable, Sendable {
    case openai
    case anthropic
}

/// Supported LLM providers. Each carries its own default endpoint and model.
/// OpenAI-compatible providers share the same wire format; Anthropic uses its own.
enum LLMProviderID: String, CaseIterable, Codable, Identifiable, Sendable {
    case openAICompatible = "openai-compatible"
    case openai
    case anthropic
    case google
    case groq
    case together
    case fireworks
    case deepseek
    case mistral
    case perplexity
    case xai
    case openrouter
    case ollama
    case lmstudio
    case cerebras
    case sambanova
    case cohere

    var id: String { rawValue }

    var wireFormat: WireFormat {
        switch self {
        case .anthropic:
            return .anthropic
        default:
            return .openai
        }
    }

    var displayName: String {
        switch self {
        case .openAICompatible: "OpenAI-compatible"
        case .openai: "OpenAI"
        case .anthropic: "Anthropic"
        case .google: "Google Gemini"
        case .groq: "Groq"
        case .together: "Together AI"
        case .fireworks: "Fireworks AI"
        case .deepseek: "DeepSeek"
        case .mistral: "Mistral"
        case .perplexity: "Perplexity"
        case .xai: "xAI (Grok)"
        case .openrouter: "OpenRouter"
        case .ollama: "Ollama"
        case .lmstudio: "LM Studio"
        case .cerebras: "Cerebras"
        case .sambanova: "SambaNova"
        case .cohere: "Cohere"
        }
    }

    /// The path component appended to the base URL to form the full endpoint.
    var endpointPath: String {
        switch self {
        case .anthropic:
            "/v1/messages"
        default:
            "/v1/chat/completions"
        }
    }

    /// Default base URL (without the endpoint path).
    var defaultBaseURL: String {
        switch self {
        case .openAICompatible, .openai:
            "https://api.openai.com"
        case .anthropic:
            "https://api.anthropic.com"
        case .google:
            "https://generativelanguage.googleapis.com/v1beta/openai"
        case .groq:
            "https://api.groq.com/openai"
        case .together:
            "https://api.together.xyz"
        case .fireworks:
            "https://api.fireworks.ai/inference/v1"
        case .deepseek:
            "https://api.deepseek.com"
        case .mistral:
            "https://api.mistral.ai"
        case .perplexity:
            "https://api.perplexity.ai"
        case .xai:
            "https://api.x.ai"
        case .openrouter:
            "https://openrouter.ai/api"
        case .ollama:
            "http://localhost:11434"
        case .lmstudio:
            "http://localhost:1234"
        case .cerebras:
            "https://api.cerebras.ai"
        case .sambanova:
            "https://api.sambanova.ai"
        case .cohere:
            "https://api.cohere.com"
        }
    }

    /// Full default endpoint (base URL + path). Used for backward compatibility
    /// and by adapters that need the complete URL.
    var defaultEndpoint: String {
        defaultBaseURL + endpointPath
    }

    var defaultModel: String {
        switch self {
        case .openAICompatible, .openai:
            "gpt-4o-mini"
        case .anthropic:
            "claude-3-5-haiku-latest"
        case .google:
            "gemini-2.0-flash"
        case .groq:
            "llama-3.3-70b-versatile"
        case .together:
            "meta-llama/Llama-3.3-70B-Instruct-Turbo"
        case .fireworks:
            "accounts/fireworks/models/llama-v3p3-70b-instruct"
        case .deepseek:
            "deepseek-chat"
        case .mistral:
            "mistral-small-latest"
        case .perplexity:
            "sonar"
        case .xai:
            "grok-3-mini"
        case .openrouter:
            "meta-llama/llama-3.3-70b-instruct"
        case .ollama:
            "llama3.3"
        case .lmstudio:
            "llama-3.3-70b-instruct"
        case .cerebras:
            "llama-3.3-70b"
        case .sambanova:
            "Meta-Llama-3.3-70B-Instruct"
        case .cohere:
            "command-a-03-2025"
        }
    }

    var keychainService: String {
        switch self {
        case .openAICompatible:
            "tingmo.llm.openai-compatible"
        case .openai:
            "tingmo.llm.openai"
        case .anthropic:
            "tingmo.llm.anthropic"
        case .google:
            "tingmo.llm.google"
        case .groq:
            "tingmo.llm.groq"
        case .together:
            "tingmo.llm.together"
        case .fireworks:
            "tingmo.llm.fireworks"
        case .deepseek:
            "tingmo.llm.deepseek"
        case .mistral:
            "tingmo.llm.mistral"
        case .perplexity:
            "tingmo.llm.perplexity"
        case .xai:
            "tingmo.llm.xai"
        case .openrouter:
            "tingmo.llm.openrouter"
        case .ollama:
            "tingmo.llm.ollama"
        case .lmstudio:
            "tingmo.llm.lmstudio"
        case .cerebras:
            "tingmo.llm.cerebras"
        case .sambanova:
            "tingmo.llm.sambanova"
        case .cohere:
            "tingmo.llm.cohere"
        }
    }

    var isLocalProvider: Bool {
        switch self {
        case .ollama, .lmstudio:
            true
        default:
            false
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
        case "google":
            self = .google
        case "groq":
            self = .groq
        case "together":
            self = .together
        case "fireworks":
            self = .fireworks
        case "deepseek":
            self = .deepseek
        case "mistral":
            self = .mistral
        case "perplexity":
            self = .perplexity
        case "xai":
            self = .xai
        case "openrouter":
            self = .openrouter
        case "ollama":
            self = .ollama
        case "lmstudio":
            self = .lmstudio
        case "cerebras":
            self = .cerebras
        case "sambanova":
            self = .sambanova
        case "cohere":
            self = .cohere
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
        self.endpoint = endpoint ?? provider.defaultBaseURL
        self.model = model ?? provider.defaultModel
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.keychainService = keychainService
    }

    /// The stored base URL, trimmed and stripped of the endpoint path if an
    /// older version saved the full URL.
    var effectiveBaseURL: String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return provider.defaultBaseURL }
        // Backward compatibility: strip the endpoint path if the stored value
        // is a full URL from an older version.
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
        if provider.isLocalProvider { return true }
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
        case windowContent
        case screenshotOCR
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
    func runConnectivityCheck(_ config: LLMConfig) async -> LLMProviderError?
    func performConnectivityCheck(config: LLMConfig, apiKey: String) async -> LLMProviderError?
}

extension LLMProvider {
    func validate(_ config: LLMConfig) throws {
        guard config.enabled else { throw LLMProviderError.disabled }
        guard config.provider == providerID || config.provider.wireFormat == providerID.wireFormat else { throw LLMProviderError.unsupportedProvider(config.provider) }
        guard let url = URL(string: config.effectiveEndpoint),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host?.isEmpty == false
        else {
            throw LLMProviderError.invalidEndpoint(config.effectiveEndpoint)
        }
        guard !config.effectiveModel.isEmpty else { throw LLMProviderError.missingModel }
    }

    func runConnectivityCheck(_ config: LLMConfig) async -> LLMProviderError? {
        guard config.enabled else { return .disabled }
        guard config.provider == providerID || config.provider.wireFormat == providerID.wireFormat else { return .unsupportedProvider(config.provider) }
        
        let apiKey = EncryptedKeyStore.get(service: config.effectiveKeychainService) ?? ""
        if apiKey.isEmpty && !config.usesLocalEndpoint {
            return .missingAPIKey
        }
        
        guard let url = URL(string: config.effectiveEndpoint),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host?.isEmpty == false
        else {
            return .invalidEndpoint(config.effectiveEndpoint)
        }
        
        return await performConnectivityCheck(config: config, apiKey: apiKey)
    }
    
    func performConnectivityCheck(config: LLMConfig, apiKey: String) async -> LLMProviderError? {
        return nil
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
        case .server(let status, let body):
            {
                let detail = Self.extractErrorMessage(from: body) ?? ""
                return "LLM server error (\(status))\(detail.isEmpty ? "" : ": \(detail)")"
            }()
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

    private static func extractErrorMessage(from body: String?) -> String? {
        guard let body, let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String, !message.isEmpty
        else { return body }
        return message
    }
}
