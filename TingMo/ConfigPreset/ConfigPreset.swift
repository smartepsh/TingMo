import Foundation
import Observation

/// The default work configuration: output language, speech engine, and correction behavior.
struct ConfigPreset: Identifiable, Codable, Equatable {
    static let defaultSpeechEngineID = "whisperkit-tiny"
    static let rawOutputLanguage = "raw"

    var id: UUID
    var name: String
    var outputLanguage: String
    var speechEngineID: String
    var llmInstanceID: UUID?
    var correctionEnabled: Bool
    var correctionPrompt: String
    var correctionTemperature: Double

    init(
        id: UUID = UUID(),
        name: String = String(localized: "Default"),
        outputLanguage: String = Self.rawOutputLanguage,
        speechEngineID: String = Self.defaultSpeechEngineID,
        llmInstanceID: UUID? = nil,
        correctionEnabled: Bool = false,
        correctionPrompt: String = LLMConfig.defaultSystemPrompt,
        correctionTemperature: Double = 0.3
    ) {
        self.id = id
        self.name = name
        self.outputLanguage = outputLanguage
        self.speechEngineID = speechEngineID
        self.llmInstanceID = llmInstanceID
        self.correctionEnabled = correctionEnabled
        self.correctionPrompt = correctionPrompt
        self.correctionTemperature = correctionTemperature
    }

    func llmConfig(resolving instance: LLMInstance) -> LLMConfig {
        LLMConfig(
            enabled: llmInstanceID != nil,
            provider: instance.provider,
            endpoint: instance.endpoint,
            model: instance.model,
            systemPrompt: correctionPrompt,
            temperature: correctionTemperature,
            keychainService: instance.keychainService
        )
    }
}

@Observable
final class ConfigPresetStore {
    private static let storageKey = "ConfigPresetStore.defaultPreset"

    private let defaults: UserDefaults
    private let storageKey: String

    var defaultPreset: ConfigPreset {
        didSet { save() }
    }

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = ConfigPresetStore.storageKey,
        defaultLLMInstanceID: UUID? = nil
    ) {
        self.defaults = defaults
        self.storageKey = storageKey

        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(ConfigPreset.self, from: data) {
            defaultPreset = decoded
        } else {
            defaultPreset = ConfigPreset(llmInstanceID: defaultLLMInstanceID)
            save()
        }
    }

    func replaceLLMInstanceSelection(deletedID: UUID, fallbackID: UUID?) {
        guard defaultPreset.llmInstanceID == deletedID else { return }
        defaultPreset.llmInstanceID = fallbackID
    }

    func replaceSpeechEngineSelection(deletedID: String, fallbackID: String) {
        guard defaultPreset.speechEngineID == deletedID else { return }
        defaultPreset.speechEngineID = fallbackID
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(defaultPreset) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
