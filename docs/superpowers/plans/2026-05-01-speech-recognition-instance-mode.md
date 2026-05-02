# Speech Recognition Instance Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor Speech Recognition settings to use an instance-based model consistent with Correction, supporting multiple remote STT providers and moving engine selection to Presets.

**Architecture:** Introduce `STTInstance` + `STTProviderID` + `STTInstanceStore` mirroring the existing `LLMInstance` pattern. Remote STT engines become dynamically managed instances instead of statically registered. Engine selection moves from the Speech Recognition page to Preset Settings. WhisperKit local models remain unchanged.

**Tech Stack:** Swift, SwiftUI, macOS, @Observable, EncryptedKeyStore, UserDefaults

---

## File Structure

### New Files
| File | Responsibility |
|---|---|
| `TingMo/SpeechEngine/STTProviderID.swift` | Enum defining remote STT providers (groq, elevenlabs) with metadata |
| `TingMo/SpeechEngine/STTInstance.swift` | Struct representing a configured remote STT connection |
| `TingMo/SpeechEngine/STTInstanceStore.swift` | CRUD store for STT instances with UserDefaults persistence and EncryptedKeyStore API key management |
| `TingMo/SpeechEngine/STTInstanceSettingsSection.swift` | SwiftUI view for managing remote STT instances (add, configure, delete) |

### Modified Files
| File | Changes |
|---|---|
| `TingMo/SpeechEngine/EngineRegistry.swift` | Accept `STTInstanceStore`, dynamically create remote engines from instances, add `refreshRemoteSTTEngines()` |
| `TingMo/SpeechEngine/RemoteSpeechEngine.swift` | Add `init(instance: STTInstance)` convenience initializer |
| `TingMo/SettingsView.swift` | Inject `STTInstanceStore`, replace `RemoteEngineSection` with `STTInstanceSettingsSection` |
| `TingMo/LLMCorrection/LLMSettingsSection.swift` | Add Speech Engine picker + language filter to `PresetSettingsSection` |
| `TingMo/TingMoApp.swift` | Create `STTInstanceStore`, pass to `EngineRegistry` and `SettingsView` |

### Deleted Files
| File | Reason |
|---|---|
| `TingMo/SpeechEngine/EngineSettingsView.swift` | Replaced by engine picker in PresetSettingsSection |
| `TingMo/SpeechEngine/RemoteEngineSection.swift` | Replaced by STTInstanceSettingsSection |

---

### Task 1: STTProviderID Enum

**Files:**
- Create: `TingMo/SpeechEngine/STTProviderID.swift`

- [ ] **Step 1: Create STTProviderID enum**

```swift
import Foundation

enum STTProviderID: String, Codable, CaseIterable, Identifiable {
    case groq
    case elevenlabs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groq: String(localized: "Groq")
        case .elevenlabs: String(localized: "ElevenLabs")
        }
    }

    var defaultInstanceName: String {
        switch self {
        case .groq: String(localized: "Groq Whisper")
        case .elevenlabs: String(localized: "ElevenLabs Scribe")
        }
    }

    var supportedLanguages: [String] {
        switch self {
        case .groq:
            ["en", "zh", "ja", "ko", "de", "fr", "es", "pt", "ru", "it"]
        case .elevenlabs:
            ["en", "zh", "ja", "ko", "de", "fr", "es", "pt", "it", "nl",
             "pl", "ru", "tr", "ar", "hi"]
        }
    }

    func supportsLanguage(_ code: String) -> Bool {
        supportedLanguages.contains(code)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Build the project to confirm no syntax errors.

- [ ] **Step 3: Commit**

```bash
git add TingMo/SpeechEngine/STTProviderID.swift
git commit -m "feat(stt): add STTProviderID enum for remote STT providers"
```

---

### Task 2: STTInstance Struct

**Files:**
- Create: `TingMo/SpeechEngine/STTInstance.swift`

- [ ] **Step 1: Create STTInstance struct**

```swift
import Foundation

struct STTInstance: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var displayName: String
    var provider: STTProviderID
    var keychainService: String

    init(
        id: UUID = UUID(),
        displayName: String? = nil,
        provider: STTProviderID = .groq,
        keychainService: String? = nil
    ) {
        let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        self.id = id
        self.displayName = trimmedName
        self.provider = provider
        self.keychainService = keychainService ?? Self.keychainService(for: id)
    }

    static func keychainService(for id: UUID) -> String {
        "tingmo.stt.instance.\(id.uuidString)"
    }
}
```

- [ ] **Step 2: Verify it compiles**

Build the project.

- [ ] **Step 3: Commit**

```bash
git add TingMo/SpeechEngine/STTInstance.swift
git commit -m "feat(stt): add STTInstance struct for remote STT connections"
```

---

### Task 3: STTInstanceStore

**Files:**
- Create: `TingMo/SpeechEngine/STTInstanceStore.swift`

- [ ] **Step 1: Create STTInstanceStore**

```swift
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
```

- [ ] **Step 2: Verify it compiles**

Build the project.

- [ ] **Step 3: Commit**

```bash
git add TingMo/SpeechEngine/STTInstanceStore.swift
git commit -m "feat(stt): add STTInstanceStore with CRUD and API key management"
```

---

### Task 4: RemoteSpeechEngine Refactor

**Files:**
- Modify: `TingMo/SpeechEngine/RemoteSpeechEngine.swift`

- [ ] **Step 1: Add STTInstance-based convenience initializer**

Add this extension at the end of `RemoteSpeechEngine.swift`:

```swift
extension RemoteSpeechEngine {
    /// Create a RemoteSpeechEngine from an STTInstance.
    /// Builds the appropriate RemoteEngineConfig based on the instance's provider.
    convenience init(instance: STTInstance) {
        let config = Self.config(for: instance.provider, keychainService: instance.keychainService)
        self.init(config: config)
    }

    private static func config(for provider: STTProviderID, keychainService: String) -> RemoteEngineConfig {
        switch provider {
        case .groq:
            RemoteEngineConfig(
                id: "stt-instance-groq",
                name: provider.defaultInstanceName,
                endpoint: "https://api.groq.com/openai/v1/audio/transcriptions",
                modelFieldName: "model",
                modelValue: "whisper-large-v3",
                languageFieldName: "language",
                keychainService: keychainService,
                authStyle: .bearer,
                supportedLanguages: provider.supportedLanguages,
                healthcheckMode: .get(url: "https://api.groq.com/openai/v1/models"),
                billingNote: nil
            )
        case .elevenlabs:
            RemoteEngineConfig(
                id: "stt-instance-elevenlabs",
                name: provider.defaultInstanceName,
                endpoint: "https://api.elevenlabs.io/v1/speech-to-text",
                modelFieldName: "model_id",
                modelValue: "scribe_v1",
                languageFieldName: "language_code",
                keychainService: keychainService,
                authStyle: .xiAPIKey,
                supportedLanguages: provider.supportedLanguages,
                healthcheckMode: .postSTT,
                billingNote: String(localized: "ElevenLabs bills per audio minute. Check your dashboard for usage and rate limits.")
            )
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Build the project. The existing `RemoteSpeechEngine(config:)` init is still available for backward compatibility.

- [ ] **Step 3: Commit**

```bash
git add TingMo/SpeechEngine/RemoteSpeechEngine.swift
git commit -m "feat(stt): add STTInstance-based convenience init to RemoteSpeechEngine"
```

---

### Task 5: EngineRegistry Refactor

**Files:**
- Modify: `TingMo/SpeechEngine/EngineRegistry.swift`

- [ ] **Step 1: Add STTInstanceStore dependency**

Add a stored property and update the init:

```swift
// Add property:
private let sttInstanceStore: STTInstanceStore

// Update init signature:
init(
    downloadSource: DownloadSourcePreference,
    importedModelStore: ImportedModelStore,
    sttInstanceStore: STTInstanceStore
) {
    self.downloadSource = downloadSource
    self.importedModelStore = importedModelStore
    self.sttInstanceStore = sttInstanceStore
    let defaultID = WhisperKitEngine.defaultModelEngineID
    activeEngineID = UserDefaults.standard.string(forKey: "EngineRegistry.activeEngineID") ?? defaultID
    registerBuiltInEngines()
    registerImportedModels()
    preloadActiveEngine()
}
```

- [ ] **Step 2: Refactor registerBuiltInEngines()**

Replace the method to remove static remote engine registration:

```swift
private func registerBuiltInEngines() {
    // WhisperKit models
    for model in WhisperKitEngine.availableModels {
        register(WhisperKitEngine(model: model))
    }

    // Remote engines from STTInstanceStore
    registerRemoteSTTEngines()

    // Parakeet
    register(ParakeetEngine(isReady: false))
}

private func registerRemoteSTTEngines() {
    // Remove existing remote engines
    engines.removeAll { $0 is RemoteSpeechEngine }

    // Create engines from instances
    for instance in sttInstanceStore.instances {
        let engine = RemoteSpeechEngine(instance: instance)
        register(engine)
    }
}
```

- [ ] **Step 3: Add refresh method**

```swift
/// Re-create remote STT engines from the current STTInstanceStore state.
func refreshRemoteSTTEngines() {
    registerRemoteSTTEngines()
    // If the active engine was a remote one that was removed, fall back
    if activeEngine == nil, let fallback = engines.first(where: { $0.info.id == ConfigPreset.defaultSpeechEngineID }) {
        activeEngineID = fallback.info.id
    }
}
```

- [ ] **Step 4: Update refreshRemoteEnginesReadiness()**

This method still needs to work for the connectivity check flow. Update it:

```swift
func refreshRemoteEnginesReadiness() {
    for engine in engines {
        if let remote = engine as? RemoteSpeechEngine {
            remote.refreshReadiness()
        }
    }
    engines = engines
}
```

- [ ] **Step 5: Verify it compiles**

Build. The `TingMoApp.init` will fail because `EngineRegistry` now requires `sttInstanceStore` — that's expected and will be fixed in Task 7.

- [ ] **Step 6: Commit**

```bash
git add TingMo/SpeechEngine/EngineRegistry.swift
git commit -m "feat(stt): refactor EngineRegistry to use STTInstanceStore for dynamic remote engines"
```

---

### Task 6: STTInstanceSettingsSection UI

**Files:**
- Create: `TingMo/SpeechEngine/STTInstanceSettingsSection.swift`

- [ ] **Step 1: Create the view**

```swift
import SwiftUI

struct STTInstanceSettingsSection: View {
    @Bindable var instanceStore: STTInstanceStore
    @Bindable var engineRegistry: EngineRegistry
    @Bindable var presetStore: ConfigPresetStore

    @State private var apiKeys: [UUID: String] = [:]
    @State private var pendingDeleteID: UUID?
    @State private var activeDeleteID: UUID?
    @State private var renamingID: UUID?
    @State private var renameText: String = ""
    @State private var expandedInstanceID: UUID?
    @State private var isTesting: [UUID: Bool] = [:]
    @State private var testResults: [UUID: TestResult] = [:]

    enum TestResult {
        case success
        case failure(String)
    }

    private var activeInstanceID: UUID? {
        let engineID = presetStore.defaultPreset.speechEngineID
        guard engineID.hasPrefix("stt-instance-") else { return nil }
        let uuidString = engineID.replacingOccurrences(of: "stt-instance-", with: "")
        return UUID(uuidString: uuidString)
    }

    var body: some View {
        Section {
            ForEach(instanceStore.instances) { instance in
                DisclosureGroup(isExpanded: expandedBinding(for: instance.id)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker(String(localized: "Provider"), selection: providerBinding(for: instance.id)) {
                            ForEach(STTProviderID.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }

                        SecureField(
                            String(localized: "API Key"),
                            text: apiKeyBinding(for: instance.id),
                            prompt: keyPlaceholder(for: instance)
                        )
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveAPIKey(for: instance.id) }

                        HStack {
                            Button(String(localized: "Save")) {
                                saveAPIKey(for: instance.id)
                            }
                            .disabled((apiKeys[instance.id] ?? "").isEmpty && !instanceStore.hasAPIKey(for: instance))

                            Button(String(localized: "Clear"), role: .destructive) {
                                clearAPIKey(for: instance)
                            }
                            .disabled(!instanceStore.hasAPIKey(for: instance) && (apiKeys[instance.id] ?? "").isEmpty)

                            Spacer()

                            Button {
                                Task { await runTest(for: instance) }
                            } label: {
                                if isTesting[instance.id, default: false] {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text(String(localized: "Test Connection"))
                                }
                            }
                            .disabled(isTesting[instance.id, default: false] || !instanceStore.hasAPIKey(for: instance))
                        }

                        if let result = testResults[instance.id] {
                            switch result {
                            case .success:
                                Label(String(localized: "Connection OK"), systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            case .failure(let message):
                                Label(message, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    HStack(spacing: 6) {
                        Text(instance.displayName.isEmpty ? String(localized: "Untitled") : instance.displayName)
                            .lineLimit(1)
                            .foregroundStyle(instance.displayName.isEmpty ? .secondary : .primary)
                        Button {
                            renameText = instance.displayName
                            renamingID = instance.id
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .popover(isPresented: renameBinding(for: instance.id)) {
                            renamePopover(for: instance)
                        }
                        Spacer()
                        if activeInstanceID == instance.id {
                            Text(String(localized: "Active"))
                                .font(.caption2)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.green.opacity(0.12), in: Capsule())
                        }
                        Text(instance.provider.displayName)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        deleteButton(for: instance)
                    }
                }
            }
        } header: {
            HStack {
                Text("Remote STT Providers")
                Spacer()
                Menu {
                    ForEach(STTProviderID.allCases) { provider in
                        Button(provider.defaultInstanceName) {
                            let instance = instanceStore.addInstance(provider: provider)
                            apiKeys[instance.id] = ""
                            expandedInstanceID = instance.id
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
            }
        } footer: {
            Text(String(localized: "Remote STT providers store reusable API connections. Presets reference these by name."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bindings

    private func expandedBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedInstanceID == id },
            set: { expandedInstanceID = $0 ? id : nil }
        )
    }

    private func renameBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { renamingID == id },
            set: { if !$0 { renamingID = nil } }
        )
    }

    private func providerBinding(for id: UUID) -> Binding<STTProviderID> {
        Binding(
            get: { instanceStore.instance(id: id)?.provider ?? .groq },
            set: { provider in
                guard var instance = instanceStore.instance(id: id) else { return }
                guard instance.provider != provider else { return }
                _ = instanceStore.clearAPIKey(for: instance)
                instance.provider = provider
                let usedDefaultName = instance.displayName == instance.provider.displayName
                    || instance.displayName == ""
                if usedDefaultName {
                    instance.displayName = provider.defaultInstanceName
                }
                instanceStore.upsert(instance)
                apiKeys[id] = ""
                testResults[id] = nil
            }
        )
    }

    private func apiKeyBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { apiKeys[id, default: ""] },
            set: { apiKeys[id] = $0 }
        )
    }

    private func keyPlaceholder(for instance: STTInstance) -> Text {
        if instanceStore.hasAPIKey(for: instance),
           let hint = EncryptedKeyStore.keyHint(service: instance.keychainService) {
            return Text(hint)
        }
        return Text("")
    }

    // MARK: - Actions

    private func saveAPIKey(for id: UUID) {
        guard let instance = instanceStore.instance(id: id) else { return }
        guard instanceStore.saveAPIKey(apiKeys[id, default: ""], for: instance) else { return }
        apiKeys[id] = ""
        engineRegistry.refreshRemoteEnginesReadiness()
    }

    private func clearAPIKey(for instance: STTInstance) {
        _ = instanceStore.clearAPIKey(for: instance)
        apiKeys[instance.id] = nil
        testResults[instance.id] = nil
        engineRegistry.refreshRemoteEnginesReadiness()
    }

    private func runTest(for instance: STTInstance) async {
        isTesting[instance.id] = true
        defer { isTesting[instance.id] = false }

        let engine = RemoteSpeechEngine(instance: instance)
        if let error = await engine.runConnectivityCheck() {
            testResults[instance.id] = .failure(error.localizedDescription)
        } else {
            testResults[instance.id] = .success
        }
    }

    private func commitRename(_ id: UUID) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var instance = instanceStore.instance(id: id) else {
            renamingID = nil
            return
        }
        instance.displayName = trimmed
        instanceStore.upsert(instance)
        renamingID = nil
    }

    @ViewBuilder
    private func renamePopover(for instance: STTInstance) -> some View {
        VStack(spacing: 8) {
            TextField(instance.displayName, text: $renameText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { commitRename(instance.id) }
            HStack {
                Button(String(localized: "Cancel")) {
                    renamingID = nil
                }
                .keyboardShortcut(.cancelAction)
                Button(String(localized: "Rename")) {
                    commitRename(instance.id)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func deleteButton(for instance: STTInstance) -> some View {
        let isActive = activeInstanceID == instance.id
        let isPending = pendingDeleteID == instance.id
        Button {
            if isActive {
                activeDeleteID = instance.id
            } else if isPending {
                deleteInstance(instance.id)
            } else {
                pendingDeleteID = instance.id
            }
        } label: {
            Image(systemName: "trash")
                .foregroundStyle(isPending ? .red : .secondary)
        }
        .buttonStyle(.borderless)
        .confirmationDialog(
            String(localized: "Delete this provider?"),
            isPresented: Binding(
                get: { activeDeleteID == instance.id },
                set: { if !$0 { activeDeleteID = nil } }
            ),
            presenting: instance
        ) { _ in
            Button(String(localized: "Delete"), role: .destructive) {
                deleteInstance(instance.id)
            }
        } message: { _ in
            Text(String(localized: "This provider is active in your preset. Deleting it will reset the Speech Engine."))
        }
        .onHover { inside in
            if !inside && isPending {
                pendingDeleteID = nil
            }
        }
    }

    private func deleteInstance(_ id: UUID) {
        let instanceID = "stt-instance-\(id.uuidString)"
        guard instanceStore.deleteInstance(id: id) else { return }
        presetStore.replaceSpeechEngineSelection(
            deletedID: instanceID,
            fallbackID: ConfigPreset.defaultSpeechEngineID
        )
        apiKeys[id] = nil
        testResults[id] = nil
        pendingDeleteID = nil
        engineRegistry.refreshRemoteSTTEngines()
    }
}
```

- [ ] **Step 2: Verify it compiles**

Build the project. It may show warnings about missing `sttInstanceStore` in `SettingsView` — that's expected.

- [ ] **Step 3: Commit**

```bash
git add TingMo/SpeechEngine/STTInstanceSettingsSection.swift
git commit -m "feat(stt): add STTInstanceSettingsSection UI for managing remote STT providers"
```

---

### Task 7: App Wiring + SettingsView Update

**Files:**
- Modify: `TingMo/TingMoApp.swift`
- Modify: `TingMo/SettingsView.swift`

- [ ] **Step 1: Update TingMoApp.swift**

In `TingMoApp.init()`, add `sttInstanceStore` creation and pass it to `EngineRegistry`:

```swift
init() {
    let permissionManager = PermissionManager()
    let audioDeviceManager = AudioDeviceManager()
    let hotkeyManager = HotkeyManager()
    let statusIndicatorManager = StatusIndicatorManager()
    let downloadSource = DownloadSourcePreference()
    let importedStore = ImportedModelStore()
    let defaultLLMInstanceID = UUID()
    let llmInstanceStore = LLMInstanceStore(defaultID: defaultLLMInstanceID)
    let sttInstanceStore = STTInstanceStore()  // NEW
    let presetStore = ConfigPresetStore(defaultLLMInstanceID: defaultLLMInstanceID)
    let contextSettings = ContextSettingsStore()
    let registry = EngineRegistry(
        downloadSource: downloadSource,
        importedModelStore: importedStore,
        sttInstanceStore: sttInstanceStore  // NEW
    )
    let languagePreference = LanguagePreference()
    _permissionManager = State(initialValue: permissionManager)
    _audioDeviceManager = State(initialValue: audioDeviceManager)
    _hotkeyManager = State(initialValue: hotkeyManager)
    _engineRegistry = State(initialValue: registry)
    _statusIndicatorManager = State(initialValue: statusIndicatorManager)
    _languagePreference = State(initialValue: languagePreference)
    _downloadSource = State(initialValue: downloadSource)
    _importedModelStore = State(initialValue: importedStore)
    _presetStore = State(initialValue: presetStore)
    _llmInstanceStore = State(initialValue: llmInstanceStore)
    _sttInstanceStore = State(initialValue: sttInstanceStore)  // NEW
    _contextSettings = State(initialValue: contextSettings)
    _pipeline = State(initialValue: DictationPipeline(
        registry: registry,
        languagePreference: languagePreference,
        presetStore: presetStore,
        llmInstanceStore: llmInstanceStore,
        contextSettings: contextSettings
    ))
}
```

Add the `@State` property:

```swift
@State private var sttInstanceStore: STTInstanceStore
```

- [ ] **Step 2: Update SettingsView.swift**

Add `sttInstanceStore` property:

```swift
@Bindable var sttInstanceStore: STTInstanceStore
```

Replace the `.speech` case in `selectedPageContent`:

```swift
case .speech:
    ModelDownloadView(
        engineRegistry: engineRegistry,
        downloadSource: downloadSource,
        presetStore: presetStore
    )

    ImportedModelSection(
        engineRegistry: engineRegistry,
        importedModelStore: importedModelStore,
        presetStore: presetStore
    )

    STTInstanceSettingsSection(
        instanceStore: sttInstanceStore,
        engineRegistry: engineRegistry,
        presetStore: presetStore
    )
```

Remove the `remoteEngines` computed property:

```swift
// DELETE this:
private var remoteEngines: [RemoteSpeechEngine] {
    engineRegistry.engines.compactMap { $0 as? RemoteSpeechEngine }
}
```

- [ ] **Step 3: Update SettingsView init call in TingMoApp**

Pass `sttInstanceStore` to `SettingsView`:

```swift
SettingsView(
    permissionManager: permissionManager,
    audioDeviceManager: audioDeviceManager,
    hotkeyManager: hotkeyManager,
    statusIndicatorManager: statusIndicatorManager,
    engineRegistry: engineRegistry,
    languagePreference: languagePreference,
    downloadSource: downloadSource,
    importedModelStore: importedModelStore,
    presetStore: presetStore,
    llmInstanceStore: llmInstanceStore,
    sttInstanceStore: sttInstanceStore,  // NEW
    contextSettings: contextSettings
)
```

- [ ] **Step 4: Remove EngineSettingsView import**

In `SettingsView.swift`, the old `EngineSettingsView` is no longer used in the `.speech` case. The import is automatic (same module), so no explicit import removal needed. Verify the build succeeds without `EngineSettingsView` references.

- [ ] **Step 5: Verify it compiles and runs**

Build and run. The Speech Recognition page should now show WhisperKit models + STTInstanceSettingsSection. The old EngineSettingsView and RemoteEngineSection are no longer referenced.

- [ ] **Step 6: Commit**

```bash
git add TingMo/TingMoApp.swift TingMo/SettingsView.swift
git commit -m "feat(stt): wire STTInstanceStore into app and update Speech Recognition page"
```

---

### Task 8: PresetSettingsSection — Speech Engine Picker + Language Filter

**Files:**
- Modify: `TingMo/LLMCorrection/LLMSettingsSection.swift`

- [ ] **Step 1: Add STTInstanceStore dependency to PresetSettingsSection**

Add the property:

```swift
@Bindable var sttInstanceStore: STTInstanceStore
@Bindable var engineRegistry: EngineRegistry
```

- [ ] **Step 2: Add language filter state**

Add at the top of the view body or as a property:

```swift
@State private var filterLanguages: Set<String> = []
```

- [ ] **Step 3: Add Speech Engine picker and language filter to the body**

Insert before the "Output Language" picker in the `Section` body:

```swift
// Language filter (UI only)
VStack(alignment: .leading, spacing: 4) {
    Text(String(localized: "Filter by language"))
        .font(.caption)
        .foregroundStyle(.secondary)
    HStack(spacing: 12) {
        ForEach(LanguagePreference.availableLanguages) { lang in
            Toggle(lang.name, isOn: filterBinding(for: lang.code))
                .font(.caption)
        }
    }
}

// Speech Engine picker
Picker(String(localized: "Speech Engine"), selection: speechEngineBinding) {
    Text(String(localized: "None")).tag("" as String)

    // WhisperKit Models
    ForEach(whisperKitEngines, id: \.info.id) { engine in
        Text("\(engine.info.name) — \(engine.info.modelSize ?? "")")
            .tag(engine.info.id as String)
    }

    // Remote STT Instances
    if !filteredSTTInstances.isEmpty {
        Divider()
        ForEach(filteredSTTInstances) { instance in
            Text("\(instance.displayName) (\(instance.provider.displayName))")
                .tag("stt-instance-\(instance.id.uuidString)" as String)
        }
    }
}
.onAppear {
    validateSpeechEngineSelection()
}
```

- [ ] **Step 4: Add computed properties and helper methods**

```swift
private var whisperKitEngines: [any SpeechEngine] {
    engineRegistry.engines.filter { engine in
        guard engine is WhisperKitEngine else { return false }
        if filterLanguages.isEmpty { return true }
        return filterLanguages.allSatisfy { engine.supportsLanguage($0) }
    }
    .sorted { ($0.info.modelSize ?? "") < ($1.info.modelSize ?? "") }
}

private var filteredSTTInstances: [STTInstance] {
    if filterLanguages.isEmpty { return sttInstanceStore.instances }
    return sttInstanceStore.instances.filter { instance in
        filterLanguages.allSatisfy { instance.provider.supportsLanguage($0) }
    }
}

private var speechEngineBinding: Binding<String> {
    Binding(
        get: { presetStore.defaultPreset.speechEngineID },
        set: { newValue in
            presetStore.defaultPreset.speechEngineID = newValue
            engineRegistry.setActiveEngine(newValue)
        }
    )
}

private func filterBinding(for code: String) -> Binding<Bool> {
    Binding(
        get: { filterLanguages.contains(code) },
        set: { isSelected in
            if isSelected {
                filterLanguages.insert(code)
            } else {
                filterLanguages.remove(code)
            }
        }
    )
}

private func validateSpeechEngineSelection() {
    let currentID = presetStore.defaultPreset.speechEngineID
    if currentID.hasPrefix("stt-instance-") {
        let uuidString = currentID.replacingOccurrences(of: "stt-instance-", with: "")
        if let uuid = UUID(uuidString: uuidString),
           sttInstanceStore.instance(id: uuid) == nil {
            presetStore.defaultPreset.speechEngineID = ConfigPreset.defaultSpeechEngineID
        }
    }
}
```

- [ ] **Step 5: Update all call sites of PresetSettingsSection**

In `SettingsView.swift`, update the `.presets` case to pass the new dependencies:

```swift
case .presets:
    PresetSettingsSection(
        presetStore: presetStore,
        instanceStore: llmInstanceStore,
        sttInstanceStore: sttInstanceStore,
        engineRegistry: engineRegistry
    )
```

- [ ] **Step 5: Verify it compiles and runs**

Build and run. The Preset Settings page should now show:
- Speech Engine picker with grouped WhisperKit + Remote providers
- Language filter (UI only)
- Existing Output Language and Correction settings

- [ ] **Step 6: Commit**

```bash
git add TingMo/LLMCorrection/LLMSettingsSection.swift TingMo/SettingsView.swift
git commit -m "feat(stt): add Speech Engine picker and language filter to Preset settings"
```

---

### Task 9: Cleanup

**Files:**
- Delete: `TingMo/SpeechEngine/EngineSettingsView.swift`
- Delete: `TingMo/SpeechEngine/RemoteEngineSection.swift`

- [ ] **Step 1: Delete EngineSettingsView.swift**

This file is no longer referenced. Delete it.

- [ ] **Step 2: Delete RemoteEngineSection.swift**

This file is no longer referenced. Delete it.

- [ ] **Step 3: Remove old static remote engine configs**

In `RemoteSpeechEngine.swift`, the static `.groq` and `.elevenlabs` configs on `RemoteEngineConfig` are no longer needed by `EngineRegistry` (engines are now created from `STTInstance` instances). However, they may still be useful as reference. Keep them for now — they don't cause harm.

- [ ] **Step 4: Verify full build**

Build and run the entire project. Verify:
- Speech Recognition page shows WhisperKit models + remote STT instances
- Preset Settings page has Speech Engine picker with language filter
- Adding a remote STT instance, configuring API key, and testing works
- Selecting an engine in Preset updates the active engine
- Deleting an instance that's in use shows a warning

- [ ] **Step 5: Commit**

```bash
git rm TingMo/SpeechEngine/EngineSettingsView.swift TingMo/SpeechEngine/RemoteEngineSection.swift
git commit -m "chore: remove old EngineSettingsView and RemoteEngineSection"
```

---

## Verification Checklist

After completing all tasks, verify these user flows:

1. **WhisperKit model management:** Download, delete, see Preset reference
2. **Remote STT instance:** Add instance → configure API key → test connection → select in Preset
3. **Multi-instance:** Add two Groq instances with different API keys
4. **Language filter:** Select languages in Preset → engine list filters correctly
5. **Delete protection:** Delete active instance → warning dialog → Preset resets to default
6. **Menu bar:** Recognition Engine menu still works with new engine IDs
