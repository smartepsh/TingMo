# M6-1 LLM Instance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add reusable LLM Instance data and storage so Settings can manage multiple correction engine connection profiles without storing API key values in Codable config.

**Architecture:** Introduce a Foundation-only `LLMInstance` model and `LLMInstanceStore` next to the existing LLM correction code. Keep API keys in macOS Keychain by stable instance-scoped service names. For M6-1, Settings exposes basic management of the default instance list while existing Preset code can continue using `LLMConfig` until M6-2 connects Presets to instances.

**Tech Stack:** Swift, SwiftUI, Observation, UserDefaults JSON persistence, macOS Keychain via Security framework, standalone Swift script tests.

---

## File Structure

- Create `TingMo/LLMCorrection/LLMInstance.swift`: `LLMInstance` model plus effective endpoint/model helpers.
- Create `TingMo/LLMCorrection/LLMInstanceStore.swift`: observable store, JSON persistence, legacy default instance creation, key save/clear/status helpers.
- Modify `TingMo/LLMCorrection/LLMSettingsSection.swift`: replace the current single embedded LLM UI with an `LLMInstanceSettingsSection` for instance management while leaving Preset prompt/temperature behavior intact for later tasks.
- Modify `TingMo/SettingsView.swift`: pass the new store into Settings.
- Modify `TingMo/TingMoApp.swift`: own one `LLMInstanceStore` state object.
- Create `scripts/test_llm_instances.swift`: standalone test runner for model/store persistence and keychain service behavior.

## Task 1: Add Model And Store With TDD

**Files:**
- Create: `scripts/test_llm_instances.swift`
- Create: `TingMo/LLMCorrection/LLMInstance.swift`
- Create: `TingMo/LLMCorrection/LLMInstanceStore.swift`

- [ ] **Step 1: Write the failing test**

Create `scripts/test_llm_instances.swift` with these checks:

```swift
import Foundation

func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

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

print("PASS: LLMInstance tests")
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift TingMo/LLMCorrection/LLMProvider.swift scripts/test_llm_instances.swift
```

Expected: FAIL to compile because `LLMInstance` and `LLMInstanceStore` do not exist.

- [ ] **Step 3: Implement minimal model and store**

Create `TingMo/LLMCorrection/LLMInstance.swift`:

```swift
import Foundation

struct LLMInstance: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var displayName: String
    var provider: LLMProviderID
    var endpoint: String
    var model: String
    var keychainService: String

    init(
        id: UUID = UUID(),
        displayName: String? = nil,
        provider: LLMProviderID = .openAICompatible,
        endpoint: String? = nil,
        model: String? = nil,
        keychainService: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? displayName!.trimmingCharacters(in: .whitespacesAndNewlines)
            : provider.displayName
        self.endpoint = endpoint ?? provider.defaultEndpoint
        self.model = model ?? provider.defaultModel
        self.keychainService = keychainService ?? Self.keychainService(for: id)
    }

    var effectiveEndpoint: String {
        endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? provider.defaultEndpoint
            : endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var effectiveModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? provider.defaultModel
            : model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func defaultInstance(id: UUID = UUID()) -> LLMInstance {
        LLMInstance(id: id)
    }

    static func keychainService(for id: UUID) -> String {
        "tingmo.llm.instance.\(id.uuidString)"
    }
}
```

Create `TingMo/LLMCorrection/LLMInstanceStore.swift`:

```swift
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

    var instances: [LLMInstance] {
        didSet { save() }
    }

    var selectedInstanceID: UUID {
        didSet { save() }
    }

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = LLMInstanceStore.storageKey,
        defaultID: UUID = UUID()
    ) {
        self.defaults = defaults
        self.storageKey = storageKey

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

    func upsert(_ instance: LLMInstance) {
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[index] = instance
        } else {
            instances.append(instance)
        }
    }

    private func save() {
        let state = StoredState(instances: instances, selectedInstanceID: selectedInstanceID)
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swift TingMo/LLMCorrection/LLMProvider.swift TingMo/LLMCorrection/LLMInstance.swift TingMo/LLMCorrection/LLMInstanceStore.swift scripts/test_llm_instances.swift
```

Expected: `PASS: LLMInstance tests`.

## Task 2: Add Keychain Helpers To Store

**Files:**
- Modify: `scripts/test_llm_instances.swift`
- Modify: `TingMo/LLMCorrection/LLMInstanceStore.swift`

- [ ] **Step 1: Write failing key status test**

Add a test seam closure to the expected API by appending this to the script before the final print:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run the same `swift ...` command.

Expected: FAIL to compile because injected keychain closures and helper methods do not exist.

- [ ] **Step 3: Implement keychain helper API**

Add closure properties to `LLMInstanceStore` initializer and methods:

```swift
private let getAPIKey: (String) -> String?
private let saveAPIKeyValue: (String, String) -> Bool
private let deleteAPIKey: (String) -> Bool

init(
    defaults: UserDefaults = .standard,
    storageKey: String = LLMInstanceStore.storageKey,
    defaultID: UUID = UUID(),
    getAPIKey: @escaping (String) -> String? = { KeychainStore.get(service: $0) },
    saveAPIKey: @escaping (String, String) -> Bool = { KeychainStore.set($0, for: $1) },
    deleteAPIKey: @escaping (String) -> Bool = { KeychainStore.delete(service: $0) }
) {
    self.defaults = defaults
    self.storageKey = storageKey
    self.getAPIKey = getAPIKey
    self.saveAPIKeyValue = saveAPIKey
    self.deleteAPIKey = deleteAPIKey
    ...
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
```

- [ ] **Step 4: Run test to verify it passes**

Run the same `swift ...` command.

Expected: `PASS: LLMInstance tests`.

## Task 3: Integrate Store Into Settings

**Files:**
- Modify: `TingMo/TingMoApp.swift`
- Modify: `TingMo/SettingsView.swift`
- Modify: `TingMo/LLMCorrection/LLMSettingsSection.swift`

- [ ] **Step 1: Add app/store wiring**

Add `@State private var llmInstanceStore = LLMInstanceStore()` to `TingMoApp`, and pass it into `SettingsView`.

- [ ] **Step 2: Add SettingsView binding**

Add `@Bindable var llmInstanceStore: LLMInstanceStore` to `SettingsView` and pass it to the LLM section.

- [ ] **Step 3: Replace LLM settings section with basic instance management**

Rename the section to `LLMInstanceSettingsSection`. It should show each instance with editable name/provider/endpoint/model fields, save/clear key controls, and current key status. Keep a minimal `Add Instance` button for multiple-instance support.

- [ ] **Step 4: Build verify**

Run:

```bash
xcodebuild -project "TingMo.xcodeproj" -scheme "TingMo" -configuration Debug build
```

Expected: `** BUILD SUCCEEDED **`.

## Self-Review

- Spec coverage: M6-1 covers reusable LLM Instance model, multiple instances, independent Keychain slots, local-only key policy, and Settings management. Preset ownership and menu bar changes are intentionally left for M6-2/M6-5.
- Placeholder scan: no placeholder tasks remain.
- Type consistency: `LLMInstance`, `LLMInstanceStore`, `LLMProviderID`, and `KeychainStore` names match existing code and planned files.
