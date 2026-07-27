import Foundation
import Observation

/// Manages available speech engines plus their download and runtime preparation lifecycle.
@Observable
final class EngineRegistry {
    /// All registered engines.
    private(set) var engines: [any SpeechEngine] = []

    enum PreparationState: Equatable {
        case ready
        case notDownloaded
        case unloaded
        case preparing
        case failed(String)
    }

    func engine(id: String) -> (any SpeechEngine)? {
        engines.first { $0.info.id == id }
    }

    /// Download progress for models (engine ID → progress 0.0–1.0).
    var downloadProgress: [String: Double] = [:]

    /// Bumped whenever a model is downloaded or deleted so UI that depends on
    /// disk-usage totals can re-render.
    var diskUsageVersion: Int = 0

    /// Last download failure per engine (surfaced to UI). Cleared on retry.
    var downloadErrors: [String: String] = [:]

    /// Engine IDs currently downloading, prewarming, or loading a model.
    var loadingEngineIDs: Set<String> = []

    /// Most recent runtime preparation failure per engine. Unlike download UI
    /// errors, these are also used by the recording gate.
    var preparationErrors: [String: String] = [:]

    /// In-flight download tasks keyed by engine ID, so we can cancel them.
    private var downloadTasks: [String: Task<Void, Never>] = [:]

    /// Source of the HuggingFace endpoint (and other download options).
    /// Injected so the registry can honour the user's mirror choice.
    private let downloadSource: DownloadSourcePreference

    /// Tracks user-imported WhisperKit models so they show up alongside the
    /// built-in variants after a restart.
    private let importedModelStore: ImportedModelStore

    /// Provides remote STT instances that are dynamically registered as engines.
    private let sttInstanceStore: STTInstanceStore

    /// Whether a download is in progress.
    var isDownloading: Bool {
        !downloadProgress.isEmpty
    }

    /// True if the engine is currently loading its CoreML model.
    func isLoading(_ engineID: String) -> Bool {
        loadingEngineIDs.contains(engineID)
    }

    /// Most recent download failure for the engine, if any.
    func downloadError(for engineID: String) -> String? {
        downloadErrors[engineID]
    }

    init(
        downloadSource: DownloadSourcePreference,
        importedModelStore: ImportedModelStore,
        sttInstanceStore: STTInstanceStore
    ) {
        self.downloadSource = downloadSource
        self.importedModelStore = importedModelStore
        self.sttInstanceStore = sttInstanceStore
        registerBuiltInEngines()
        registerImportedModels()
    }

    // MARK: - Registration

    func register(_ engine: any SpeechEngine) {
        engines.append(engine)
    }

    private func registerBuiltInEngines() {
        // WhisperKit models — isReady is derived from disk state in init.
        for model in WhisperKitEngine.availableModels {
            register(WhisperKitEngine(model: model))
        }

        // Remote engines from STTInstanceStore
        registerRemoteSTTEngines()

        // SenseVoice — zh/yue/en/ja/ko, CPU via sherpa-onnx. Registered
        // unconditionally; `isReady` reflects whether the model is installed.
        register(SenseVoiceEngine())

        // Parakeet — English-only, CoreML
        register(ParakeetEngine(isReady: false))
    }

    private func registerRemoteSTTEngines() {
        // Remove existing remote engines
        engines.removeAll { $0 is RemoteSpeechEngine }

        // Create engines from instances
        for instance in sttInstanceStore.instances {
            let engine = RemoteSpeechEngine(instance: instance)
            register(engine)
        }
    }

    /// Re-create remote STT engines from the current STTInstanceStore state.
    func refreshRemoteSTTEngines() {
        registerRemoteSTTEngines()
    }

    /// Re-query the keychain for every remote engine and update `isReady`.
    /// Called after a successful API key save / delete / connectivity test.
    func refreshRemoteEnginesReadiness() {
        for engine in engines {
            if let remote = engine as? RemoteSpeechEngine {
                remote.refreshReadiness()
            }
        }
        // Nudge the `engines` array so @Observable consumers see the
        // downstream `info.isReady` change — SwiftUI only tracks the
        // array-level reference by default.
        engines = engines
    }

    private func registerImportedModels() {
        for imported in importedModelStore.models {
            let model = WhisperKitEngine.WhisperModel(
                id: "imported-\(imported.id)",
                variant: imported.id,
                name: imported.displayName,
                size: String(localized: "Imported"),
                importedFolder: imported.folderURL
            )
            register(WhisperKitEngine(model: model))
        }
    }

    /// Drop any currently-registered imported engines and re-register from
    /// the store. Called after a successful import or delete so the UI
    /// reflects changes without restarting the app.
    func refreshImportedEngines() {
        engines.removeAll {
            guard let whisper = $0 as? WhisperKitEngine else { return false }
            return whisper.model.isImported
        }
        registerImportedModels()
    }

    // MARK: - Engine Preparation

    /// Runtime preparation state for an engine. Remote engines require no
    /// local model load and are ready as soon as their normal readiness checks
    /// pass. WhisperKit readiness includes prewarm and in-memory loading.
    func preparationState(for engineID: String) -> PreparationState {
        guard let engine = engine(id: engineID) else {
            return .failed(String(localized: "The selected speech engine is unavailable."))
        }
        guard let downloadable = engine as? any DownloadableEngine else { return .ready }
        if loadingEngineIDs.contains(engineID) { return .preparing }
        if let message = preparationErrors[engineID] { return .failed(message) }
        guard downloadable.info.isReady else { return .notDownloaded }

        return switch downloadable.modelLoadState {
        case .unloaded: .unloaded
        case .loading: .preparing
        case .loaded: .ready
        case .failed(let message): .failed(message)
        }
    }

    /// Prepare one explicitly-selected local engine. Selection itself belongs
    /// to ConfigPresetStore; the registry only performs the requested side
    /// effect. Calls are safe to repeat because WhisperKitEngine is
    /// single-flight.
    func prepareEngine(_ engineID: String, downloadIfNeeded: Bool = false) {
        guard let downloadable = engine(id: engineID) as? any DownloadableEngine else { return }
        guard downloadable.info.isReady || downloadIfNeeded else { return }
        guard !downloadable.isModelLoaded else {
            loadingEngineIDs.remove(engineID)
            preparationErrors[engineID] = nil
            return
        }
        guard !loadingEngineIDs.contains(engineID) else { return }

        loadingEngineIDs.insert(engineID)
        preparationErrors[engineID] = nil
        let endpoint = downloadSource.effectiveEndpoint
        let needsDownload = !downloadable.info.isReady
        Task.detached { [weak self] in
            let failureMessage: String?
            do {
                if needsDownload {
                    try await downloadable.downloadModel(endpoint: endpoint, progress: nil)
                }
                try await downloadable.loadModel()
                failureMessage = nil
            } catch {
                failureMessage = error.localizedDescription
                NSLog("[TingMo] model preparation failed for \(engineID): \(error)")
            }
            await MainActor.run { [weak self] in
                self?.preparationErrors[engineID] = failureMessage
                _ = self?.loadingEngineIDs.remove(engineID)
            }
        }
    }

    // MARK: - Language Compatibility

    func compatibleEngines(for language: String) -> [any SpeechEngine] {
        engines.filter { $0.supportsLanguage(language) }
    }

    // MARK: - Downloads

    /// Kick off a download for the given engine ID. Safe to call twice —
    /// returns immediately if that engine is already downloading.
    @MainActor
    func downloadModel(engineID: String) {
        guard let engine = engines.first(where: { $0.info.id == engineID }) else { return }
        guard let downloadable = engine as? any DownloadableEngine else { return }
        guard downloadProgress[engineID] == nil else { return }
        if downloadable.info.isReady { return }

        downloadProgress[engineID] = 0
        downloadErrors[engineID] = nil

        let endpoint = downloadSource.effectiveEndpoint

        let task = Task { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.downloadProgress[engineID] = nil
                    self?.downloadTasks[engineID] = nil
                    self?.diskUsageVersion &+= 1
                }
            }
            do {
                try await downloadable.downloadModel(endpoint: endpoint) { fraction in
                    Task { @MainActor [weak self] in
                        self?.downloadProgress[engineID] = fraction
                    }
                }
                if Task.isCancelled { return }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run { [weak self] in
                    self?.downloadErrors[engineID] = Self.describeDownloadError(error)
                }
            }
        }
        downloadTasks[engineID] = task
    }

    /// Cancel an in-flight download. Best-effort: the underlying HTTP
    /// request may already be mid-write; the partial folder is left on disk
    /// for a later retry (WhisperKit resumes file-by-file).
    func cancelDownload(engineID: String) {
        downloadTasks[engineID]?.cancel()
        downloadTasks[engineID] = nil
        downloadProgress[engineID] = nil
    }

    /// Cancel / clear a failed download so the user can retry.
    func clearDownloadError(for engineID: String) {
        downloadErrors[engineID] = nil
    }

    /// Removes the on-disk model folder for a downloaded WhisperKit variant
    /// and refreshes the engine's `isReady` flag.
    @discardableResult
    func deleteDownloadedModel(engineID: String) -> Bool {
        guard let engine = engines.first(where: { $0.info.id == engineID }) as? any DownloadableEngine else {
            return false
        }
        let result = engine.deleteLocalFiles()
        if result { diskUsageVersion &+= 1 }
        return result
    }

    private static func describeDownloadError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain, ns.code == 28 {
            return String(localized: "Disk is full. Free up space and try again.")
        }
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet:
                return String(localized: "No internet connection.")
            case NSURLErrorTimedOut:
                return String(localized: "Download timed out.")
            case NSURLErrorCancelled:
                return String(localized: "Download cancelled.")
            default:
                break
            }
        }
        return error.localizedDescription
    }

    /// True if the given engine has an active download.
    func isDownloading(_ engineID: String) -> Bool {
        downloadProgress[engineID] != nil
    }

    /// Progress for the given engine (0.0–1.0) if downloading, else nil.
    func progress(for engineID: String) -> Double? {
        downloadProgress[engineID]
    }
}
