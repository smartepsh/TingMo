import SwiftUI

/// Settings section for the pre-preset global LLM correction config.
struct LLMSettingsSection: View {
    @Bindable var settings: LLMSettingsStore

    @State private var apiKey: String = ""
    @State private var apiKeySaved = false

    var body: some View {
        Section {
            Toggle(String(localized: "Enable LLM Correction"), isOn: configBinding(\.enabled))

            Picker(String(localized: "Provider"), selection: providerBinding) {
                ForEach(LLMProviderID.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }

            TextField(String(localized: "Endpoint"), text: configBinding(\.endpoint))
                .textFieldStyle(.roundedBorder)
                .textContentType(.URL)

            TextField(String(localized: "Model"), text: configBinding(\.model))
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
                .disabled(!settings.hasAPIKey() && apiKey.isEmpty)

                Spacer()

                keyStatusLabel
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "System Prompt"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: configBinding(\.systemPrompt))
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
                    Text(settings.config.normalizedTemperature, format: .number.precision(.fractionLength(1)))
                        .foregroundStyle(.secondary)
                }
                Slider(value: configBinding(\.temperature), in: 0...2, step: 0.1)
            }
        } header: {
            Text("LLM Correction")
        } footer: {
            Text(footerText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            apiKeySaved = settings.hasAPIKey()
        }
    }

    private var providerBinding: Binding<LLMProviderID> {
        Binding(
            get: { settings.config.provider },
            set: { provider in
                guard settings.config.provider != provider else { return }
                settings.config.provider = provider
                settings.resetProviderDefaults()
                apiKey = ""
                apiKeySaved = settings.hasAPIKey()
            }
        )
    }

    private func configBinding<Value>(_ keyPath: WritableKeyPath<LLMConfig, Value>) -> Binding<Value> {
        Binding(
            get: { settings.config[keyPath: keyPath] },
            set: { settings.config[keyPath: keyPath] = $0 }
        )
    }

    private var keyStatusLabel: some View {
        Group {
            if settings.hasAPIKey() || apiKeySaved {
                Label(String(localized: "Key saved"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if settings.config.usesLocalEndpoint && settings.config.provider == .openAICompatible {
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
        switch settings.config.provider {
        case .openAICompatible:
            String(localized: "Works with OpenAI-compatible chat/completions endpoints, including local services such as Ollama.")
        case .anthropic:
            String(localized: "Anthropic keys are stored in the local Keychain and are never written to presets or UserDefaults.")
        }
    }

    private func saveAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        apiKeySaved = settings.saveAPIKey(trimmed)
        apiKey = ""
    }

    private func clearAPIKey() {
        _ = settings.clearAPIKey()
        apiKey = ""
        apiKeySaved = false
    }
}
