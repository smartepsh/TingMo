import Foundation
import Observation

/// Manages the list of available speech engines, model downloads, and active engine selection.
@Observable
final class EngineRegistry {
    /// All registered engines.
    private(set) var engines: [any SpeechEngine] = []

    /// Currently active engine ID (persisted).
    var activeEngineID: String {
        didSet { UserDefaults.standard.set(activeEngineID, forKey: "EngineRegistry.activeEngineID") }
    }

    /// The currently active engine instance.
    var activeEngine: (any SpeechEngine)? {
        engines.first { $0.info.id == activeEngineID }
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

    /// Engine IDs currently running `loadModel()` (for a "loading…" UI hint).
    /// Large variants take several seconds to compile CoreML; without this
    /// the user has no feedback that anything is happening.
    var loadingEngineIDs: Set<String> = []

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
        let defaultID = WhisperKitEngine.defaultModelEngineID
        activeEngineID = UserDefaults.standard.string(forKey: "EngineRegistry.activeEngineID") ?? defaultID
        registerBuiltInEngines()
        registerImportedModels()
        preloadActiveEngine()
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
        // If the active engine was a remote one that was removed, fall back
        if activeEngine == nil, let fallback = engines.first(where: { $0.info.id == ConfigPreset.defaultSpeechEngineID }) {
            activeEngineID = fallback.info.id
        }
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

    // MARK: - Engine Selection

    func setActiveEngine(_ engineID: String) {
        guard engines.contains(where: { $0.info.id == engineID }) else { return }
        activeEngineID = engineID
        preloadActiveEngine()
    }

    /// Kick off a background `loadModel()` for the active engine so the
    /// first recording after a model switch doesn't pay the CoreML
    /// compile/load tax synchronously. No-op if already loaded.
    func preloadActiveEngine() {
        guard let whisper = activeEngine as? WhisperKitEngine else { return }
        guard whisper.info.isReady else { return }
        let id = whisper.info.id
        loadingEngineIDs.insert(id)
        Task.detached { [weak self] in
            try? await whisper.loadModel()
            await MainActor.run { [weak self] in
                _ = self?.loadingEngineIDs.remove(id)
            }
        }
    }

    /// Load the active engine synchronously for the pipeline. Updates the
    /// `loadingEngineIDs` hint around the call so UI can show a "loading"
    /// badge during first-use compile/prewarm.
    func loadActiveEngine() async throws {
        guard let whisper = activeEngine as? WhisperKitEngine else { return }
        let id = whisper.info.id
        loadingEngineIDs.insert(id)
        defer { loadingEngineIDs.remove(id) }
        try await whisper.loadModel()
    }

    // MARK: - Language Compatibility

    func compatibleEngines(for language: String) -> [any SpeechEngine] {
        engines.filter { $0.supportsLanguage(language) }
    }

    func isActiveEngineCompatible(with language: String) -> Bool {
        activeEngine?.supportsLanguage(language) ?? false
    }

    // MARK: - Downloads

    /// Kick off a download for the given engine ID. When it finishes, if no
    /// other model is currently active-and-ready, the newly downloaded model
    /// becomes active. Safe to call twice — returns immediately if already
    /// downloading.
    @MainActor
    func downloadModel(
        engineID: String,
        makeActiveWhenDone: Bool = true,
        onActiveWhenDone: (() -> Void)? = nil
    ) {
        guard let engine = engines.first(where: { $0.info.id == engineID }) else { return }
        guard let whisper = engine as? WhisperKitEngine else { return }
        guard downloadProgress[engineID] == nil else { return }
        if whisper.info.isReady { return }

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
                try await whisper.downloadModel(endpoint: endpoint) { fraction in
                    Task { @MainActor [weak self] in
                        self?.downloadProgress[engineID] = fraction
                    }
                }
                if Task.isCancelled { return }
                if makeActiveWhenDone {
                    await MainActor.run { [weak self] in
                        self?.setActiveEngine(engineID)
                        onActiveWhenDone?()
                    }
                }
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
        guard let engine = engines.first(where: { $0.info.id == engineID }) as? WhisperKitEngine else {
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
