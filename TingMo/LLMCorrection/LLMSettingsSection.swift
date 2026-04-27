import SwiftUI

struct PresetSettingsSection: View {
    @Bindable var presetStore: ConfigPresetStore
    @Bindable var instanceStore: LLMInstanceStore

    var body: some View {
        Section {
            TextField(String(localized: "Preset Name"), text: presetBinding(\.name))
                .textFieldStyle(.roundedBorder)

            Toggle(String(localized: "Enable LLM Correction"), isOn: presetBinding(\.correctionEnabled))

            Picker(String(localized: "Correction Engine"), selection: llmInstanceBinding) {
                Text(String(localized: "None")).tag(UUID?.none)
                ForEach(instanceStore.instances) { instance in
                    Text(instance.displayName).tag(Optional(instance.id))
                }
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

    private var footerText: String {
        String(localized: "The default preset stores correction behavior and the selected LLM instance. API keys, endpoints, and models are managed in LLM Instances.")
    }

    private var normalizedCorrectionTemperature: Double {
        min(max(presetStore.defaultPreset.correctionTemperature, 0), 2)
    }
}

struct LLMInstanceSettingsSection: View {
    @Bindable var instanceStore: LLMInstanceStore
    @Bindable var presetStore: ConfigPresetStore

    @State private var apiKeys: [UUID: String] = [:]
    @State private var savedKeyIDs: Set<UUID> = []

    var body: some View {
        Section {
            ForEach(instanceStore.instances) { instance in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(String(localized: "Name"), text: textBinding(for: instance.id, \.displayName))
                            .textFieldStyle(.roundedBorder)

                        Picker(String(localized: "Provider"), selection: providerBinding(for: instance.id)) {
                            ForEach(LLMProviderID.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }

                        TextField(String(localized: "Endpoint"), text: textBinding(for: instance.id, \.endpoint))
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.URL)

                        TextField(String(localized: "Model"), text: textBinding(for: instance.id, \.model))
                            .textFieldStyle(.roundedBorder)

                        SecureField(String(localized: "API Key"), text: apiKeyBinding(for: instance.id))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { saveAPIKey(for: instance.id) }

                        HStack {
                            Button(String(localized: "Save Key")) {
                                saveAPIKey(for: instance.id)
                            }
                            .disabled(apiKeys[instance.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button(String(localized: "Clear Key"), role: .destructive) {
                                clearAPIKey(for: instance.id)
                            }
                            .disabled(!instanceStore.hasAPIKey(for: instance) && apiKeys[instance.id, default: ""].isEmpty)

                            Spacer()

                            keyStatusLabel(for: instance)
                        }

                        Button(String(localized: "Delete Instance"), role: .destructive) {
                            deleteInstance(instance.id)
                        }
                        .disabled(instanceStore.instances.count == 1)
                    }
                    .padding(.vertical, 4)
                } label: {
                    HStack {
                        Text(instance.displayName)
                        Spacer()
                        Text(instance.provider.displayName)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button(String(localized: "Add LLM Instance")) {
                let instance = instanceStore.addInstance()
                apiKeys[instance.id] = ""
            }
        } header: {
            Text("LLM Instances")
        } footer: {
            Text(String(localized: "Instances store reusable correction engine connections. API keys stay in the local macOS Keychain; presets and settings store only references."))
                .font(.caption)
                .foregroundStyle(.secondary)
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
                savedKeyIDs.remove(id)
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

    private func keyStatusLabel(for instance: LLMInstance) -> some View {
        Group {
            if instanceStore.hasAPIKey(for: instance) || savedKeyIDs.contains(instance.id) {
                Label(String(localized: "Key saved"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label(String(localized: "No key"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
    }

    private func saveAPIKey(for id: UUID) {
        guard let instance = instanceStore.instance(id: id) else { return }
        guard instanceStore.saveAPIKey(apiKeys[id, default: ""], for: instance) else { return }
        apiKeys[id] = ""
        savedKeyIDs.insert(id)
    }

    private func clearAPIKey(for id: UUID) {
        guard let instance = instanceStore.instance(id: id) else { return }
        _ = instanceStore.clearAPIKey(for: instance)
        apiKeys[id] = ""
        savedKeyIDs.remove(id)
    }

    private func deleteInstance(_ id: UUID) {
        guard instanceStore.deleteInstance(id: id) else { return }
        presetStore.replaceLLMInstanceSelection(
            deletedID: id,
            fallbackID: instanceStore.instances.first?.id
        )
        apiKeys[id] = nil
        savedKeyIDs.remove(id)
    }
}
