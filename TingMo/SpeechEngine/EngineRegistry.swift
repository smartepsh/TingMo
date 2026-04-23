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

    /// Download progress for models (engine ID → progress 0.0–1.0).
    var downloadProgress: [String: Double] = [:]

    /// Whether a download is in progress.
    var isDownloading: Bool {
        !downloadProgress.isEmpty
    }

    init() {
        let defaultID = WhisperKitEngine.defaultModelEngineID
        activeEngineID = UserDefaults.standard.string(forKey: "EngineRegistry.activeEngineID") ?? defaultID
        registerBuiltInEngines()
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

        // Parakeet — English-only, CoreML
        register(ParakeetEngine(isReady: false))
    }

    // MARK: - Engine Selection

    func setActiveEngine(_ engineID: String) {
        guard engines.contains(where: { $0.info.id == engineID }) else { return }
        activeEngineID = engineID
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
    func downloadModel(engineID: String, makeActiveWhenDone: Bool = true) {
        guard let engine = engines.first(where: { $0.info.id == engineID }) else { return }
        guard let whisper = engine as? WhisperKitEngine else { return }
        guard downloadProgress[engineID] == nil else { return }
        if whisper.info.isReady { return }

        downloadProgress[engineID] = 0

        Task { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.downloadProgress[engineID] = nil
                }
            }
            do {
                try await whisper.downloadModel { fraction in
                    Task { @MainActor [weak self] in
                        self?.downloadProgress[engineID] = fraction
                    }
                }
                if makeActiveWhenDone {
                    await MainActor.run { [weak self] in
                        self?.setActiveEngine(engineID)
                    }
                }
            } catch {
                NSLog("[TingMo] model download failed for \(engineID): \(error)")
            }
        }
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
