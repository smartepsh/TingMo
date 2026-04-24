import Foundation
import Observation

/// The M4 preset shape: one default bundle for LLM correction settings and a
/// placeholder switch for the future knowledge-base retrieval layer.
struct ConfigPreset: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var llm: LLMConfig
    var knowledgeBaseEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String = String(localized: "Default"),
        llm: LLMConfig = LLMConfig(),
        knowledgeBaseEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.llm = llm
        self.knowledgeBaseEnabled = knowledgeBaseEnabled
    }
}

@Observable
final class ConfigPresetStore {
    private static let storageKey = "ConfigPresetStore.defaultPreset"
    private static let legacyLLMStorageKey = "LLMSettingsStore.config"

    var defaultPreset: ConfigPreset {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(ConfigPreset.self, from: data) {
            defaultPreset = decoded
        } else if let data = UserDefaults.standard.data(forKey: Self.legacyLLMStorageKey),
                  let legacyConfig = try? JSONDecoder().decode(LLMConfig.self, from: data) {
            defaultPreset = ConfigPreset(llm: legacyConfig)
            save()
        } else {
            defaultPreset = ConfigPreset()
        }
    }

    var llmConfig: LLMConfig {
        get { defaultPreset.llm }
        set { defaultPreset.llm = newValue }
    }

    var knowledgeBaseEnabled: Bool {
        get { defaultPreset.knowledgeBaseEnabled }
        set { defaultPreset.knowledgeBaseEnabled = newValue }
    }

    func resetProviderDefaults() {
        defaultPreset.llm.endpoint = defaultPreset.llm.provider.defaultEndpoint
        defaultPreset.llm.model = defaultPreset.llm.provider.defaultModel
        defaultPreset.llm.keychainService = nil
    }

    func hasAPIKey() -> Bool {
        let key = KeychainStore.get(service: defaultPreset.llm.effectiveKeychainService) ?? ""
        return !key.isEmpty
    }

    @discardableResult
    func saveAPIKey(_ value: String) -> Bool {
        KeychainStore.set(
            value.trimmingCharacters(in: .whitespacesAndNewlines),
            for: defaultPreset.llm.effectiveKeychainService
        )
    }

    @discardableResult
    func clearAPIKey() -> Bool {
        KeychainStore.delete(service: defaultPreset.llm.effectiveKeychainService)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(defaultPreset) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
