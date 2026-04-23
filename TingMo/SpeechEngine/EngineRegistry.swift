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
        // WhisperKit models — registered with download status
        for model in WhisperKitEngine.availableModels {
            let isDownloaded = WhisperKitEngine.isModelDownloaded(model)
            register(WhisperKitEngine(model: model, isReady: isDownloaded))
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
}
