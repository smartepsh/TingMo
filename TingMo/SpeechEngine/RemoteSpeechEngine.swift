import Foundation

/// Configuration for a remote speech recognition API.
struct RemoteEngineConfig: Codable, Sendable {
    var id: String
    var name: String
    var endpoint: String
    var apiKey: String
    var supportedLanguages: [String]

    static let groq = RemoteEngineConfig(
        id: "groq-whisper",
        name: "Groq (Whisper)",
        endpoint: "https://api.groq.com/openai/v1/audio/transcriptions",
        apiKey: "",
        supportedLanguages: ["en", "zh", "ja", "ko", "de", "fr", "es", "pt", "ru", "it"]
    )

    static let elevenlabs = RemoteEngineConfig(
        id: "elevenlabs",
        name: "ElevenLabs",
        endpoint: "https://api.elevenlabs.io/v1/speech-to-text",
        apiKey: "",
        supportedLanguages: ["en", "zh", "ja", "ko", "de", "fr", "es"]
    )
}

/// Remote speech recognition engine — records audio, sends to API, returns result.
final class RemoteSpeechEngine: SpeechEngine, @unchecked Sendable {
    let config: RemoteEngineConfig
    let info: EngineInfo

    /// URL of the last audio file that failed transcription (for retry).
    private(set) var retainedAudioURL: URL?
    private(set) var lastError: Error?

    init(config: RemoteEngineConfig) {
        self.config = config
        self.info = EngineInfo(
            id: config.id,
            name: config.name,
            type: .remote,
            supportedLanguages: config.supportedLanguages,
            supportsStreaming: false,
            modelSize: nil,
            isReady: !config.apiKey.isEmpty
        )
    }

    func transcribe(audioURL: URL, language: String) async throws -> AsyncStream<TranscriptionResult> {
        guard !config.apiKey.isEmpty else { throw SpeechEngineError.permissionDenied }
        guard supportsLanguage(language) else { throw SpeechEngineError.unsupportedLanguage(language) }

        retainedAudioURL = audioURL
        lastError = nil

        do {
            let text = try await sendToAPI(audioURL: audioURL, language: language)
            retainedAudioURL = nil
            return AsyncStream { continuation in
                continuation.yield(.final(text))
                continuation.finish()
            }
        } catch {
            lastError = error
            // Retain the audio URL for retry
            throw SpeechEngineError.networkError(underlying: error)
        }
    }

    /// Retry transcription with the retained audio file.
    func retryLastFailed() async throws -> AsyncStream<TranscriptionResult> {
        guard let audioURL = retainedAudioURL else {
            throw SpeechEngineError.modelNotFound
        }
        return try await transcribe(audioURL: audioURL, language: "en")
    }

    // MARK: - API Communication

    private func sendToAPI(audioURL: URL, language: String) async throws -> String {
        let audioData = try Data(contentsOf: audioURL)
        let boundary = UUID().uuidString

        var request = URLRequest(url: URL(string: config.endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // File field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Model field (for Groq/OpenAI compatible endpoints)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-large-v3\r\n".data(using: .utf8)!)

        // Language field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(language)\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SpeechEngineError.networkError(
                underlying: NSError(domain: "RemoteSpeechEngine", code: (response as? HTTPURLResponse)?.statusCode ?? -1)
            )
        }

        // Parse JSON response — expects {"text": "..."}
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String
        {
            return text
        }

        // Fallback: treat entire response as plain text
        return String(data: data, encoding: .utf8) ?? ""
    }
}
