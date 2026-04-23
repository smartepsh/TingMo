import Foundation

/// Result emitted by a speech engine during or after transcription.
enum TranscriptionResult: Sendable {
    /// Partial (interim) result during streaming.
    case partial(String)
    /// Final transcription result.
    case final(String)
}

/// Describes a speech engine's capabilities and metadata.
struct EngineInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let type: EngineType
    let supportedLanguages: [String]
    let supportsStreaming: Bool
    /// Model size description (e.g. "75 MB"), nil for system/remote engines.
    var modelSize: String?
    /// Whether the engine's model is downloaded and ready to use.
    var isReady: Bool

    enum EngineType: String, Sendable {
        case local
        case remote
    }
}

/// Unified protocol for all speech recognition engines.
protocol SpeechEngine: Sendable {
    /// Engine metadata and capabilities.
    var info: EngineInfo { get }

    /// Start transcription from the given audio data or an ongoing audio stream.
    /// Emits results via the returned AsyncStream.
    func transcribe(audioURL: URL, language: String) async throws -> AsyncStream<TranscriptionResult>

    /// Start real-time streaming transcription from the microphone.
    /// Only available when `info.supportsStreaming` is true.
    /// Returns a stream of transcription results and a stop handler.
    func startStreaming(language: String) async throws -> (stream: AsyncStream<TranscriptionResult>, stop: @Sendable () -> Void)

    /// Check if a specific language is supported by this engine.
    func supportsLanguage(_ language: String) -> Bool
}

extension SpeechEngine {
    func supportsLanguage(_ language: String) -> Bool {
        info.supportedLanguages.contains(language)
    }

    func startStreaming(language: String) async throws -> (stream: AsyncStream<TranscriptionResult>, stop: @Sendable () -> Void) {
        throw SpeechEngineError.streamingNotSupported
    }
}

enum SpeechEngineError: Error, LocalizedError {
    case streamingNotSupported
    case modelNotDownloaded
    case modelNotFound
    case transcriptionFailed(underlying: Error)
    case networkError(underlying: Error)
    case permissionDenied
    case unsupportedLanguage(String)

    var errorDescription: String? {
        switch self {
        case .streamingNotSupported:
            "This engine does not support streaming."
        case .modelNotDownloaded:
            "The speech model has not been downloaded yet."
        case .modelNotFound:
            "The speech model could not be found."
        case .transcriptionFailed(let error):
            "Transcription failed: \(error.localizedDescription)"
        case .networkError(let error):
            "Network error: \(error.localizedDescription)"
        case .permissionDenied:
            "Microphone or speech recognition permission denied."
        case .unsupportedLanguage(let lang):
            "Language '\(lang)' is not supported by this engine."
        }
    }
}
