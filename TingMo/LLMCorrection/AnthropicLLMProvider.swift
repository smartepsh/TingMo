import Foundation

/// Adapter for Anthropic's Messages API.
struct AnthropicLLMProvider: LLMProvider {
    let providerID: LLMProviderID = .anthropic
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func correct(_ request: LLMCorrectionRequest) async throws -> LLMCorrectionResponse {
        try validate(request.config)

        let transcript = request.trimmedTranscript
        guard !transcript.isEmpty else { throw LLMProviderError.emptyTranscript }

        guard let apiKey = KeychainStore.get(service: request.config.effectiveKeychainService),
              !apiKey.isEmpty
        else {
            throw LLMProviderError.missingAPIKey
        }

        guard let url = URL(string: request.config.effectiveEndpoint) else {
            throw LLMProviderError.invalidEndpoint(request.config.effectiveEndpoint)
        }

        var urlRequest = URLRequest(url: url, timeoutInterval: 45)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body = MessagesRequest(
            model: request.config.effectiveModel,
            system: request.config.effectiveSystemPrompt,
            messages: makeMessages(for: request),
            maxTokens: 1024,
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

        let decoded: MessagesResponse
        do {
            decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        } catch {
            throw LLMProviderError.invalidResponse
        }

        let correctedText = decoded.content
            .filter { $0.type == "text" }
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !correctedText.isEmpty else { throw LLMProviderError.missingCorrectedText }

        return LLMCorrectionResponse(
            correctedText: correctedText,
            provider: providerID,
            model: decoded.model ?? request.config.effectiveModel,
            usage: decoded.usage?.asLLMUsage
        )
    }

    private func makeMessages(for request: LLMCorrectionRequest) -> [Message] {
        let content = LLMCorrectionPrompt.userMessage(for: request)
        return [Message(role: "user", content: [ContentBlock(type: "text", text: content)])]
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

private struct MessagesRequest: Encodable {
    var model: String
    var system: String
    var messages: [Message]
    var maxTokens: Int
    var temperature: Double

    enum CodingKeys: String, CodingKey {
        case model
        case system
        case messages
        case maxTokens = "max_tokens"
        case temperature
    }
}

private struct Message: Codable, Equatable {
    var role: String
    var content: [ContentBlock]
}

private struct ContentBlock: Codable, Equatable {
    var type: String
    var text: String
}

private struct MessagesResponse: Decodable {
    var model: String?
    var content: [ContentBlock]
    var usage: Usage?

    struct Usage: Decodable {
        var inputTokens: Int?
        var outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }

        var asLLMUsage: LLMUsage {
            LLMUsage(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                totalTokens: inputTokens.flatMap { input in
                    outputTokens.map { input + $0 }
                }
            )
        }
    }
}
