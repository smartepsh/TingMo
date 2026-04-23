import Foundation
import WhisperKit

/// WhisperKit-based local speech recognition engine.
///
/// The engine wraps one model variant. Construct an instance per variant
/// (tiny, base, small, …); the shared registry hands out the right one.
///
/// Lifecycle: instances start with `isReady == false`. Call
/// `downloadModel(progress:)` then `loadModel()` (or let `loadModel()`
/// download on demand when the folder already exists but hasn't been
/// loaded yet) before `transcribe` / `startStreaming`. Without that,
/// those methods throw `.modelNotDownloaded`. UI layers (onboarding,
/// settings) decide when to trigger the download.
final class WhisperKitEngine: SpeechEngine, @unchecked Sendable {
    static let engineID = "whisperkit"

    let model: WhisperModel
    var info: EngineInfo

    private var whisperKit: WhisperKit?
    private let loadLock = NSLock()

    static let availableModels: [WhisperModel] = [
        WhisperModel(id: "tiny", variant: "openai_whisper-tiny", name: "Whisper Tiny", size: "75 MB"),
        WhisperModel(id: "base", variant: "openai_whisper-base", name: "Whisper Base", size: "150 MB"),
        WhisperModel(id: "small", variant: "openai_whisper-small", name: "Whisper Small", size: "500 MB"),
        WhisperModel(id: "medium", variant: "openai_whisper-medium", name: "Whisper Medium", size: "1.5 GB"),
        WhisperModel(id: "large-v3", variant: "openai_whisper-large-v3", name: "Whisper Large v3", size: "3.1 GB"),
    ]

    /// Default engine ID used when the user has no saved preference (M1 ships with tiny).
    static let defaultModelEngineID = "\(engineID)-tiny"

    struct WhisperModel: Identifiable, Sendable {
        /// Short stable ID we use internally (e.g. "tiny").
        let id: String
        /// The argmaxinc/whisperkit-coreml repo variant name.
        let variant: String
        let name: String
        let size: String
    }

    init(model: WhisperModel) {
        self.model = model
        self.info = EngineInfo(
            id: "\(Self.engineID)-\(model.id)",
            name: model.name,
            type: .local,
            supportedLanguages: Self.supportedLanguages,
            supportsStreaming: true,
            modelSize: model.size,
            isReady: Self.isModelDownloaded(model)
        )
    }

    // MARK: - Model storage

    /// Root directory for all WhisperKit model folders we manage.
    /// We override WhisperKit's default location so downloads live under
    /// Application Support where we can clean them up consistently.
    static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TingMo/Models", isDirectory: true)
    }

    /// Directory where WhisperKit actually places a downloaded variant.
    /// `WhisperKit.download(downloadBase:)` appends `models/<repo>/<variant>`.
    static func modelFolder(for model: WhisperModel) -> URL {
        modelsDirectory
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc/whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(model.variant, isDirectory: true)
    }

    /// A model is considered downloaded if the .mlmodelc bundles are present.
    static func isModelDownloaded(_ model: WhisperModel) -> Bool {
        let folder = modelFolder(for: model)
        let required = ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"]
        return required.allSatisfy {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
    }

    // MARK: - Download & load

    /// Download the model variant into our managed folder.
    /// No-op if already present on disk.
    func downloadModel(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        if Self.isModelDownloaded(model) {
            info.isReady = true
            return
        }

        try FileManager.default.createDirectory(
            at: Self.modelsDirectory,
            withIntermediateDirectories: true
        )

        do {
            _ = try await WhisperKit.download(
                variant: model.variant,
                downloadBase: Self.modelsDirectory,
                from: "argmaxinc/whisperkit-coreml"
            ) { p in
                progress?(p.fractionCompleted)
            }
            info.isReady = true
        } catch {
            throw SpeechEngineError.networkError(underlying: error)
        }
    }

    /// Load the model into memory. Must be called before transcribe/startStreaming.
    /// Downloads first if needed.
    func loadModel() async throws {
        loadLock.lock()
        let alreadyLoaded = whisperKit != nil
        loadLock.unlock()
        if alreadyLoaded { return }

        if !Self.isModelDownloaded(model) {
            try await downloadModel()
        }

        do {
            let config = WhisperKitConfig(
                model: model.variant,
                modelRepo: "argmaxinc/whisperkit-coreml",
                modelFolder: Self.modelFolder(for: model).path,
                verbose: false,
                logLevel: .error,
                prewarm: false,
                load: true,
                download: false
            )
            let kit = try await WhisperKit(config)
            loadLock.lock()
            whisperKit = kit
            loadLock.unlock()
            info.isReady = true
        } catch {
            throw SpeechEngineError.transcriptionFailed(underlying: error)
        }
    }

    // MARK: - SpeechEngine Protocol

    func transcribe(audioURL: URL, language: String) async throws -> AsyncStream<TranscriptionResult> {
        guard info.isReady else { throw SpeechEngineError.modelNotDownloaded }
        // Empty language means auto-detect; otherwise the engine must support it.
        if !language.isEmpty, !supportsLanguage(language) {
            throw SpeechEngineError.unsupportedLanguage(language)
        }

        loadLock.lock()
        let kit = whisperKit
        loadLock.unlock()
        guard let kit else { throw SpeechEngineError.modelNotDownloaded }

        let options = DecodingOptions(
            task: .transcribe,
            language: language.isEmpty ? nil : language,
            temperature: 0.0,
            wordTimestamps: false,
            suppressBlank: true,
            chunkingStrategy: .vad
        )

        let results: [TranscriptionResult]
        do {
            let transcriptionResults = try await kit.transcribe(
                audioPath: audioURL.path,
                decodeOptions: options
            )
            let text = transcriptionResults.map(\.text).joined(separator: " ")
            results = [.final(text)]
        } catch {
            throw SpeechEngineError.transcriptionFailed(underlying: error)
        }

        return AsyncStream { continuation in
            for r in results { continuation.yield(r) }
            continuation.finish()
        }
    }

    func startStreaming(language: String) async throws -> (stream: AsyncStream<TranscriptionResult>, stop: @Sendable () -> Void) {
        guard info.isReady else { throw SpeechEngineError.modelNotDownloaded }
        if !language.isEmpty, !supportsLanguage(language) {
            throw SpeechEngineError.unsupportedLanguage(language)
        }

        loadLock.lock()
        let kit = whisperKit
        loadLock.unlock()
        guard let kit, let tokenizer = kit.tokenizer else {
            throw SpeechEngineError.modelNotDownloaded
        }

        let continuationBox = StreamContinuationBox()
        let stream = AsyncStream<TranscriptionResult> { continuation in
            continuationBox.set(continuation)
        }

        let options = DecodingOptions(
            task: .transcribe,
            language: language.isEmpty ? nil : language,
            temperature: 0.0,
            wordTimestamps: false,
            suppressBlank: true
        )

        let transcriber = AudioStreamTranscriber(
            audioEncoder: kit.audioEncoder,
            featureExtractor: kit.featureExtractor,
            segmentSeeker: kit.segmentSeeker,
            textDecoder: kit.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: kit.audioProcessor,
            decodingOptions: options
        ) { _, newState in
            let confirmed = newState.confirmedSegments.map(\.text).joined(separator: " ")
            let unconfirmed = newState.unconfirmedSegments.map(\.text).joined(separator: " ")
            let partial = [confirmed, unconfirmed].filter { !$0.isEmpty }.joined(separator: " ")
            if !partial.isEmpty {
                continuationBox.yield(.partial(partial))
            }
        }

        let transcriberBox = TranscriberBox(transcriber)

        Task {
            do {
                try await transcriber.startStreamTranscription()
            } catch {
                continuationBox.finish()
            }
        }

        let stop: @Sendable () -> Void = {
            Task {
                await transcriberBox.stop()
                continuationBox.finish()
            }
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

// MARK: - Sendable wrappers

private final class StreamContinuationBox: @unchecked Sendable {
    private var continuation: AsyncStream<TranscriptionResult>.Continuation?
    private let lock = NSLock()

    func set(_ c: AsyncStream<TranscriptionResult>.Continuation) {
        lock.lock(); defer { lock.unlock() }
        continuation = c
    }

    func yield(_ r: TranscriptionResult) {
        lock.lock(); defer { lock.unlock() }
        continuation?.yield(r)
    }

    func finish() {
        lock.lock(); defer { lock.unlock() }
        continuation?.finish()
        continuation = nil
    }
}

private actor TranscriberBox {
    private let transcriber: AudioStreamTranscriber
    init(_ t: AudioStreamTranscriber) { self.transcriber = t }
    func stop() async {
        await transcriber.stopStreamTranscription()
    }
}
