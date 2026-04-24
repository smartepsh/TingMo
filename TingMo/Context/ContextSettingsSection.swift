import SwiftUI

struct ContextSettingsSection: View {
    @Bindable var settings: ContextSettingsStore

    var body: some View {
        Section {
            ForEach(settings.sources) { source in
                HStack {
                    Toggle(source.kind.displayName, isOn: sourceEnabledBinding(for: source.kind))
                    Spacer()
                    Stepper(
                        value: sourcePriorityBinding(for: source.kind),
                        in: 1...99,
                        step: 1
                    ) {
                        Text(String(localized: "Priority \(settings.config(for: source.kind).priority)"))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 150)
                }
            }

            Stepper(
                value: $settings.maxCharactersPerItem,
                in: 200...4_000,
                step: 100
            ) {
                Text(String(localized: "Per-item limit: \(settings.maxCharactersPerItem) chars"))
            }

            Stepper(
                value: $settings.maxTotalCharacters,
                in: 500...12_000,
                step: 500
            ) {
                Text(String(localized: "Total limit: \(settings.maxTotalCharacters) chars"))
            }
        } header: {
            Text("Context")
        } footer: {
            Text(String(localized: "Lower priority numbers are injected first. Sensitive fields are excluded before prompt construction."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func sourceEnabledBinding(for kind: LLMContextItem.Kind) -> Binding<Bool> {
        Binding(
            get: { settings.config(for: kind).enabled },
            set: { enabled in
                var source = settings.config(for: kind)
                source.enabled = enabled
                settings.update(source)
            }
        )
    }

    private func sourcePriorityBinding(for kind: LLMContextItem.Kind) -> Binding<Int> {
        Binding(
            get: { settings.config(for: kind).priority },
            set: { priority in
                var source = settings.config(for: kind)
                source.priority = priority
                settings.update(source)
            }
        )
    }
}

private extension LLMContextItem.Kind {
    var displayName: String {
        switch self {
        case .selectedText:
            String(localized: "Selected Text")
        case .inputText:
            String(localized: "Input Text")
        case .windowTitle:
            String(localized: "Window Title")
        case .applicationName:
            String(localized: "Application Name")
        case .clipboard:
            String(localized: "Clipboard")
        case .knowledgeBase:
            String(localized: "Knowledge Base")
        case .custom:
            String(localized: "Custom")
        }
    }
}
