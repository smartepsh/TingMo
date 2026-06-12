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
        WhisperModel(id: "turbo-626", variant: "openai_whisper-large-v3-v20240930_626MB", name: "Whisper Turbo Compressed", size: "626 MB"),
        WhisperModel(id: "turbo", variant: "openai_whisper-large-v3-v20240930", name: "Whisper Turbo", size: "1.6 GB"),
        WhisperModel(id: "large-v3", variant: "openai_whisper-large-v3", name: "Whisper Large v3", size: "3.1 GB"),
        WhisperModel(id: "large-v3-turbo", variant: "openai_whisper-large-v3_turbo", name: "Whisper Large v3 (Optimized)", size: "3.1 GB"),
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
        /// When non-nil, the model was user-imported and lives at this
        /// absolute folder instead of under the managed argmaxinc tree.
        var importedFolder: URL?

        var isImported: Bool { importedFolder != nil }
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
    /// For user-imported models we return the pre-bound folder instead.
    static func modelFolder(for model: WhisperModel) -> URL {
        if let imported = model.importedFolder { return imported }
        return modelsDirectory
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

    /// Cache of previously-computed folder sizes keyed by model.id.
    /// SwiftUI redraws the settings form on every observable change (e.g.
    /// after saving an API key), which was triggering a full recursive file
    /// enumeration per model on every keystroke — noticeably blocking the
    /// main thread once medium/large variants were on disk. We invalidate
    /// this cache only when we actually change the folder contents
    /// (download completion, delete).
    private static var diskUsageCache: [String: Int64] = [:]
    private static let diskUsageCacheLock = NSLock()

    /// Size of the model folder on disk in bytes (0 if missing).
    /// Cached; call `invalidateDiskUsage(for:)` after a download or delete.
    static func diskUsage(for model: WhisperModel) -> Int64 {
        diskUsageCacheLock.lock()
        if let cached = diskUsageCache[model.id] {
            diskUsageCacheLock.unlock()
            return cached
        }
        diskUsageCacheLock.unlock()

        let folder = modelFolder(for: model)
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            diskUsageCacheLock.lock()
            diskUsageCache[model.id] = 0
            diskUsageCacheLock.unlock()
            return 0
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        diskUsageCacheLock.lock()
        diskUsageCache[model.id] = total
        diskUsageCacheLock.unlock()
        return total
    }

    /// Drop the cached disk-usage entry for a model. Call after download
    /// completion or deletion so the next UI read re-enumerates.
    static func invalidateDiskUsage(for model: WhisperModel) {
        diskUsageCacheLock.lock()
        diskUsageCache.removeValue(forKey: model.id)
        diskUsageCacheLock.unlock()
    }

    /// Remove the on-disk model folder and reset `isReady`. Returns true on
    /// success. The engine instance stays registered; the user can redownload.
    @discardableResult
    func deleteLocalFiles() -> Bool {
        let folder = Self.modelFolder(for: model)
        guard FileManager.default.fileExists(atPath: folder.path) else {
            info.isReady = false
            Self.invalidateDiskUsage(for: model)
            return true
        }
        do {
            try FileManager.default.removeItem(at: folder)
            loadLock.lock()
            whisperKit = nil
            loadLock.unlock()
            info.isReady = false
            Self.invalidateDiskUsage(for: model)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Download & load

    /// Download the model variant into our managed folder.
    /// No-op if already present on disk.
    /// - Parameter endpoint: HuggingFace-compatible host URL to pull from.
    ///   `nil` uses WhisperKit's built-in default (huggingface.co).
    func downloadModel(
        endpoint: String? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        if model.isImported {
            // Imported models live entirely on the user's disk.
            info.isReady = Self.isModelDownloaded(model)
            return
        }
        if Self.isModelDownloaded(model) {
            // Backfill the tokenizer for models downloaded before we started
            // bundling it. Best-effort: these models can still load through
            // WhisperKit's hub cache, so a failure here must not brick them.
            if !Self.isTokenizerBundled(for: model) {
                try? await downloadTokenizer(endpoint: endpoint)
            }
            info.isReady = true
            return
        }

        try FileManager.default.createDirectory(
            at: Self.modelsDirectory,
            withIntermediateDirectories: true
        )

        do {
            if let endpoint, !endpoint.isEmpty {
                _ = try await WhisperKit.download(
                    variant: model.variant,
                    downloadBase: Self.modelsDirectory,
                    from: "argmaxinc/whisperkit-coreml",
                    endpoint: endpoint
                ) { p in
                    progress?(p.fractionCompleted)
                }
            } else {
                _ = try await WhisperKit.download(
                    variant: model.variant,
                    downloadBase: Self.modelsDirectory,
                    from: "argmaxinc/whisperkit-coreml"
                ) { p in
                    progress?(p.fractionCompleted)
                }
            }
            try await downloadTokenizer(endpoint: endpoint)
            Self.invalidateDiskUsage(for: model)
            info.isReady = true
        } catch {
            throw SpeechEngineError.networkError(underlying: error)
        }
    }

    // MARK: - Tokenizer bundling

    /// HuggingFace repo that hosts the tokenizer for this variant, e.g.
    /// "openai/whisper-large-v3". The turbo variant shares large-v3's
    /// tokenizer. Imported models manage their own files, so they get nil.
    static func tokenizerRepo(for model: WhisperModel) -> String? {
        guard !model.isImported else { return nil }
        let prefix = "openai_whisper-"
        guard model.variant.hasPrefix(prefix) else { return nil }
        var size = String(model.variant.dropFirst(prefix.count))
        // Strip argmax packaging suffixes — quantization ("_626MB") and the
        // turbo-compile marker ("_turbo") don't change the vocabulary.
        if let quant = size.range(of: #"_\d+MB$"#, options: .regularExpression) {
            size.removeSubrange(quant)
        }
        if size.hasSuffix("_turbo") {
            size.removeLast("_turbo".count)
        }
        // The 2024-09-30 release (OpenAI's turbo model) shares large-v3's
        // tokenizer; WhisperKit's own variant mapping does the same.
        if size == "large-v3-v20240930" {
            size = "large-v3"
        }
        return "openai/whisper-\(size)"
    }

    /// Files WhisperKit needs to load the tokenizer without touching the
    /// network. Deliberately excludes config.json: the model folder already
    /// contains WhisperKit's own config.json and overwriting it would break
    /// model loading.
    private static let tokenizerFiles = ["tokenizer.json", "tokenizer_config.json"]

    /// True when the tokenizer files sit next to the .mlmodelc bundles, so
    /// `loadModel()` resolves the tokenizer offline (WhisperKit searches the
    /// model folder before falling back to a hub fetch).
    static func isTokenizerBundled(for model: WhisperModel) -> Bool {
        let folder = modelFolder(for: model)
        return tokenizerFiles.allSatisfy {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
    }

    /// Fetch the tokenizer files into the model folder from the given
    /// HuggingFace-compatible host (nil/empty falls back to huggingface.co).
    private func downloadTokenizer(endpoint: String?) async throws {
        guard let repo = Self.tokenizerRepo(for: model) else { return }
        let folder = Self.modelFolder(for: model)

        var base = (endpoint?.isEmpty == false ? endpoint! : "https://huggingface.co")
        while base.hasSuffix("/") { base.removeLast() }

        for file in Self.tokenizerFiles {
            let destination = folder.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: destination.path) { continue }

            guard let url = URL(string: "\(base)/\(repo)/resolve/main/\(file)") else {
                throw URLError(.badURL)
            }
            let request = URLRequest(url: url, timeoutInterval: 60)
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status), !data.isEmpty else {
                throw URLError(.badServerResponse)
            }
            try data.write(to: destination, options: .atomic)
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
            // WhisperKit defaults detectLanguage to false when prefill is on,
            // and a nil language then prefills <|en|> — forcing English output
            // for Chinese speech. Detect explicitly when no language is pinned.
            detectLanguage: language.isEmpty,
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
            detectLanguage: language.isEmpty,
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
