import Foundation

func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

@main
struct LLMInstanceTests {
    static func main() {
        let suiteName = "tingmo.llm-instance-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let secondID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        let defaultInstance = LLMInstance.defaultInstance(id: firstID)
        assert(defaultInstance.displayName == "OpenAI-compatible", "default display name should be provider display name")
        assert(defaultInstance.keychainService == "tingmo.llm.instance.11111111-1111-1111-1111-111111111111", "default keychain service should be instance scoped")
        assert(defaultInstance.effectiveEndpoint == LLMProviderID.openAICompatible.defaultEndpoint, "default endpoint should resolve from provider")
        assert(defaultInstance.effectiveModel == LLMProviderID.openAICompatible.defaultModel, "default model should resolve from provider")

        let custom = LLMInstance(
            id: secondID,
            displayName: "Work OpenAI",
            provider: .openAICompatible,
            endpoint: " https://example.com/v1/chat/completions ",
            model: " gpt-work ",
            keychainService: "tingmo.llm.instance.custom"
        )
        assert(custom.effectiveEndpoint == "https://example.com/v1/chat/completions", "custom endpoint should trim whitespace")
        assert(custom.effectiveModel == "gpt-work", "custom model should trim whitespace")

        let store = LLMInstanceStore(defaults: defaults, defaultID: firstID)
        assert(store.instances.count == 1, "store should create one default instance")
        assert(store.selectedInstanceID == firstID, "store should select the default instance")

        store.upsert(custom)
        assert(store.instances.count == 2, "upsert should add a second instance")
        assert(store.instance(id: secondID)?.displayName == "Work OpenAI", "store should retrieve instance by id")

        store.selectedInstanceID = secondID
        let reloaded = LLMInstanceStore(defaults: defaults, defaultID: firstID)
        assert(reloaded.instances.count == 2, "store should persist instances")
        assert(reloaded.selectedInstanceID == secondID, "store should persist selection")
        assert(reloaded.instance(id: secondID)?.keychainService == "tingmo.llm.instance.custom", "store should persist keychain reference only")

        var savedService: String?
        var deletedService: String?
        let keyStore = LLMInstanceStore(
            defaults: defaults,
            storageKey: "key-test",
            defaultID: firstID,
            getAPIKey: { service in service == defaultInstance.keychainService ? "stored" : nil },
            saveAPIKey: { value, service in
                savedService = service
                return value == "secret"
            },
            deleteAPIKey: { service in
                deletedService = service
                return true
            }
        )

        assert(keyStore.hasAPIKey(for: defaultInstance), "hasAPIKey should read by instance keychain service")
        assert(keyStore.saveAPIKey(" secret ", for: defaultInstance), "saveAPIKey should trim and save non-empty values")
        assert(savedService == defaultInstance.keychainService, "saveAPIKey should use the instance keychain service")
        assert(keyStore.clearAPIKey(for: defaultInstance), "clearAPIKey should delete by instance keychain service")
        assert(deletedService == defaultInstance.keychainService, "clearAPIKey should use the instance keychain service")

        let added = keyStore.addInstance(provider: .anthropic)
        assert(added.provider == .anthropic, "addInstance should use requested provider")
        assert(added.displayName == "Anthropic", "addInstance should default display name from provider")
        assert(keyStore.instances.contains { $0.id == added.id }, "addInstance should append instance")

        keyStore.selectedInstanceID = added.id
        assert(keyStore.deleteInstance(id: added.id), "deleteInstance should remove existing instance")
        assert(!keyStore.instances.contains { $0.id == added.id }, "deleteInstance should remove the instance from store")
        assert(keyStore.selectedInstanceID == firstID, "deleteInstance should fall back to first remaining instance")
        assert(deletedService == added.keychainService, "deleteInstance should clear the removed instance key")

        deletedService = nil
        assert(keyStore.updateProvider(for: firstID, provider: .anthropic), "updateProvider should update an existing instance")
        assert(keyStore.instance(id: firstID)?.provider == .anthropic, "updateProvider should change provider")
        assert(keyStore.instance(id: firstID)?.endpoint == LLMProviderID.anthropic.defaultEndpoint, "updateProvider should reset endpoint")
        assert(keyStore.instance(id: firstID)?.model == LLMProviderID.anthropic.defaultModel, "updateProvider should reset model")
        assert(deletedService == defaultInstance.keychainService, "updateProvider should clear the previous provider key")

        let failingDeleteStore = LLMInstanceStore(
            defaults: defaults,
            storageKey: "delete-fail-test",
            defaultID: firstID,
            getAPIKey: { _ in "stored" },
            saveAPIKey: { _, _ in true },
            deleteAPIKey: { _ in false }
        )
        let undeletable = failingDeleteStore.addInstance()
        assert(!failingDeleteStore.deleteInstance(id: undeletable.id), "deleteInstance should fail when key deletion fails")
        assert(failingDeleteStore.instances.contains { $0.id == undeletable.id }, "deleteInstance should keep instance when key deletion fails")

        print("PASS: LLMInstance tests")
    }
}
