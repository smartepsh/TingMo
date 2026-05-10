import SwiftUI
import CoreGraphics

struct ContextSettingsSection: View {
    @Bindable var settings: ContextSettingsStore
    @State private var showPermissionAlert = false

    private var sortedSources: [ContextSourceConfig] {
        settings.sources
            .filter { $0.kind != .knowledgeBase && $0.kind != .custom }
            .sorted { $0.priority < $1.priority }
    }

    var body: some View {
        Section {
            ForEach(sortedSources) { source in
                sourceRow(for: source)
            }

            Stepper(
                value: $settings.ocrTriggerThreshold,
                in: 10...500,
                step: 10
            ) {
                Text(String(localized: "OCR trigger: < \(settings.ocrTriggerThreshold) info chars"))
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

            Toggle("Log context for dogfood", isOn: $settings.debugLoggingEnabled)
        } header: {
            Text("Context")
        } footer: {
            Text(String(localized: "Each source gets a share of the total character budget. Unused budget is redistributed. Screenshot OCR requires Screen Recording permission and uses remaining space."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .alert("Screen Recording Permission Required", isPresented: $showPermissionAlert) {
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Screenshot OCR requires Screen Recording permission. Please grant permission in System Settings > Privacy & Security > Screen Recording.")
        }
    }

    @ViewBuilder
    private func sourceRow(for source: ContextSourceConfig) -> some View {
        let config = settings.config(for: source.kind)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle(source.kind.displayName, isOn: sourceEnabledBinding(for: source.kind))

                if source.kind == .screenshotOCR {
                    Text(String(localized: "Needs Screen Recording"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if source.kind != .screenshotOCR && config.enabled {
                HStack {
                    Text(String(localized: "Budget"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .leading)
                    Slider(
                        value: sourceBudgetBinding(for: source.kind),
                        in: 0...100,
                        step: 5
                    ) {
                        EmptyView()
                    }
                    Text("\(config.budgetPercent)%")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func sourceEnabledBinding(for kind: LLMContextItem.Kind) -> Binding<Bool> {
        Binding(
            get: { settings.config(for: kind).enabled },
            set: { enabled in
                if enabled && kind == .screenshotOCR {
                    let hasAccess = CGPreflightScreenCaptureAccess()
                    if !hasAccess {
                        // Trigger registration in System Settings by requesting access
                        CGRequestScreenCaptureAccess()
                        showPermissionAlert = true
                        return
                    }
                }
                var source = settings.config(for: kind)
                source.enabled = enabled
                settings.update(source)
            }
        )
    }

    private func sourceBudgetBinding(for kind: LLMContextItem.Kind) -> Binding<Double> {
        Binding(
            get: { Double(settings.config(for: kind).budgetPercent) },
            set: { percent in
                var source = settings.config(for: kind)
                source.budgetPercent = Int(percent)
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
        case .windowContent:
            String(localized: "Window Content")
        case .screenshotOCR:
            String(localized: "Screenshot OCR")
        case .knowledgeBase:
            String(localized: "Knowledge Base")
        case .custom:
            String(localized: "Custom")
        }
    }
}
