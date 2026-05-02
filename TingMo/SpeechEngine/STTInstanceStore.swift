import Foundation
import Observation

@Observable
final class STTInstanceStore {
    private static let storageKey = "STTInstanceStore.instances"

    private let defaults: UserDefaults
    private let storageKey: String
    private let getAPIKey: (String) -> String?
    private let saveAPIKeyValue: (String, String) -> Bool
    private let deleteAPIKey: (String) -> Bool

    var instances: [STTInstance] {
        didSet { save() }
    }

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = STTInstanceStore.storageKey,
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
           let decoded = try? JSONDecoder().decode([STTInstance].self, from: data),
           !decoded.isEmpty {
            instances = decoded
        } else {
            instances = []
            save()
        }
    }

    func instance(id: UUID) -> STTInstance? {
        instances.first { $0.id == id }
    }

    func upsert(_ instance: STTInstance) {
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[index] = instance
        } else {
            instances.append(instance)
        }
    }

    @discardableResult
    func addInstance(provider: STTProviderID) -> STTInstance {
        let defaultName = nextDefaultName(for: provider)
        let instance = STTInstance(displayName: defaultName, provider: provider)
        instances.append(instance)
        return instance
    }

    private func nextDefaultName(for provider: STTProviderID) -> String {
        let base = provider.defaultInstanceName
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
        _ = clearAPIKey(for: instance)
        instances.remove(at: index)
        return true
    }

    func hasAPIKey(for instance: STTInstance) -> Bool {
        let key = getAPIKey(instance.keychainService) ?? ""
        return !key.isEmpty
    }

    @discardableResult
    func saveAPIKey(_ value: String, for instance: STTInstance) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return saveAPIKeyValue(trimmed, instance.keychainService)
    }

    @discardableResult
    func clearAPIKey(for instance: STTInstance) -> Bool {
        deleteAPIKey(instance.keychainService)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(instances) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
