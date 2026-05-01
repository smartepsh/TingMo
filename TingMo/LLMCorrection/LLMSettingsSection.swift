import SwiftUI

struct PresetSettingsSection: View {
    @Bindable var presetStore: ConfigPresetStore
    @Bindable var instanceStore: LLMInstanceStore
    @Bindable var sttInstanceStore: STTInstanceStore
    @Bindable var engineRegistry: EngineRegistry
    @State private var filterLanguages: Set<String> = []

    var body: some View {
        Section {
            TextField(String(localized: "Preset Name"), text: presetBinding(\.name))
                .textFieldStyle(.roundedBorder)

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

            Picker(String(localized: "Output Language"), selection: outputLanguageBinding) {
                Text(String(localized: "Raw (原始值)")).tag(ConfigPreset.rawOutputLanguage)
                ForEach(LanguagePreference.availableLanguages) { lang in
                    Text(lang.name).tag(lang.code)
                }
            }

            Toggle(String(localized: "Enable LLM Correction"), isOn: presetBinding(\.correctionEnabled))

            Picker(String(localized: "Correction Engine"), selection: llmInstanceBinding) {
                Text(String(localized: "None")).tag(UUID?.none)
                ForEach(instanceStore.instances) { instance in
                    Text(instance.displayName).tag(Optional(instance.id))
                }
            }
            .onAppear {
                validateLLMInstanceSelection()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "System Prompt"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: presetBinding(\.correctionPrompt))
                    .font(.body)
                    .frame(minHeight: 90)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary)
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(String(localized: "Temperature"))
                    Spacer()
                    Text(normalizedCorrectionTemperature, format: .number.precision(.fractionLength(1)))
                        .foregroundStyle(.secondary)
                }
                Slider(value: presetBinding(\.correctionTemperature), in: 0...2, step: 0.1)
            }
        } header: {
            Text("Default Preset")
        } footer: {
            Text(footerText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func validateLLMInstanceSelection() {
        if let id = presetStore.defaultPreset.llmInstanceID,
           !instanceStore.instances.contains(where: { $0.id == id }) {
            presetStore.defaultPreset.llmInstanceID = nil
        }
    }

    private var whisperKitEngines: [any SpeechEngine] {
        engineRegistry.engines.filter { engine in
            guard engine is WhisperKitEngine else { return false }
            if filterLanguages.isEmpty { return true }
            return filterLanguages.allSatisfy { engine.supportsLanguage($0) }
        }
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

    private func presetBinding<Value>(_ keyPath: WritableKeyPath<ConfigPreset, Value>) -> Binding<Value> {
        Binding(
            get: { presetStore.defaultPreset[keyPath: keyPath] },
            set: { presetStore.defaultPreset[keyPath: keyPath] = $0 }
        )
    }

    private var llmInstanceBinding: Binding<UUID?> {
        Binding(
            get: { presetStore.defaultPreset.llmInstanceID },
            set: { presetStore.defaultPreset.llmInstanceID = $0 }
        )
    }

    private var outputLanguageBinding: Binding<String> {
        Binding(
            get: { presetStore.defaultPreset.outputLanguage },
            set: { presetStore.defaultPreset.outputLanguage = $0 }
        )
    }

    private var footerText: String {
        String(localized: "The default preset stores correction behavior and the selected correction model. API keys, endpoints, and models are managed in Correction.")
    }

    private var normalizedCorrectionTemperature: Double {
        min(max(presetStore.defaultPreset.correctionTemperature, 0), 2)
    }
}

struct LLMInstanceSettingsSection: View {
    @Bindable var instanceStore: LLMInstanceStore
    @Bindable var presetStore: ConfigPresetStore

    @State private var apiKeys: [UUID: String] = [:]
    @State private var pendingDeleteID: UUID?
    @State private var activeDeleteID: UUID?
    @State private var renamingID: UUID?
    @State private var renameText: String = ""
    @State private var expandedInstanceID: UUID?

    var body: some View {
        Section {
            ForEach(instanceStore.instances) { instance in
                DisclosureGroup(isExpanded: expandedBinding(for: instance.id)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker(String(localized: "Provider"), selection: providerBinding(for: instance.id)) {
                            ForEach(LLMProviderID.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }

                        TextField(String(localized: "Base URL"), text: textBinding(for: instance.id, \.endpoint))
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.URL)

                        TextField(String(localized: "Model"), text: textBinding(for: instance.id, \.model))
                            .textFieldStyle(.roundedBorder)

                        SecureField(
                            String(localized: "API Key"),
                            text: apiKeyBinding(for: instance.id),
                            prompt: keyPlaceholder(for: instance)
                        )
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveAPIKey(for: instance.id) }
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
                        if presetStore.defaultPreset.llmInstanceID == instance.id {
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
                Text("Correction Models")
                Spacer()
                Button {
                    let instance = instanceStore.addInstance()
                    apiKeys[instance.id] = ""
                    expandedInstanceID = instance.id
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
        } footer: {
            Text(String(localized: "Correction models store reusable LLM connections. API keys are stored locally with encryption; presets reference these models by name."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

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

    @ViewBuilder
    private func renamePopover(for instance: LLMInstance) -> some View {
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
    private func deleteButton(for instance: LLMInstance) -> some View {
        let isActive = presetStore.defaultPreset.llmInstanceID == instance.id
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
            String(localized: "Delete this model?"),
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
            Text(String(localized: "This model is active in your preset. Deleting it will set the Correction Engine to None."))
        }
        .onHover { inside in
            if !inside && isPending {
                pendingDeleteID = nil
            }
        }
    }

    private func textBinding(for id: UUID, _ keyPath: WritableKeyPath<LLMInstance, String>) -> Binding<String> {
        Binding(
            get: { instanceStore.instance(id: id)?[keyPath: keyPath] ?? "" },
            set: { value in
                guard var instance = instanceStore.instance(id: id) else { return }
                instance[keyPath: keyPath] = value
                instanceStore.upsert(instance)
            }
        )
    }

    private func providerBinding(for id: UUID) -> Binding<LLMProviderID> {
        Binding(
            get: { instanceStore.instance(id: id)?.provider ?? .openAICompatible },
            set: { provider in
                guard instanceStore.updateProvider(for: id, provider: provider) else { return }
                apiKeys[id] = ""
            }
        )
    }

    private func apiKeyBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { apiKeys[id, default: ""] },
            set: { apiKeys[id] = $0 }
        )
    }

    private func keyPlaceholder(for instance: LLMInstance) -> Text {
        if instanceStore.hasAPIKey(for: instance),
           let hint = EncryptedKeyStore.keyHint(service: instance.keychainService) {
            return Text(hint)
        }
        return Text("")
    }

    private func saveAPIKey(for id: UUID) {
        guard let instance = instanceStore.instance(id: id) else { return }
        guard instanceStore.saveAPIKey(apiKeys[id, default: ""], for: instance) else { return }
        apiKeys[id] = ""
    }

    private func deleteInstance(_ id: UUID) {
        guard instanceStore.deleteInstance(id: id) else { return }
        presetStore.replaceLLMInstanceSelection(
            deletedID: id,
            fallbackID: instanceStore.instances.first?.id
        )
        apiKeys[id] = nil
        pendingDeleteID = nil
    }
}
