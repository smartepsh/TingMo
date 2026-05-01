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
    @State private var pipeline: DictationPipeline
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var didCheckOnboarding = false
    @State private var didPrefetchModel = false
    @State private var hotkeyCancellable: AnyCancellable?

    private static let menuBarIcon: NSImage = {
        let image = NSImage(named: "MenuBarIcon") ?? NSImage()
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
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
        let registry = EngineRegistry(
            downloadSource: downloadSource,
            importedModelStore: importedStore,
            sttInstanceStore: sttInstanceStore
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
        _sttInstanceStore = State(initialValue: sttInstanceStore)
        _contextSettings = State(initialValue: contextSettings)
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
    private var showRecordingIcon: Bool {
        pipeline.state == .recording
    }

    private var statusText: String {
        switch pipeline.state {
        case .idle: String(localized: "Idle")
        case .recording: String(localized: "Recording…")
        case .transcribing: String(localized: "Transcribing…")
        }
    }

    private var primaryButtonTitle: String {
        switch pipeline.state {
        case .idle: String(localized: "Start Recording")
        case .recording: String(localized: "Stop Recording")
        case .transcribing: String(localized: "Transcribing…")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            Button(primaryButtonTitle) {
                toggleRecording()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(pipeline.state == .transcribing)
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
                ForEach(engineRegistry.engines, id: \.info.id) { engine in
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
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(pipeline.state == .recording)

            Divider()

            Button(String(localized: "Quit")) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(nsImage: showRecordingIcon ? Self.menuBarIconRecording : Self.menuBarIcon)
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
                    prefetchDefaultModelIfNeeded()
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
                    // When the pipeline returns to idle after transcribing,
                    // flash any surfaced error on the indicator, otherwise
                    // hide it.
                    if newState == .idle {
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
                importedModelStore: importedModelStore,
                presetStore: presetStore,
                llmInstanceStore: llmInstanceStore,
                sttInstanceStore: sttInstanceStore,
                contextSettings: contextSettings
            )
        }
        .defaultSize(width: 860, height: 700)

        Window(String(localized: "Setup Wizard"), id: "onboarding-window") {
            OnboardingView(permissionManager: permissionManager)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }

    // MARK: - Recording control

    private func toggleRecording() {
        if pipeline.state == .recording {
            pipeline.stopAndTranscribe()
            audioDeviceManager.isRecording = false
            // Keep indicator visible in processing state; it hides on success
            // or flashes the error via the lastError observer.
            statusIndicatorManager.setProcessing(true)
        } else if pipeline.state == .idle {
            let preferredUID = audioDeviceManager.firstOnlineDevice()?.uid
            do {
                try pipeline.start(preferredDeviceUID: preferredUID)
                audioDeviceManager.isRecording = true
                statusIndicatorManager.setProcessing(false)
                statusIndicatorManager.audioLevel = 0.3
                statusIndicatorManager.show()
            } catch {
                let message = (pipeline.lastError ?? error).localizedDescription
                statusIndicatorManager.showError(message)
            }
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
                    if pipeline.state == .recording {
                        toggleRecording()
                    }
                case .cancelRecording:
                    if pipeline.state == .recording {
                        pipeline.cancel()
                        audioDeviceManager.isRecording = false
                        statusIndicatorManager.setProcessing(false)
                        statusIndicatorManager.hide()
                    }
                }
            }
    }

    // MARK: - Preset quick editor

    @ViewBuilder
    private func recognitionEngineMenuButton(engine: any SpeechEngine) -> some View {
        let isActive = presetStore.defaultPreset.speechEngineID == engine.info.id
        let ready = engine.info.isReady

        let title: String = {
            var label = menuTitle(engine.info.name, isActive: isActive)
            if !ready {
                if engine.info.type == .remote {
                    label += " — \(String(localized: "Missing API Key"))"
                } else {
                    label += " — \(String(localized: "Not Downloaded"))"
                }
            }
            return label
        }()

        Button(title) {
            presetStore.defaultPreset.speechEngineID = engine.info.id
            engineRegistry.setActiveEngine(engine.info.id)
        }
        .disabled(isActive || !ready)
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

    // MARK: - Model prefetch (M1 hotest convenience)

    /// Kick off a background download of the default tiny model if it's not
    /// on disk yet, so the first recording doesn't require manual setup.
    /// Temporary until M1-5 adds a real download UI.
    private func prefetchDefaultModelIfNeeded() {
        guard !didPrefetchModel else { return }
        didPrefetchModel = true

        guard let whisper = engineRegistry.engine(id: presetStore.defaultPreset.speechEngineID) as? WhisperKitEngine else { return }
        if whisper.info.isReady { return }

        Task.detached {
            try? await whisper.downloadModel()
            try? await whisper.loadModel()
        }
    }
}
