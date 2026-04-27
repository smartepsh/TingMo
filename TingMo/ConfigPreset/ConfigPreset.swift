import Foundation
import Observation

/// The default work configuration: language, speech engine, and correction behavior.
struct ConfigPreset: Identifiable, Codable, Equatable {
    static let defaultLanguageCode = "zh"
    static let defaultSpeechEngineID = "whisperkit-tiny"

    var id: UUID
    var name: String
    var languageCode: String
    var speechEngineID: String
    var llmInstanceID: UUID?
    var correctionEnabled: Bool
    var correctionPrompt: String
    var correctionTemperature: Double

    init(
        id: UUID = UUID(),
        name: String = String(localized: "Default"),
        languageCode: String = Self.defaultLanguageCode,
        speechEngineID: String = Self.defaultSpeechEngineID,
        llmInstanceID: UUID? = nil,
        correctionEnabled: Bool = false,
        correctionPrompt: String = LLMConfig.defaultSystemPrompt,
        correctionTemperature: Double = 0.3
    ) {
        self.id = id
        self.name = name
        self.languageCode = languageCode
        self.speechEngineID = speechEngineID
        self.llmInstanceID = llmInstanceID
        self.correctionEnabled = correctionEnabled
        self.correctionPrompt = correctionPrompt
        self.correctionTemperature = correctionTemperature
    }

    func llmConfig(resolving instance: LLMInstance) -> LLMConfig {
        LLMConfig(
            enabled: correctionEnabled,
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
    private static let legacyLLMStorageKey = "LLMSettingsStore.config"
    private static let legacyLanguageStorageKey = "LanguagePreference.currentLanguage"
    private static let legacyEngineStorageKey = "EngineRegistry.activeEngineID"

    private struct LegacyPreset: Codable {
        var id: UUID
        var name: String
        var llm: LLMConfig
    }

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
        } else if let migrated = Self.migratedPreset(
            defaults: defaults,
            storageKey: storageKey,
            defaultLLMInstanceID: defaultLLMInstanceID
        ) {
            defaultPreset = migrated
            save()
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

    private static func migratedPreset(
        defaults: UserDefaults,
        storageKey: String,
        defaultLLMInstanceID: UUID?
    ) -> ConfigPreset? {
        guard let llmConfig = legacyLLMConfig(defaults: defaults, storageKey: storageKey) else {
            return nil
        }

        let legacyPreset = legacyPreset(defaults: defaults, storageKey: storageKey)
        return ConfigPreset(
            id: legacyPreset?.id ?? UUID(),
            name: legacyPreset?.name ?? String(localized: "Default"),
            languageCode: defaults.string(forKey: legacyLanguageStorageKey) ?? ConfigPreset.defaultLanguageCode,
            speechEngineID: defaults.string(forKey: legacyEngineStorageKey) ?? ConfigPreset.defaultSpeechEngineID,
            llmInstanceID: defaultLLMInstanceID,
            correctionEnabled: llmConfig.enabled,
            correctionPrompt: llmConfig.systemPrompt,
            correctionTemperature: llmConfig.temperature
        )
    }

    private static func legacyPreset(defaults: UserDefaults, storageKey: String) -> LegacyPreset? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(LegacyPreset.self, from: data)
    }

    static func legacyLLMConfig(defaults: UserDefaults, storageKey: String = storageKey) -> LLMConfig? {
        if let legacyPreset = legacyPreset(defaults: defaults, storageKey: storageKey) {
            return legacyPreset.llm
        }

        guard let data = defaults.data(forKey: legacyLLMStorageKey) else { return nil }
        return try? JSONDecoder().decode(LLMConfig.self, from: data)
    }
}
