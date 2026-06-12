import Foundation

/// Fetches the model catalog from a provider's models endpoint so the
/// settings UI can offer real model IDs instead of free-form typing.
/// OpenAI-compatible and Anthropic APIs both expose `GET /v1/models`
/// returning `{"data": [{"id": ...}]}`; only the auth headers differ.
enum LLMModelListFetcher {
    enum FetchError: LocalizedError {
        case invalidURL
        case unauthorized
        case server(status: Int)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                String(localized: "The base URL is not a valid URL.")
            case .unauthorized:
                String(localized: "The server rejected the API key.")
            case .server(let status):
                String(localized: "The server returned an error (HTTP \(status)).")
            case .invalidResponse:
                String(localized: "Could not read the model list from the server's response.")
            }
        }
    }

    static func fetchModels(
        provider: LLMProviderID,
        baseURL: String,
        apiKey: String,
        session: URLSession = .shared
    ) async throws -> [String] {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/v1/models") else {
            throw FetchError.invalidURL
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        switch provider.wireFormat {
        case .openai:
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            return try parse(data)
        case 401, 403:
            throw FetchError.unauthorized
        default:
            throw FetchError.server(status: status)
        }
    }

    /// Decode `{"data": [{"id": "..."}]}`, keeping the server's ordering.
    static func parse(_ data: Data) throws -> [String] {
        struct ModelList: Decodable {
            struct Item: Decodable { let id: String }
            let data: [Item]
        }
        guard let list = try? JSONDecoder().decode(ModelList.self, from: data) else {
            throw FetchError.invalidResponse
        }
        return list.data.map(\.id)
    }
}
