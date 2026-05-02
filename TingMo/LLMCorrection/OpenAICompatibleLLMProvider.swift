import Foundation

/// Adapter for OpenAI chat/completions compatible APIs: OpenAI, Groq chat,
/// Ollama, LiteLLM, and proxy services that implement the same wire format.
struct OpenAICompatibleLLMProvider: LLMProvider {
    let providerID: LLMProviderID = .openAICompatible
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func correct(_ request: LLMCorrectionRequest) async throws -> LLMCorrectionResponse {
        try validate(request.config)

        let transcript = request.trimmedTranscript
        guard !transcript.isEmpty else { throw LLMProviderError.emptyTranscript }

        let apiKey = EncryptedKeyStore.get(service: request.config.effectiveKeychainService) ?? ""
        if apiKey.isEmpty && !request.config.usesLocalEndpoint {
            throw LLMProviderError.missingAPIKey
        }

        guard let url = URL(string: request.config.effectiveEndpoint) else {
            throw LLMProviderError.invalidEndpoint(request.config.effectiveEndpoint)
        }

        var urlRequest = URLRequest(url: url, timeoutInterval: 45)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body = ChatCompletionRequest(
            model: request.config.effectiveModel,
            messages: makeMessages(for: request),
            temperature: request.config.normalizedTemperature
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw Self.classifyURLError(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if let error = Self.classifyStatus(status, data: data, response: response) {
            throw error
        }

        let decoded: ChatCompletionResponse
        do {
            decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            throw LLMProviderError.invalidResponse
        }

        guard let correctedText = decoded.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !correctedText.isEmpty
        else {
            throw LLMProviderError.missingCorrectedText
        }

        return LLMCorrectionResponse(
            correctedText: correctedText,
            provider: providerID,
            model: decoded.model ?? request.config.effectiveModel,
            usage: decoded.usage?.asLLMUsage
        )
    }

    func performConnectivityCheck(config: LLMConfig, apiKey: String) async -> LLMProviderError? {
        guard let url = URL(string: config.effectiveEndpoint) else {
            return .invalidEndpoint(config.effectiveEndpoint)
        }

        let keyPreview = apiKey.isEmpty
            ? "<empty>"
            : "\(apiKey.prefix(4))...\(apiKey.suffix(4)) (len=\(apiKey.count))"
        NSLog("[TingMo][LLM][check] provider=\(config.provider.rawValue) url=\(url.absoluteString) model=\(config.effectiveModel) keychainService=\(config.effectiveKeychainService) apiKey=\(keyPreview)")

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body = ChatCompletionRequest(
            model: config.effectiveModel,
            messages: [ChatMessage(role: "user", content: "hi")],
            temperature: 0,
            maxTokens: 1,
            thinking: .init(type: "disabled")
        )
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            return .network(underlying: error)
        }

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let bodyPreview = String(data: data, encoding: .utf8)?.prefix(500) ?? ""
            NSLog("[TingMo][LLM][check] status=\(status) body=\(bodyPreview)")

            switch status {
            case 200..<300:
                return nil
            case 401, 403:
                return .unauthorized
            case 429:
                return .rateLimited(retryAfter: nil)
            default:
                return .server(status: status, body: String(data: data, encoding: .utf8))
            }
        } catch {
            NSLog("[TingMo][LLM][check] network error: \(error)")
            return .network(underlying: error)
        }
    }

    private func makeMessages(for request: LLMCorrectionRequest) -> [ChatMessage] {
        [
            ChatMessage(role: "system", content: request.config.effectiveSystemPrompt),
            ChatMessage(role: "user", content: LLMCorrectionPrompt.userMessage(for: request)),
        ]
    }

    private static func classifyStatus(_ status: Int, data: Data, response: URLResponse) -> LLMProviderError? {
        switch status {
        case 200..<300:
            return nil
        case 401, 403:
            return .unauthorized
        case 408:
            return .timeout
        case 429:
            return .rateLimited(retryAfter: retryAfter(from: response))
        case 500..<600:
            return .server(status: status, body: String(data: data, encoding: .utf8))
        case 0:
            return .invalidResponse
        default:
            return .server(status: status, body: String(data: data, encoding: .utf8))
        }
    }

    private static func retryAfter(from response: URLResponse) -> TimeInterval? {
        guard let value = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }
        return TimeInterval(value)
    }

    private static func classifyURLError(_ error: Error) -> LLMProviderError {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorTimedOut:
                return .timeout
            case NSURLErrorCancelled:
                return .cancelled
            default:
                return .network(underlying: error)
            }
        }
        return .network(underlying: error)
    }
}

private struct ChatCompletionRequest: Encodable {
    var model: String
    var messages: [ChatMessage]
    var temperature: Double
    var maxTokens: Int?
    var thinking: ThinkingConfig?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case thinking
    }

    struct ThinkingConfig: Encodable {
        var type: String
    }
}

private struct ChatMessage: Codable, Equatable {
    var role: String
    var content: String
}

private struct ChatCompletionResponse: Decodable {
    var model: String?
    var choices: [Choice]
    var usage: Usage?

    struct Choice: Decodable {
        var message: ChatMessage
    }

    struct Usage: Decodable {
        var promptTokens: Int?
        var completionTokens: Int?
        var totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }

        var asLLMUsage: LLMUsage {
            LLMUsage(
                inputTokens: promptTokens,
                outputTokens: completionTokens,
                totalTokens: totalTokens
            )
        }
    }
}
