import SwiftUI

struct PresetSettingsSection: View {
    @Bindable var presetStore: ConfigPresetStore

    @State private var apiKey: String = ""
    @State private var apiKeySaved = false

    var body: some View {
        Section {
            TextField(String(localized: "Preset Name"), text: presetBinding(\.name))
                .textFieldStyle(.roundedBorder)

            Toggle(String(localized: "Enable LLM Correction"), isOn: llmBinding(\.enabled))

            Picker(String(localized: "Provider"), selection: providerBinding) {
                ForEach(LLMProviderID.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }

            TextField(String(localized: "Endpoint"), text: llmBinding(\.endpoint))
                .textFieldStyle(.roundedBorder)
                .textContentType(.URL)

            TextField(String(localized: "Model"), text: llmBinding(\.model))
                .textFieldStyle(.roundedBorder)

            SecureField(String(localized: "API Key"), text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .onSubmit { saveAPIKey() }

            HStack {
                Button(String(localized: "Save Key")) {
                    saveAPIKey()
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(String(localized: "Clear Key"), role: .destructive) {
                    clearAPIKey()
                }
                .disabled(!presetStore.hasAPIKey() && apiKey.isEmpty)

                Spacer()

                keyStatusLabel
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "System Prompt"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: llmBinding(\.systemPrompt))
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
                    Text(presetStore.defaultPreset.llm.normalizedTemperature, format: .number.precision(.fractionLength(1)))
                        .foregroundStyle(.secondary)
                }
                Slider(value: llmBinding(\.temperature), in: 0...2, step: 0.1)
            }

            Toggle(String(localized: "Enable Knowledge Base"), isOn: presetBinding(\.knowledgeBaseEnabled))
        } header: {
            Text("Default Preset")
        } footer: {
            Text(footerText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            apiKeySaved = presetStore.hasAPIKey()
        }
    }

    private var providerBinding: Binding<LLMProviderID> {
        Binding(
            get: { presetStore.defaultPreset.llm.provider },
            set: { provider in
                guard presetStore.defaultPreset.llm.provider != provider else { return }
                presetStore.defaultPreset.llm.provider = provider
                presetStore.resetProviderDefaults()
                apiKey = ""
                apiKeySaved = presetStore.hasAPIKey()
            }
        )
    }

    private func llmBinding<Value>(_ keyPath: WritableKeyPath<LLMConfig, Value>) -> Binding<Value> {
        Binding(
            get: { presetStore.defaultPreset.llm[keyPath: keyPath] },
            set: { presetStore.defaultPreset.llm[keyPath: keyPath] = $0 }
        )
    }

    private func presetBinding<Value>(_ keyPath: WritableKeyPath<ConfigPreset, Value>) -> Binding<Value> {
        Binding(
            get: { presetStore.defaultPreset[keyPath: keyPath] },
            set: { presetStore.defaultPreset[keyPath: keyPath] = $0 }
        )
    }

    private var keyStatusLabel: some View {
        Group {
            if presetStore.hasAPIKey() || apiKeySaved {
                Label(String(localized: "Key saved"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if presetStore.defaultPreset.llm.usesLocalEndpoint && presetStore.defaultPreset.llm.provider == .openAICompatible {
                Label(String(localized: "Key optional"), systemImage: "network")
                    .foregroundStyle(.secondary)
            } else {
                Label(String(localized: "No key"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
    }

    private var footerText: String {
        switch presetStore.defaultPreset.llm.provider {
        case .openAICompatible:
            String(localized: "The default preset stores LLM configuration and the knowledge-base switch. Speech engine, model, language, and device settings stay independent.")
        case .anthropic:
            String(localized: "API keys are stored in the local Keychain by reference and are never written to presets or UserDefaults.")
        }
    }

    private func saveAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        apiKeySaved = presetStore.saveAPIKey(trimmed)
        apiKey = ""
    }

    private func clearAPIKey() {
        _ = presetStore.clearAPIKey()
        apiKey = ""
        apiKeySaved = false
    }
}
