import Combine
import SwiftUI

@main
struct TingMoApp: App {
    @Environment(\.openWindow) private var openWindow
    @State private var permissionManager: PermissionManager
    @State private var audioDeviceManager: AudioDeviceManager
    @State private var hotkeyManager: HotkeyManager
    @State private var engineRegistry: EngineRegistry
    @State private var statusIndicatorManager: StatusIndicatorManager
    @State private var languagePreference: LanguagePreference
    @State private var downloadSource: DownloadSourcePreference
    @State private var importedModelStore: ImportedModelStore
    @State private var presetStore: ConfigPresetStore
    @State private var llmInstanceStore: LLMInstanceStore
    @State private var sttInstanceStore: STTInstanceStore
    @State private var contextSettings: ContextSettingsStore
    @State private var updateManager: UpdateManager
    @State private var pipeline: DictationPipeline
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var didCheckOnboarding = false
    @State private var hotkeyCancellable: AnyCancellable?

    private static let menuBarIcon: NSImage = {
        let image = NSImage(named: "MenuBarIcon") ?? NSImage()
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    private static let menuBarIconPreparing: NSImage = {
        let source = NSImage(named: "MenuBarIcon") ?? NSImage()
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect)
            NSColor.systemYellow.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        // A template image would be recolored by the menu bar and lose the
        // yellow preparation state.
        image.isTemplate = false
        return image
    }()

    private static let menuBarIconRecording: NSImage = {
        let image = NSImage(named: "MenuBarIconRecording") ?? NSImage()
        image.isTemplate = false
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    init() {
        let permissionManager = PermissionManager()
        let audioDeviceManager = AudioDeviceManager()
        let hotkeyManager = HotkeyManager()
        let statusIndicatorManager = StatusIndicatorManager()
        let downloadSource = DownloadSourcePreference()
        let importedStore = ImportedModelStore()
        let defaultLLMInstanceID = UUID()
        let llmInstanceStore = LLMInstanceStore(defaultID: defaultLLMInstanceID)
        let sttInstanceStore = STTInstanceStore()
        let presetStore = ConfigPresetStore(defaultLLMInstanceID: defaultLLMInstanceID)
        let contextSettings = ContextSettingsStore()
        let updateManager = UpdateManager()
        let registry = EngineRegistry(
            downloadSource: downloadSource,
            importedModelStore: importedStore,
            sttInstanceStore: sttInstanceStore
        )
        let languagePreference = LanguagePreference()

        // Model selection belongs to the preset. Begin preparing that exact
        // engine immediately rather than waiting for a SwiftUI view to appear.
        registry.prepareEngine(
            presetStore.defaultPreset.speechEngineID,
            downloadIfNeeded: true
        )

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
        _sttInstanceStore = State(initialValue: sttInstanceStore)
        _contextSettings = State(initialValue: contextSettings)
        _updateManager = State(initialValue: updateManager)
        _pipeline = State(initialValue: DictationPipeline(
            registry: registry,
            languagePreference: languagePreference,
            presetStore: presetStore,
            llmInstanceStore: llmInstanceStore,
            contextSettings: contextSettings
        ))
    }

    /// Menu icon should only show the recording variant while actively
    /// capturing audio; during transcribing we revert to idle so the user
    /// doesn't think the mic is still live.
    private var currentMenuBarIcon: NSImage {
        if pipeline.state == .recording {
            return Self.menuBarIconRecording
        }
        if isSelectedEnginePreparing {
            return Self.menuBarIconPreparing
        }
        return Self.menuBarIcon
    }

    private var statusText: String {
        switch pipeline.state {
        case .idle: String(localized: "Idle")
        case .preparing: String(localized: "Preparing Recording…")
        case .recording: String(localized: "Recording…")
        case .transcribing: String(localized: "Transcribing…")
        }
    }

    private var selectedEnginePreparationState: EngineRegistry.PreparationState {
        engineRegistry.preparationState(for: presetStore.defaultPreset.speechEngineID)
    }

    private var isSelectedEnginePreparing: Bool {
        selectedEnginePreparationState == .preparing
    }

    private var primaryButtonTitle: String {
        // Show the user-configured global hotkey; it can be modifier-only
        // (e.g. fn), which SwiftUI's keyboardShortcut cannot represent, so
        // it lives in the title instead of a key equivalent.
        let hotkeySuffix = " (\(hotkeyManager.hotkey.displayName))"
        switch pipeline.state {
        case .idle where isSelectedEnginePreparing:
            return String(localized: "Preparing Speech Model…")
        case .idle:
            return String(localized: "Start Recording") + hotkeySuffix
        case .preparing:
            return String(localized: "Cancel Recording Start") + hotkeySuffix
        case .recording:
            return String(localized: "Stop Recording") + hotkeySuffix
        case .transcribing:
            return String(localized: "Transcribing…")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            Button(primaryButtonTitle) {
                toggleRecording()
            }
            .disabled(pipeline.state == .transcribing || isSelectedEnginePreparing)
            .onAppear {
                guard !didCheckOnboarding else { return }
                didCheckOnboarding = true
                if !hasCompletedOnboarding {
                    openWindow(id: "onboarding-window")
                }
            }

            Divider()

            Menu(String(localized: "Preset: \(presetStore.defaultPreset.name)")) {
                Button("✓ \(presetStore.defaultPreset.name)") {}
                    .disabled(true)
            }
            .disabled(pipeline.state != .idle)

            Text(String(localized: "\(presetStore.defaultPreset.name) Settings"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu(String(localized: "Recognition Engine")) {
                ForEach(engineRegistry.engines.filter { $0.info.isReady }, id: \.info.id) { engine in
                    recognitionEngineMenuButton(engine: engine)
                }
            }
            .disabled(pipeline.state != .idle)

            Menu(String(localized: "Correction Engine")) {
                Button(correctionEngineTitle(instance: nil)) {
                    presetStore.defaultPreset.llmInstanceID = nil
                }
                .disabled(presetStore.defaultPreset.llmInstanceID == nil)

                ForEach(llmInstanceStore.instances) { instance in
                    correctionEngineMenuButton(instance: instance)
                }
            }
            .disabled(pipeline.state != .idle)

            if let err = pipeline.lastError {
                Divider()

                Text(err.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            Button(String(localized: "Settings...")) {
                openWindow(id: "settings-window")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(pipeline.state == .recording || pipeline.state == .preparing)

            Button(updateMenuTitle) {
                performUpdateMenuAction()
            }
            .disabled(updateManager.isBusy)

            Divider()

            Button(String(localized: "Quit")) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(nsImage: currentMenuBarIcon)
                .onAppear {
                    // Trigger the system's Accessibility prompt on first launch
                    // so the user actually sees a dialog offering to open
                    // System Settings. Without this, AXIsProcessTrusted stays
                    // false silently and the global hotkey never works.
                    if permissionManager.accessibilityStatus != .granted {
                        permissionManager.requestAccessibility()
                    }
                    hotkeyManager.start()
                    subscribeToHotkeyEvents()
                    Task { await updateManager.checkAutomaticallyIfNeeded() }
                }
                .onChange(of: audioDeviceManager.deviceDisconnectedDuringRecording) { _, disconnected in
                    guard disconnected else { return }
                    audioDeviceManager.deviceDisconnectedDuringRecording = false
                    if pipeline.state == .recording {
                        pipeline.cancel()
                        statusIndicatorManager.showError(
                            String(localized: "Microphone disconnected.")
                        )
                    }
                }
                .onChange(of: pipeline.state) { _, newState in
                    switch newState {
                    case .preparing:
                        audioDeviceManager.isRecording = false
                        statusIndicatorManager.setProcessing(true)
                        statusIndicatorManager.show()
                    case .recording:
                        audioDeviceManager.recordingDeviceUID = pipeline.activeDeviceUID
                        audioDeviceManager.isRecording = true
                        statusIndicatorManager.setProcessing(false)
                        statusIndicatorManager.audioLevel = 0.3
                        statusIndicatorManager.show()
                    case .transcribing:
                        hotkeyManager.recordingDidEnd()
                        audioDeviceManager.isRecording = false
                        statusIndicatorManager.setProcessing(true)
                    case .idle:
                        audioDeviceManager.isRecording = false
                        statusIndicatorManager.setProcessing(false)
                        if let err = pipeline.lastError {
                            statusIndicatorManager.showError(err.localizedDescription)
                        } else if statusIndicatorManager.isShowing {
                            statusIndicatorManager.hide()
                        }
                    }
                }
        }

        Window(String(localized: "Settings"), id: "settings-window") {
            SettingsView(
                permissionManager: permissionManager,
                audioDeviceManager: audioDeviceManager,
                hotkeyManager: hotkeyManager,
                statusIndicatorManager: statusIndicatorManager,
                engineRegistry: engineRegistry,
                languagePreference: languagePreference,
                downloadSource: downloadSource,
                presetStore: presetStore,
                llmInstanceStore: llmInstanceStore,
                sttInstanceStore: sttInstanceStore,
                contextSettings: contextSettings,
                updateManager: updateManager
            )
        }
        .defaultSize(width: 860, height: 700)

        Window(String(localized: "Setup Wizard"), id: "onboarding-window") {
            OnboardingView(permissionManager: permissionManager)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }

    // MARK: - Software update

    private var updateMenuTitle: String {
        switch updateManager.state {
        case .updateAvailable:
            if let version = updateManager.latestRelease?.version {
                String(localized: "Download TingMo \(version.description)…")
            } else {
                String(localized: "Download Update…")
            }
        case .checking:
            String(localized: "Checking for Updates…")
        case .downloading:
            String(localized: "Downloading Update…")
        case .downloaded:
            String(localized: "Open Update Installer")
        default:
            String(localized: "Check for Updates…")
        }
    }

    private func performUpdateMenuAction() {
        switch updateManager.state {
        case .updateAvailable:
            Task { await updateManager.downloadAvailableUpdate() }
        case .downloaded:
            updateManager.openDownloadedUpdate()
        default:
            Task { await checkForUpdatesAndPresentResult() }
        }
    }

    private func checkForUpdatesAndPresentResult() async {
        await updateManager.checkForUpdates()

        switch updateManager.state {
        case .upToDate:
            presentUpdateAlert(
                message: String(localized: "TingMo is up to date."),
                informativeText: String(
                    localized: "Current version: \(updateManager.currentVersionString)"
                )
            )
        case .updateAvailable:
            let version = updateManager.latestRelease?.version?.description ?? ""
            let response = presentUpdateAlert(
                message: String(localized: "TingMo \(version) is available."),
                informativeText: String(
                    localized: "You are currently using TingMo \(updateManager.currentVersionString)."
                ),
                primaryButtonTitle: String(localized: "Download Update"),
                secondaryButtonTitle: String(localized: "Later")
            )
            if response == .alertFirstButtonReturn {
                await updateManager.downloadAvailableUpdate()
            }
        case .failed(let message):
            presentUpdateAlert(
                message: String(localized: "Unable to Check for Updates"),
                informativeText: message,
                style: .warning
            )
        default:
            break
        }
    }

    @discardableResult
    private func presentUpdateAlert(
        message: String,
        informativeText: String,
        style: NSAlert.Style = .informational,
        primaryButtonTitle: String = String(localized: "OK"),
        secondaryButtonTitle: String? = nil
    ) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = message
        alert.informativeText = informativeText
        alert.addButton(withTitle: primaryButtonTitle)
        if let secondaryButtonTitle {
            alert.addButton(withTitle: secondaryButtonTitle)
        }
        return alert.runModal()
    }

    // MARK: - Recording control

    private func toggleRecording() {
        switch pipeline.state {
        case .preparing:
            pipeline.cancel()
        case .recording:
            pipeline.stopAndTranscribe()
        case .idle:
            let preferredUID = audioDeviceManager.firstOnlineDevice()?.uid
            do {
                try pipeline.start(preferredDeviceUID: preferredUID)
            } catch {
                let message = (pipeline.lastError ?? error).localizedDescription
                statusIndicatorManager.showError(message)
            }
        case .transcribing:
            break
        }
    }

    private func subscribeToHotkeyEvents() {
        guard hotkeyCancellable == nil else { return }
        hotkeyCancellable = hotkeyManager.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { event in
                switch event {
                case .startRecording:
                    if pipeline.state == .idle {
                        toggleRecording()
                    }
                case .stopRecording:
                    if pipeline.state == .preparing || pipeline.state == .recording {
                        toggleRecording()
                    }
                case .cancelRecording:
                    if pipeline.state == .preparing || pipeline.state == .recording {
                        pipeline.cancel()
                    }
                }
            }
    }

    // MARK: - Preset quick editor

    @ViewBuilder
    private func recognitionEngineMenuButton(engine: any SpeechEngine) -> some View {
        let isActive = presetStore.defaultPreset.speechEngineID == engine.info.id

        Button(menuTitle(engine.info.name, isActive: isActive)) {
            presetStore.defaultPreset.speechEngineID = engine.info.id
            engineRegistry.prepareEngine(engine.info.id)
        }
        .disabled(isActive)
    }

    @ViewBuilder
    private func correctionEngineMenuButton(instance: LLMInstance) -> some View {
        let isActive = presetStore.defaultPreset.llmInstanceID == instance.id

        Button(correctionEngineTitle(instance: instance)) {
            presetStore.defaultPreset.llmInstanceID = instance.id
        }
        .disabled(isActive)
    }

    private func correctionEngineTitle(instance: LLMInstance?) -> String {
        guard let instance else {
            return menuTitle(String(localized: "Off"), isActive: presetStore.defaultPreset.llmInstanceID == nil)
        }

        return menuTitle(
            "\(instance.displayName) (\(instance.provider.displayName))",
            isActive: presetStore.defaultPreset.llmInstanceID == instance.id
        )
    }

    private func menuTitle(_ title: String, isActive: Bool) -> String {
        isActive ? "✓ \(title)" : title
    }

}
