import Foundation

/// WhisperKit-based local speech recognition engine.
/// Note: WhisperKit SPM dependency will be added when the package is integrated.
/// This implementation provides the structural shell and model management.
final class WhisperKitEngine: SpeechEngine, @unchecked Sendable {
    static let engineID = "whisperkit"

    let model: WhisperModel
    var info: EngineInfo

    static let availableModels: [WhisperModel] = [
        WhisperModel(id: "tiny", name: "Whisper Tiny", size: "75 MB"),
        WhisperModel(id: "base", name: "Whisper Base", size: "150 MB"),
        WhisperModel(id: "small", name: "Whisper Small", size: "500 MB"),
        WhisperModel(id: "medium", name: "Whisper Medium", size: "1.5 GB"),
        WhisperModel(id: "large-v2", name: "Whisper Large v2", size: "3.1 GB"),
        WhisperModel(id: "large-v3", name: "Whisper Large v3", size: "3.1 GB"),
    ]

    /// Default engine ID used when the user has no saved preference (M1 ships with tiny).
    static let defaultModelEngineID = "\(engineID)-tiny"

    struct WhisperModel: Identifiable, Sendable {
        let id: String
        let name: String
        let size: String
    }

    init(model: WhisperModel, isReady: Bool = false) {
        self.model = model
        self.info = EngineInfo(
            id: "\(Self.engineID)-\(model.id)",
            name: model.name,
            type: .local,
            supportedLanguages: Self.supportedLanguages,
            supportsStreaming: true,
            modelSize: model.size,
            isReady: isReady
        )
    }

    // MARK: - Model Management

    static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TingMo/Models", isDirectory: true)
    }

    static func modelDirectory(for modelID: String) -> URL {
        modelsDirectory.appendingPathComponent("whisperkit-\(modelID)", isDirectory: true)
    }

    static func isModelDownloaded(_ model: WhisperModel) -> Bool {
        let dir = modelDirectory(for: model.id)
        return FileManager.default.fileExists(atPath: dir.path)
    }

    /// Required files in a valid WhisperKit model folder.
    static let requiredModelFiles = [
        "MelSpectrogram.mlmodelc",
        "AudioEncoder.mlmodelc",
        "TextDecoder.mlmodelc",
    ]

    /// Validate that a folder contains valid WhisperKit model files.
    static func validateModelFolder(_ url: URL) -> Result<Void, SpeechEngineError> {
        let missing = requiredModelFiles.filter { fileName in
            !FileManager.default.fileExists(atPath: url.appendingPathComponent(fileName).path)
        }
        if missing.isEmpty {
            return .success(())
        } else {
            return .failure(.invalidModelFiles(missing: missing))
        }
    }

    /// Import a local model folder by copying it to the models directory.
    static func importModel(from sourceURL: URL, as modelID: String) throws {
        switch validateModelFolder(sourceURL) {
        case .success:
            let destination = modelDirectory(for: modelID)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        case .failure(let error):
            throw error
        }
    }

    /// Download base URL — user can override for mirror sources.
    static var customDownloadBase: String? {
        get { UserDefaults.standard.string(forKey: "WhisperKit.customDownloadBase") }
        set { UserDefaults.standard.set(newValue, forKey: "WhisperKit.customDownloadBase") }
    }

    // MARK: - SpeechEngine Protocol

    func transcribe(audioURL: URL, language: String) async throws -> AsyncStream<TranscriptionResult> {
        guard info.isReady else { throw SpeechEngineError.modelNotDownloaded }
        guard supportsLanguage(language) else { throw SpeechEngineError.unsupportedLanguage(language) }

        // TODO: Integrate WhisperKit transcription when SPM dependency is added.
        // This returns a placeholder that will be replaced with real WhisperKit calls.
        return AsyncStream { continuation in
            continuation.yield(.final("[WhisperKit \(model.name): transcription placeholder]"))
            continuation.finish()
        }
    }

    func startStreaming(language: String) async throws -> (stream: AsyncStream<TranscriptionResult>, stop: @Sendable () -> Void) {
        guard info.isReady else { throw SpeechEngineError.modelNotDownloaded }
        guard supportsLanguage(language) else { throw SpeechEngineError.unsupportedLanguage(language) }

        // TODO: Integrate WhisperKit streaming when SPM dependency is added.
        let stopped = UncheckedSendable(value: false)
        let stream = AsyncStream<TranscriptionResult> { continuation in
            continuation.onTermination = { @Sendable _ in }
            Task {
                while !stopped.value {
                    try await Task.sleep(for: .milliseconds(500))
                    if stopped.value { break }
                    continuation.yield(.partial("[streaming...]"))
                }
                continuation.finish()
            }
        }
        let stop: @Sendable () -> Void = {
            stopped.setValue(true)
        }
        return (stream, stop)
    }

    // MARK: - Languages

    private static let supportedLanguages = [
        "en", "zh", "ja", "ko", "de", "fr", "es", "pt", "ru", "it",
        "nl", "pl", "sv", "da", "fi", "no", "tr", "ar", "he", "hi",
        "th", "vi", "id", "ms", "uk", "cs", "ro", "hu", "el", "bg",
    ]
}

/// Helper for passing mutable state across sendable boundaries.
private final class UncheckedSendable<T>: @unchecked Sendable {
    var value: T
    init(value: T) { self.value = value }
    func setValue(_ newValue: T) { value = newValue }
}
