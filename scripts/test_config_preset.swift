import Foundation

func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

private struct LegacyPreset: Codable {
    var id: UUID
    var name: String
    var llm: LLMConfig
}

@main
struct ConfigPresetTests {
    static func main() {
        let suiteName = "tingmo.config-preset-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let instanceID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let instance = LLMInstance(
            id: instanceID,
            displayName: "Work Anthropic",
            provider: .anthropic,
            endpoint: " https://example.com/messages ",
            model: " claude-work ",
            keychainService: "tingmo.llm.instance.work"
        )

        let defaultPreset = ConfigPreset()
        assert(defaultPreset.languageCode == "zh", "default preset should own the default language")
        assert(defaultPreset.speechEngineID == "whisperkit-tiny", "default preset should own the default speech engine")
        assert(defaultPreset.llmInstanceID == nil, "default preset should not require an instance before migration")
        assert(!defaultPreset.correctionEnabled, "LLM correction should default off")

        let preset = ConfigPreset(
            name: "Writing",
            languageCode: "en",
            speechEngineID: "remote-groq",
            llmInstanceID: instanceID,
            correctionEnabled: true,
            correctionPrompt: " Correct carefully ",
            correctionTemperature: 1.2
        )

        assert(preset.languageCode == "en", "preset should store selected language")
        assert(preset.speechEngineID == "remote-groq", "preset should store selected speech engine")
        assert(preset.llmInstanceID == instanceID, "preset should store selected LLM instance")

        let resolved = preset.llmConfig(resolving: instance)
        assert(resolved.enabled, "resolved config should preserve preset correction enabled state")
        assert(resolved.provider == .anthropic, "resolved config should use instance provider")
        assert(resolved.effectiveEndpoint == "https://example.com/messages", "resolved config should use instance endpoint")
        assert(resolved.effectiveModel == "claude-work", "resolved config should use instance model")
        assert(resolved.effectiveSystemPrompt == "Correct carefully", "resolved config should use preset prompt")
        assert(resolved.normalizedTemperature == 1.2, "resolved config should use preset temperature")
        assert(resolved.effectiveKeychainService == "tingmo.llm.instance.work", "resolved config should use instance keychain service")

        let store = ConfigPresetStore(defaults: defaults, storageKey: "preset-test")
        store.defaultPreset = preset

        let reloaded = ConfigPresetStore(defaults: defaults, storageKey: "preset-test")
        assert(reloaded.defaultPreset.name == "Writing", "store should persist preset name")
        assert(reloaded.defaultPreset.languageCode == "en", "store should persist preset language")
        assert(reloaded.defaultPreset.speechEngineID == "remote-groq", "store should persist preset speech engine")
        assert(reloaded.defaultPreset.llmInstanceID == instanceID, "store should persist selected LLM instance")
        assert(reloaded.defaultPreset.correctionEnabled, "store should persist correction enabled state")
        assert(reloaded.defaultPreset.correctionPrompt == " Correct carefully ", "store should persist correction prompt")
        assert(reloaded.defaultPreset.correctionTemperature == 1.2, "store should persist correction temperature")

        let otherID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let other = LLMInstance(
            id: otherID,
            displayName: "Other OpenAI",
            provider: .openAICompatible,
            endpoint: "https://example.com/chat",
            model: "gpt-other",
            keychainService: "tingmo.llm.instance.other"
        )
        let instanceStore = LLMInstanceStore(defaults: defaults, storageKey: "instance-test", defaultID: instanceID)
        instanceStore.upsert(instance)
        instanceStore.upsert(other)
        instanceStore.selectedInstanceID = otherID

        let presetSelectedConfig = instanceStore.llmConfig(for: preset)
        assert(presetSelectedConfig?.provider == .anthropic, "preset LLM instance should win over store selection")
        assert(presetSelectedConfig?.effectiveKeychainService == "tingmo.llm.instance.work", "preset-selected config should use the referenced instance key")

        let missingPreset = ConfigPreset(llmInstanceID: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!)
        assert(instanceStore.llmConfig(for: missingPreset) == nil, "missing preset LLM instance should not fall back to selected instance")

        store.defaultPreset.llmInstanceID = instanceID
        store.replaceLLMInstanceSelection(deletedID: instanceID, fallbackID: otherID)
        assert(store.defaultPreset.llmInstanceID == otherID, "deleted preset LLM instance should fall back to supplied instance")

        store.replaceLLMInstanceSelection(deletedID: otherID, fallbackID: nil)
        assert(store.defaultPreset.llmInstanceID == nil, "deleted preset LLM instance should clear when no fallback exists")

        store.defaultPreset.speechEngineID = "imported-old"
        store.replaceSpeechEngineSelection(deletedID: "imported-old", fallbackID: "whisperkit-tiny")
        assert(store.defaultPreset.speechEngineID == "whisperkit-tiny", "deleted preset speech engine should fall back to supplied engine")

        let migrationSuiteName = "tingmo.config-preset-migration-tests.\(UUID().uuidString)"
        let migrationDefaults = UserDefaults(suiteName: migrationSuiteName)!
        defer { migrationDefaults.removePersistentDomain(forName: migrationSuiteName) }

        let migratedInstanceID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let legacyConfig = LLMConfig(
            enabled: true,
            provider: .anthropic,
            endpoint: "https://legacy.example.com/messages",
            model: "legacy-claude",
            systemPrompt: "Legacy prompt",
            temperature: 0.7,
            keychainService: "tingmo.llm.legacy"
        )
        let legacyPreset = LegacyPreset(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            name: "Legacy Default",
            llm: legacyConfig
        )
        let legacyPresetData = try! JSONEncoder().encode(legacyPreset)
        migrationDefaults.set(legacyPresetData, forKey: "ConfigPresetStore.defaultPreset")
        migrationDefaults.set("ja", forKey: "LanguagePreference.currentLanguage")
        migrationDefaults.set("remote-groq", forKey: "EngineRegistry.activeEngineID")

        var copiedKey: (value: String, service: String)?
        var deletedLegacyService: String?
        let migratedInstanceStore = LLMInstanceStore(
            defaults: migrationDefaults,
            defaultID: migratedInstanceID,
            getAPIKey: { service in service == legacyConfig.effectiveKeychainService ? "legacy-secret" : nil },
            saveAPIKey: { value, service in
                copiedKey = (value, service)
                return true
            },
            deleteAPIKey: { service in
                deletedLegacyService = service
                return true
            }
        )
        let migratedPresetStore = ConfigPresetStore(
            defaults: migrationDefaults,
            defaultLLMInstanceID: migratedInstanceID
        )

        assert(migratedPresetStore.defaultPreset.name == "Legacy Default", "migration should keep legacy preset name")
        assert(migratedPresetStore.defaultPreset.languageCode == "ja", "migration should move current language into preset")
        assert(migratedPresetStore.defaultPreset.speechEngineID == "remote-groq", "migration should move active engine into preset")
        assert(migratedPresetStore.defaultPreset.llmInstanceID == migratedInstanceID, "migration should point preset at default LLM instance")
        assert(migratedPresetStore.defaultPreset.correctionEnabled, "migration should move correction enabled state")
        assert(migratedPresetStore.defaultPreset.correctionPrompt == "Legacy prompt", "migration should move correction prompt")
        assert(migratedPresetStore.defaultPreset.correctionTemperature == 0.7, "migration should move correction temperature")

        assert(migratedInstanceStore.instances.count == 1, "migration should create one default LLM instance")
        assert(migratedInstanceStore.selectedInstanceID == migratedInstanceID, "migration should select the default LLM instance")
        assert(migratedInstanceStore.instances[0].provider == .anthropic, "migration should move provider into LLM instance")
        assert(migratedInstanceStore.instances[0].endpoint == "https://legacy.example.com/messages", "migration should move endpoint into LLM instance")
        assert(migratedInstanceStore.instances[0].model == "legacy-claude", "migration should move model into LLM instance")
        assert(migratedInstanceStore.instances[0].keychainService == LLMInstance.keychainService(for: migratedInstanceID), "migration should use an instance-scoped keychain service")
        assert(copiedKey?.value == "legacy-secret", "migration should copy legacy keychain value")
        assert(copiedKey?.service == LLMInstance.keychainService(for: migratedInstanceID), "migration should copy key to instance-scoped keychain service")
        assert(deletedLegacyService == "tingmo.llm.legacy", "migration should remove legacy keychain slot after copying")

        print("PASS: ConfigPreset tests")
    }
}
