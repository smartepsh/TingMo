import Foundation
import Observation

@Observable
final class LLMInstanceStore {
    private static let storageKey = "LLMInstanceStore.state"

    private struct StoredState: Codable {
        var instances: [LLMInstance]
        var selectedInstanceID: UUID
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private let getAPIKey: (String) -> String?
    private let saveAPIKeyValue: (String, String) -> Bool
    private let deleteAPIKey: (String) -> Bool

    var instances: [LLMInstance] {
        didSet { save() }
    }

    var selectedInstanceID: UUID {
        didSet { save() }
    }

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = LLMInstanceStore.storageKey,
        defaultID: UUID = UUID(),
        getAPIKey: @escaping (String) -> String? = { EncryptedKeyStore.get(service: $0) },
        saveAPIKey: @escaping (String, String) -> Bool = { EncryptedKeyStore.set($0, for: $1) },
        deleteAPIKey: @escaping (String) -> Bool = { EncryptedKeyStore.delete(service: $0) }
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.getAPIKey = getAPIKey
        self.saveAPIKeyValue = saveAPIKey
        self.deleteAPIKey = deleteAPIKey

        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(StoredState.self, from: data),
           !decoded.instances.isEmpty {
            instances = decoded.instances
            selectedInstanceID = decoded.selectedInstanceID
        } else {
            let defaultInstance = LLMInstance.defaultInstance(id: defaultID)
            instances = [defaultInstance]
            selectedInstanceID = defaultInstance.id
            save()
        }
    }

    var selectedInstance: LLMInstance? {
        instance(id: selectedInstanceID) ?? instances.first
    }

    func instance(id: UUID) -> LLMInstance? {
        instances.first { $0.id == id }
    }

    func llmConfig(for preset: ConfigPreset) -> LLMConfig? {
        guard let llmInstanceID = preset.llmInstanceID,
              let instance = instance(id: llmInstanceID)
        else { return nil }

        return preset.llmConfig(resolving: instance)
    }

    func upsert(_ instance: LLMInstance) {
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[index] = instance
        } else {
            instances.append(instance)
        }
    }

    @discardableResult
    func addInstance(provider: LLMProviderID = .openAICompatible) -> LLMInstance {
        let defaultName = nextDefaultName(for: provider)
        let instance = LLMInstance(displayName: defaultName, provider: provider)
        instances.append(instance)
        selectedInstanceID = instance.id
        return instance
    }

    private func nextDefaultName(for provider: LLMProviderID) -> String {
        let base = provider.displayName
        let existing = Set(instances.filter { $0.provider == provider }.map(\.displayName))
        var index = 1
        while true {
            let candidate = index == 1 ? base : "\(base) \(index)"
            if !existing.contains(candidate) { return candidate }
            index += 1
        }
    }

    @discardableResult
    func deleteInstance(id: UUID) -> Bool {
        guard let index = instances.firstIndex(where: { $0.id == id })
        else { return false }

        let instance = instances[index]
        guard clearAPIKey(for: instance) else { return false }

        instances.remove(at: index)

        if selectedInstanceID == id, let fallback = instances.first {
            selectedInstanceID = fallback.id
        }

        return true
    }

    @discardableResult
    func updateProvider(for id: UUID, provider: LLMProviderID) -> Bool {
        guard var instance = instance(id: id) else { return false }
        guard instance.provider != provider else { return true }
        guard clearAPIKey(for: instance) else { return false }

        let usedProviderName = instance.displayName == instance.provider.displayName
        instance.provider = provider
        instance.endpoint = provider.defaultBaseURL
        instance.model = provider.defaultModel
        if usedProviderName {
            instance.displayName = provider.displayName
        }
        upsert(instance)
        return true
    }

    func hasAPIKey(for instance: LLMInstance) -> Bool {
        let key = getAPIKey(instance.keychainService) ?? ""
        return !key.isEmpty
    }

    @discardableResult
    func saveAPIKey(_ value: String, for instance: LLMInstance) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return saveAPIKeyValue(trimmed, instance.keychainService)
    }

    @discardableResult
    func clearAPIKey(for instance: LLMInstance) -> Bool {
        deleteAPIKey(instance.keychainService)
    }

    private func save() {
        let state = StoredState(instances: instances, selectedInstanceID: selectedInstanceID)
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
