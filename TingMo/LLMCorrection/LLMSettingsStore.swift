import Foundation
import Observation

/// Persists the single global LLM correction config used before M4 presets.
@Observable
final class LLMSettingsStore {
    private static let storageKey = "LLMSettingsStore.config"

    var config: LLMConfig {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(LLMConfig.self, from: data) {
            config = decoded
        } else {
            config = LLMConfig()
        }
    }

    func resetProviderDefaults() {
        config.endpoint = config.provider.defaultEndpoint
        config.model = config.provider.defaultModel
        config.keychainService = nil
    }

    func hasAPIKey() -> Bool {
        let key = KeychainStore.get(service: config.effectiveKeychainService) ?? ""
        return !key.isEmpty
    }

    @discardableResult
    func saveAPIKey(_ value: String) -> Bool {
        KeychainStore.set(
            value.trimmingCharacters(in: .whitespacesAndNewlines),
            for: config.effectiveKeychainService
        )
    }

    @discardableResult
    func clearAPIKey() -> Bool {
        KeychainStore.delete(service: config.effectiveKeychainService)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
