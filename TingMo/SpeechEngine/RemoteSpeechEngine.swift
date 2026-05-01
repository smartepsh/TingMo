import Foundation

/// How a provider authenticates requests. Groq-style uses the OpenAI
/// `Authorization: Bearer`; ElevenLabs wants an `xi-api-key` header.
enum RemoteAuthStyle: Sendable {
    case bearer
    case xiAPIKey
}

/// Static description of a remote STT provider.
/// Runtime secrets (API key) are fetched from `EncryptedKeyStore` via `keychainService`.
struct RemoteEngineConfig: Sendable {
    var id: String
    var name: String
    var endpoint: String
    /// Multipart field name that carries the model selector (e.g. "model" for
    /// OpenAI-compatible, "model_id" for ElevenLabs). Value is `modelValue`.
    var modelFieldName: String
    var modelValue: String?
    /// Multipart field name for the language hint.
    var languageFieldName: String
    var keychainService: String
    var authStyle: RemoteAuthStyle
    var supportedLanguages: [String]
    /// How the connectivity-check endpoint is exercised.
    /// * `.get(url)` — simple GET with the auth header; any 2xx = success.
    ///   Works for providers that expose a scoped-agnostic read endpoint.
    /// * `.postSTT` — send a tiny silent WAV to the real `endpoint`. This is
    ///   the only path that works for providers (ElevenLabs) where every
    ///   read endpoint requires a scope that STT-only keys don't have.
    var healthcheckMode: HealthcheckMode?

    enum HealthcheckMode: Sendable {
        case get(url: String)
        case postSTT
    }
    /// Optional footer shown under the settings section (billing blurb, etc.).
    var billingNote: String?

    static let groq = RemoteEngineConfig(
        id: "groq-whisper",
        name: "Groq (Whisper)",
        endpoint: "https://api.groq.com/openai/v1/audio/transcriptions",
        modelFieldName: "model",
        modelValue: "whisper-large-v3",
        languageFieldName: "language",
        keychainService: "tingmo.groq",
        authStyle: .bearer,
        supportedLanguages: ["en", "zh", "ja", "ko", "de", "fr", "es", "pt", "ru", "it"],
        healthcheckMode: .get(url: "https://api.groq.com/openai/v1/models"),
        billingNote: nil
    )

    static let elevenlabs = RemoteEngineConfig(
        id: "elevenlabs",
        name: "ElevenLabs (Scribe)",
        endpoint: "https://api.elevenlabs.io/v1/speech-to-text",
        modelFieldName: "model_id",
        modelValue: "scribe_v1",
        languageFieldName: "language_code",
        keychainService: "tingmo.elevenlabs",
        authStyle: .xiAPIKey,
        supportedLanguages: [
            "en", "zh", "ja", "ko", "de", "fr", "es", "pt", "it", "nl",
            "pl", "ru", "tr", "ar", "hi",
        ],
        // ElevenLabs gates every GET endpoint behind a scope (user_read,
        // models_read, voices_read) that STT-only keys don't have. The
        // only way to verify a STT key is legitimate is to exercise the
        // STT endpoint itself with a tiny silent WAV — that's what
        // `.postSTT` does.
        healthcheckMode: .postSTT,
        billingNote: String(localized: "ElevenLabs bills per audio minute. Check your dashboard for usage and rate limits.")
    )
}

/// Classified failure surfaced by remote engines. The pipeline maps these
/// into user-facing strings via `localizedDescription`.
enum RemoteEngineError: LocalizedError {
    case missingAPIKey
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int, body: String?)
    case network(underlying: Error)
    case timeout
    case cancelled
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return String(localized: "API key is missing. Enter it in Settings.")
        case .unauthorized:
            return String(localized: "Authentication failed — the API key is invalid.")
        case .rateLimited(let retry):
            if let retry {
                return String(localized: "Rate limit exceeded. Retry after \(Int(retry))s.")
            }
            return String(localized: "Rate limit exceeded.")
        case .server(let status, _):
            return String(localized: "Server returned an error (\(status)).")
        case .network(let err):
            return String(localized: "Network error: \(err.localizedDescription)")
        case .timeout:
            return String(localized: "Request timed out.")
        case .cancelled:
            return String(localized: "Request cancelled.")
        case .invalidResponse:
            return String(localized: "Unexpected response from the server.")
        }
    }
}

/// Remote speech recognition engine — records audio, sends to API, returns result.
///
/// Streaming is not implemented: remote providers currently only expose
/// one-shot "upload the file, get the text" endpoints, so `transcribe` sends
/// the audio and yields a single `.final` result once the response arrives.
final class RemoteSpeechEngine: SpeechEngine, @unchecked Sendable {
    let config: RemoteEngineConfig
    var info: EngineInfo

    /// URL of the last audio file that failed transcription (for retry).
    private(set) var retainedAudioURL: URL?
    private(set) var lastError: Error?

    /// Wall-clock timeout for a single transcription request. Remote STT
    /// occasionally stalls on giant uploads; 60s is generous for a 30s clip.
    private let requestTimeout: TimeInterval = 60

    init(config: RemoteEngineConfig) {
        self.config = config
        let keyPresent = (EncryptedKeyStore.get(service: config.keychainService) ?? "").isEmpty == false
        self.info = EngineInfo(
            id: config.id,
            name: config.name,
            type: .remote,
            supportedLanguages: config.supportedLanguages,
            supportsStreaming: false,
            modelSize: nil,
            isReady: keyPresent
        )
    }

    /// Refresh `info.isReady` based on the current keychain state. Call this
    /// after the user adds/removes an API key so UI picks up the change.
    func refreshReadiness() {
        let keyPresent = (EncryptedKeyStore.get(service: config.keychainService) ?? "").isEmpty == false
        info.isReady = keyPresent
    }

    func transcribe(audioURL: URL, language: String) async throws -> AsyncStream<TranscriptionResult> {
        guard let apiKey = EncryptedKeyStore.get(service: config.keychainService), !apiKey.isEmpty else {
            throw RemoteEngineError.missingAPIKey
        }
        if !language.isEmpty, !supportsLanguage(language) {
            throw SpeechEngineError.unsupportedLanguage(language)
        }

        retainedAudioURL = audioURL
        lastError = nil

        do {
            let text = try await sendTranscription(audioURL: audioURL, language: language, apiKey: apiKey)
            retainedAudioURL = nil
            return AsyncStream { continuation in
                continuation.yield(.final(text))
                continuation.finish()
            }
        } catch {
            lastError = error
            throw error
        }
    }

    /// Issue a cheap auth check against the provider. Returns `nil` on
    /// success, or a `RemoteEngineError` describing the failure.
    func runConnectivityCheck() async -> RemoteEngineError? {
        guard let apiKey = EncryptedKeyStore.get(service: config.keychainService), !apiKey.isEmpty else {
            return .missingAPIKey
        }
        guard let mode = config.healthcheckMode else {
            return nil
        }

        switch mode {
        case .get(let urlString):
            return await runGETHealthcheck(urlString: urlString, apiKey: apiKey)
        case .postSTT:
            return await runSTTHealthcheck(apiKey: apiKey)
        }
    }

    private func runGETHealthcheck(urlString: String, apiKey: String) async -> RemoteEngineError? {
        guard let url = URL(string: urlString) else { return .invalidResponse }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        applyAuth(to: &request, apiKey: apiKey)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return Self.classifyStatus(status, body: nil)
        } catch {
            return Self.classifyURLError(error)
        }
    }

    /// Hit the real STT endpoint with a tiny silent WAV. The audio is
    /// ~0.2s of silence, so the provider charges fractions of a cent at
    /// worst and returns an empty transcription on success. Any 4xx other
    /// than the quota-style 402/429 implies a bad key.
    private func runSTTHealthcheck(apiKey: String) async -> RemoteEngineError? {
        let wav = Self.silentWAV()
        let boundary = UUID().uuidString
        guard let url = URL(string: config.endpoint) else { return .invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        applyAuth(to: &request, apiKey: apiKey)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        appendField(&body, boundary: boundary, name: "file", filename: "probe.wav", contentType: "audio/wav", data: wav)
        if let model = config.modelValue {
            appendTextField(&body, boundary: boundary, name: config.modelFieldName, value: model)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let result = Self.classifyStatus(status, body: data)
            NSLog("[TingMo][Remote:\(config.id)] health check done status=\(status) result=\(result.map { "\($0)" } ?? "OK")")
            return result
        } catch {
            let classified = Self.classifyURLError(error)
            NSLog("[TingMo][Remote:\(config.id)] health check FAILED error=\(error) classified=\(classified)")
            return classified
        }
    }

    private func applyAuth(to request: inout URLRequest, apiKey: String) {
        switch config.authStyle {
        case .bearer:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .xiAPIKey:
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        }
    }

    /// 16 kHz mono PCM WAV containing ~0.2 seconds of silence. Used by the
    /// STT-based health check so we don't have to ship an audio asset.
    private static func silentWAV() -> Data {
        let sampleRate: UInt32 = 16000
        let sampleCount: UInt32 = 3200 // 0.2s
        let byteRate = sampleRate * 2
        let subchunk2Size = sampleCount * 2
        let chunkSize = 36 + subchunk2Size

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(Self.littleEndian(chunkSize))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(Self.littleEndian(UInt32(16)))           // PCM subchunk size
        data.append(Self.littleEndian(UInt16(1)))            // PCM format
        data.append(Self.littleEndian(UInt16(1)))            // mono
        data.append(Self.littleEndian(sampleRate))
        data.append(Self.littleEndian(byteRate))
        data.append(Self.littleEndian(UInt16(2)))            // block align
        data.append(Self.littleEndian(UInt16(16)))           // bits/sample
        data.append("data".data(using: .ascii)!)
        data.append(Self.littleEndian(subchunk2Size))
        data.append(Data(count: Int(subchunk2Size)))         // zeros
        return data
    }

    private static func littleEndian(_ value: UInt32) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 4)
    }

    private static func littleEndian(_ value: UInt16) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 2)
    }

    // MARK: - API Communication

    private func sendTranscription(audioURL: URL, language: String, apiKey: String) async throws -> String {
        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            throw RemoteEngineError.network(underlying: error)
        }

        let boundary = UUID().uuidString
        guard let url = URL(string: config.endpoint) else {
            throw RemoteEngineError.invalidResponse
        }

        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        switch config.authStyle {
        case .bearer:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .xiAPIKey:
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        }
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        appendField(&body, boundary: boundary, name: "file", filename: "audio.wav", contentType: "audio/wav", data: audioData)
        if let model = config.modelValue {
            appendTextField(&body, boundary: boundary, name: config.modelFieldName, value: model)
        }
        if !language.isEmpty {
            appendTextField(&body, boundary: boundary, name: config.languageFieldName, value: language)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Self.classifyURLError(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        NSLog("[TingMo][Remote:\(config.id)] transcribe HTTP status=\(status) bytes=\(data.count)")
        if let classification = Self.classifyStatus(status, body: data) {
            throw classification
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let text = json["text"] as? String { return text }
            if let nested = (json["results"] as? [[String: Any]])?.first?["transcript"] as? String {
                return nested
            }
        }
        if let fallback = String(data: data, encoding: .utf8) {
            NSLog("[TingMo][Remote:\(config.id)] transcribe JSON parse failed, using raw body")
            return fallback
        }
        throw RemoteEngineError.invalidResponse
    }

    // MARK: - Error classification

    private static func classifyStatus(_ status: Int, body: Data?) -> RemoteEngineError? {
        switch status {
        case 200..<300:
            return nil
        case 401, 403:
            return .unauthorized
        case 429:
            return .rateLimited(retryAfter: nil)
        case 500..<600:
            return .server(status: status, body: body.flatMap { String(data: $0, encoding: .utf8) })
        case 0:
            return .invalidResponse
        default:
            return .server(status: status, body: body.flatMap { String(data: $0, encoding: .utf8) })
        }
    }

    private static func classifyURLError(_ error: Error) -> RemoteEngineError {
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

    // MARK: - Multipart helpers

    private func appendField(
        _ body: inout Data,
        boundary: String,
        name: String,
        filename: String,
        contentType: String,
        data: Data
    ) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
    }

    private func appendTextField(
        _ body: inout Data,
        boundary: String,
        name: String,
        value: String
    ) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }
}

extension RemoteSpeechEngine {
    /// Create a RemoteSpeechEngine from an STTInstance.
    /// Builds the appropriate RemoteEngineConfig based on the instance's provider.
    convenience init(instance: STTInstance) {
        let config = Self.config(for: instance.provider, keychainService: instance.keychainService)
        self.init(config: config)
    }

    private static func config(for provider: STTProviderID, keychainService: String) -> RemoteEngineConfig {
        switch provider {
        case .groq:
            RemoteEngineConfig(
                id: "stt-instance-groq",
                name: provider.defaultInstanceName,
                endpoint: "https://api.groq.com/openai/v1/audio/transcriptions",
                modelFieldName: "model",
                modelValue: "whisper-large-v3",
                languageFieldName: "language",
                keychainService: keychainService,
                authStyle: .bearer,
                supportedLanguages: provider.supportedLanguages,
                healthcheckMode: .get(url: "https://api.groq.com/openai/v1/models"),
                billingNote: nil
            )
        case .elevenlabs:
            RemoteEngineConfig(
                id: "stt-instance-elevenlabs",
                name: provider.defaultInstanceName,
                endpoint: "https://api.elevenlabs.io/v1/speech-to-text",
                modelFieldName: "model_id",
                modelValue: "scribe_v1",
                languageFieldName: "language_code",
                keychainService: keychainService,
                authStyle: .xiAPIKey,
                supportedLanguages: provider.supportedLanguages,
                healthcheckMode: .postSTT,
                billingNote: String(localized: "ElevenLabs bills per audio minute. Check your dashboard for usage and rate limits.")
            )
        }
    }
}
