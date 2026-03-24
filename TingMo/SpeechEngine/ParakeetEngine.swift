import Foundation

/// Parakeet (NVIDIA) CoreML engine — English-only, high accuracy.
/// Will be fully implemented when Argmax SDK provides native support.
final class ParakeetEngine: SpeechEngine, @unchecked Sendable {
    static let engineID = "parakeet"

    let info: EngineInfo

    init(isReady: Bool = false) {
        self.info = EngineInfo(
            id: Self.engineID,
            name: "Parakeet (English Only)",
            type: .local,
            supportedLanguages: ["en"],
            supportsStreaming: false,
            modelSize: "600 MB",
            isReady: isReady
        )
    }

    func transcribe(audioURL: URL, language: String) async throws -> AsyncStream<TranscriptionResult> {
        guard info.isReady else { throw SpeechEngineError.modelNotDownloaded }
        guard supportsLanguage(language) else { throw SpeechEngineError.unsupportedLanguage(language) }

        // TODO: Integrate Parakeet CoreML model when Argmax SDK is available.
        return AsyncStream { continuation in
            continuation.yield(.final("[Parakeet: transcription placeholder]"))
            continuation.finish()
        }
    }
}
