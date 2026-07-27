import SwiftUI

struct SettingsView: View {
    let permissionManager: PermissionManager
    let audioDeviceManager: AudioDeviceManager
    let hotkeyManager: HotkeyManager
    let statusIndicatorManager: StatusIndicatorManager
    @Bindable var engineRegistry: EngineRegistry
    @Bindable var languagePreference: LanguagePreference
    @Bindable var downloadSource: DownloadSourcePreference
    @Bindable var importedModelStore: ImportedModelStore
    @Bindable var presetStore: ConfigPresetStore
    @Bindable var llmInstanceStore: LLMInstanceStore
    @Bindable var sttInstanceStore: STTInstanceStore
    @Bindable var contextSettings: ContextSettingsStore
    @Bindable var updateManager: UpdateManager

    @Environment(\.openWindow) private var openWindow
    @State private var selectedPage: SettingsPage = .presets
    /// Shared with `TextInjector` (UserDefaults key
    /// "TextInjection.restoreDelay"). Binding via @AppStorage gives us a
    /// single source of truth that is reactive in the UI and immediately
    /// read by the injector on the next transcription.
    @AppStorage("TextInjection.restoreDelay") private var clipboardRestoreDelay: Double = 5

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selectedPage: $selectedPage)

            Divider()

            VStack(spacing: 0) {
                SettingsPageHeader(page: selectedPage)

                Divider()

                Form {
                    selectedPageContent
                }
                .formStyle(.grouped)
            }
            .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 820, minHeight: 640)
        .onAppear {
            permissionManager.refreshAll()
            permissionManager.startPolling()
        }
        .onDisappear {
            permissionManager.stopPolling()
        }
    }

    @ViewBuilder
    private var selectedPageContent: some View {
        switch selectedPage {
        case .presets:
            PresetSettingsSection(
                presetStore: presetStore,
                instanceStore: llmInstanceStore,
                sttInstanceStore: sttInstanceStore,
                engineRegistry: engineRegistry
            )

        case .speech:
            STTInstanceSettingsSection(
                instanceStore: sttInstanceStore,
                engineRegistry: engineRegistry,
                presetStore: presetStore
            )

            LocalProviderSection(
                engineRegistry: engineRegistry,
                downloadSource: downloadSource,
                importedModelStore: importedModelStore,
                presetStore: presetStore
            )

        case .correction:
            LLMInstanceSettingsSection(
                instanceStore: llmInstanceStore,
                presetStore: presetStore
            )

            ContextSettingsSection(settings: contextSettings)

        case .system:
            Section {
                AudioDeviceListView(deviceManager: audioDeviceManager)
                    .frame(minHeight: 140)
            } header: {
                Text("Audio Devices")
            }

            Section {
                Picker(String(localized: "Display Mode"), selection: Binding(
                    get: { statusIndicatorManager.mode },
                    set: { statusIndicatorManager.mode = $0 }
                )) {
                    ForEach(StatusIndicatorMode.allCases) { mode in
                        VStack(alignment: .leading) {
                            Text(mode.displayName)
                        }
                        .tag(mode)
                    }
                }

                if statusIndicatorManager.mode == .notch && !StatusIndicatorMode.anyScreenHasNotch {
                    Label(String(localized: "No notch detected on any screen — will use Top Center mode"), systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(String(localized: "Preview Indicator")) {
                    statusIndicatorManager.audioLevel = 0.5
                    statusIndicatorManager.previewText = "Hello, this is a preview..."
                    statusIndicatorManager.show()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        statusIndicatorManager.hide()
                    }
                }
            } header: {
                Text("Status Indicator")
            }

            HotkeySettingsView(hotkeyManager: hotkeyManager)

            Section {
                LabeledContent(String(localized: "Restore original clipboard after")) {
                    HStack {
                        Text(String(format: "%d s", Int(clipboardRestoreDelay)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Stepper(
                            value: $clipboardRestoreDelay,
                            in: 1...120,
                            step: 1
                        ) {
                            EmptyView()
                        }
                    }
                }
            } header: {
                Text("Clipboard")
            } footer: {
                Text("After TingMo pastes the transcription result, keep it on the clipboard for this many seconds before restoring your original clipboard content.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(PermissionType.allCases) { type in
                    PermissionStatusView(
                        type: type,
                        status: permissionManager.status(for: type),
                        onRequest: {
                            Task { await permissionManager.request(for: type) }
                        },
                        onOpenSettings: {
                            permissionManager.openSystemSettings(for: type)
                        }
                    )
                }
            } header: {
                Text("Permissions")
            }

            SoftwareUpdateSettingsSection(updateManager: updateManager)

            Section {
                Button(String(localized: "Run Setup Wizard Again")) {
                    openWindow(id: "onboarding-window")
                }
            }
        }
    }
}

private enum SettingsPage: CaseIterable, Hashable, Identifiable {
    case presets
    case speech
    case correction
    case system

    var id: Self { self }

    var title: String {
        switch self {
        case .presets:
            String(localized: "Presets")
        case .speech:
            String(localized: "Speech Recognition")
        case .correction:
            String(localized: "Correction")
        case .system:
            String(localized: "System")
        }
    }

    var systemImage: String {
        switch self {
        case .presets:
            "slider.horizontal.3"
        case .speech:
            "waveform"
        case .correction:
            "sparkles"
        case .system:
            "gearshape"
        }
    }
}

private struct SettingsSidebar: View {
    @Binding var selectedPage: SettingsPage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Settings"))
                .font(.headline)
                .padding(.horizontal, 10)

            VStack(spacing: 4) {
                ForEach(SettingsPage.allCases) { page in
                    sidebarButton(for: page)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 16)
        .frame(width: 190, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func sidebarButton(for page: SettingsPage) -> some View {
        let isSelected = selectedPage == page

        return Button {
            selectedPage = page
        } label: {
            Label {
                Text(page.title)
                    .lineLimit(1)
            } icon: {
                Image(systemName: page.systemImage)
                    .frame(width: 18)
            }
            .font(.callout)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .padding(.horizontal, 10)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsPageHeader: View {
    let page: SettingsPage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: page.systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            Text(page.title)
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
    }
}
