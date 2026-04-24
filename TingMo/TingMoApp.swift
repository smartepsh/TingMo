import Combine
import SwiftUI

@main
struct TingMoApp: App {
    @Environment(\.openWindow) private var openWindow
    @State private var permissionManager = PermissionManager()
    @State private var audioDeviceManager = AudioDeviceManager()
    @State private var hotkeyManager = HotkeyManager()
    @State private var engineRegistry: EngineRegistry
    @State private var statusIndicatorManager = StatusIndicatorManager()
    @State private var languagePreference = LanguagePreference()
    @State private var downloadSource = DownloadSourcePreference()
    @State private var importedModelStore = ImportedModelStore()
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
        let downloadSource = DownloadSourcePreference()
        let importedStore = ImportedModelStore()
        let registry = EngineRegistry(
            downloadSource: downloadSource,
            importedModelStore: importedStore
        )
        let languagePreference = LanguagePreference()
        _engineRegistry = State(initialValue: registry)
        _languagePreference = State(initialValue: languagePreference)
        _downloadSource = State(initialValue: downloadSource)
        _importedModelStore = State(initialValue: importedStore)
        _pipeline = State(initialValue: DictationPipeline(
            registry: registry,
            languagePreference: languagePreference
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
            Text("TingMo 听墨")
                .font(.headline)
                .onAppear {
                    guard !didCheckOnboarding else { return }
                    didCheckOnboarding = true
                    if !hasCompletedOnboarding {
                        openWindow(id: "onboarding-window")
                    }
                }

            Divider()

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            let inputName = audioDeviceManager.firstOnlineDevice()?.name
                ?? String(localized: "System Default")
            Text(String(localized: "Input: \(inputName)"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let err = pipeline.lastError {
                Text(err.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            Button(primaryButtonTitle) {
                toggleRecording()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(pipeline.state == .transcribing)

            Divider()

            Menu(String(localized: "Speech Model")) {
                ForEach(WhisperKitEngine.availableModels) { model in
                    let engineID = "\(WhisperKitEngine.engineID)-\(model.id)"
                    modelMenuButton(engineID: engineID, model: model)
                }

                Divider()

                Button(String(localized: "Parakeet (English) — Coming Soon")) {}
                    .disabled(true)
            }
            .disabled(pipeline.state != .idle)

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
                importedModelStore: importedModelStore
            )
        }

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

    // MARK: - Model menu

    @ViewBuilder
    private func modelMenuButton(engineID: String, model: WhisperKitEngine.WhisperModel) -> some View {
        let isActive = engineRegistry.activeEngineID == engineID
        let downloaded = WhisperKitEngine.isModelDownloaded(model)
        let progress = engineRegistry.progress(for: engineID)
        let loading = engineRegistry.isLoading(engineID)
        let error = engineRegistry.downloadError(for: engineID)

        let title: String = {
            if let err = error {
                return "\(model.name) — \(String(localized: "Failed")): \(err)"
            }
            if let p = progress {
                return "\(model.name) — \(Int(p * 100))%"
            }
            if loading {
                return "\(model.name) — \(String(localized: "Loading…"))"
            }
            if isActive { return "✓ \(model.name) (\(model.size))" }
            if downloaded { return "\(model.name) (\(model.size))" }
            return "\(model.name) (\(model.size)) — \(String(localized: "Download"))"
        }()

        Button(title) {
            if error != nil {
                engineRegistry.clearDownloadError(for: engineID)
                engineRegistry.downloadModel(engineID: engineID)
            } else if downloaded {
                engineRegistry.setActiveEngine(engineID)
            } else {
                engineRegistry.downloadModel(engineID: engineID)
            }
        }
        .disabled(progress != nil || loading || isActive)
    }

    // MARK: - Model prefetch (M1 hotest convenience)

    /// Kick off a background download of the default tiny model if it's not
    /// on disk yet, so the first recording doesn't require manual setup.
    /// Temporary until M1-5 adds a real download UI.
    private func prefetchDefaultModelIfNeeded() {
        guard !didPrefetchModel else { return }
        didPrefetchModel = true

        guard let whisper = engineRegistry.activeEngine as? WhisperKitEngine else { return }
        if whisper.info.isReady { return }

        Task.detached {
            try? await whisper.downloadModel()
            try? await whisper.loadModel()
        }
    }
}
