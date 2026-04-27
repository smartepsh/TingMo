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
    @Bindable var contextSettings: ContextSettingsStore

    @Environment(\.openWindow) private var openWindow

    private var remoteEngines: [RemoteSpeechEngine] {
        engineRegistry.engines.compactMap { $0 as? RemoteSpeechEngine }
    }

    var body: some View {
        Form {
            SettingsAreaHeader(title: String(localized: "Presets"))

            PresetSettingsSection(
                presetStore: presetStore,
                instanceStore: llmInstanceStore
            )

            SettingsAreaHeader(title: String(localized: "Speech"))

            EngineSettingsView(
                engineRegistry: engineRegistry,
                languagePreference: languagePreference,
                presetStore: presetStore
            )

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

            ForEach(remoteEngines, id: \.info.id) { engine in
                RemoteEngineSection(
                    engine: engine,
                    engineRegistry: engineRegistry
                )
            }

            Section {
                AudioDeviceListView(deviceManager: audioDeviceManager)
                    .frame(minHeight: 100)
            } header: {
                Text("Audio Devices")
            }

            SettingsAreaHeader(title: String(localized: "LLM Instances"))

            LLMInstanceSettingsSection(
                instanceStore: llmInstanceStore,
                presetStore: presetStore
            )

            SettingsAreaHeader(title: String(localized: "Behavior"))

            ContextSettingsSection(settings: contextSettings)

            HotkeySettingsView(hotkeyManager: hotkeyManager)

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
                    // Auto-hide after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        statusIndicatorManager.hide()
                    }
                }
            } header: {
                Text("Status Indicator")
            }

            SettingsAreaHeader(title: String(localized: "Advanced"))

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

            Section {
                Button(String(localized: "Run Setup Wizard Again")) {
                    openWindow(id: "onboarding-window")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 700)
        .onAppear {
            permissionManager.refreshAll()
            permissionManager.startPolling()
        }
        .onDisappear {
            permissionManager.stopPolling()
        }
    }
}

private struct SettingsAreaHeader: View {
    let title: String

    var body: some View {
        Section {} header: {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
        }
    }
}
