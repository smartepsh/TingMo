import Combine
import SwiftUI

@main
struct TingMoApp: App {
    @Environment(\.openWindow) private var openWindow
    @State private var permissionManager = PermissionManager()
    @State private var audioDeviceManager = AudioDeviceManager()
    @State private var hotkeyManager = HotkeyManager()
    @State private var engineRegistry = EngineRegistry()
    @State private var statusIndicatorManager = StatusIndicatorManager()
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
        let registry = EngineRegistry()
        _engineRegistry = State(initialValue: registry)
        _pipeline = State(initialValue: DictationPipeline(registry: registry))
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
                    hotkeyManager.start()
                    subscribeToHotkeyEvents()
                    prefetchDefaultModelIfNeeded()
                }
                .onChange(of: audioDeviceManager.deviceDisconnectedDuringRecording) { _, disconnected in
                    guard disconnected else { return }
                    audioDeviceManager.deviceDisconnectedDuringRecording = false
                    if pipeline.state == .recording {
                        pipeline.cancel()
                        statusIndicatorManager.hide()
                    }
                }
        }

        Window(String(localized: "Settings"), id: "settings-window") {
            SettingsView(
                permissionManager: permissionManager,
                audioDeviceManager: audioDeviceManager,
                hotkeyManager: hotkeyManager,
                statusIndicatorManager: statusIndicatorManager
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
            statusIndicatorManager.hide()
        } else if pipeline.state == .idle {
            let preferredUID = audioDeviceManager.firstOnlineDevice()?.uid
            do {
                try pipeline.start(preferredDeviceUID: preferredUID)
                audioDeviceManager.isRecording = true
                statusIndicatorManager.audioLevel = 0.3
                statusIndicatorManager.show()
            } catch {
                // Error surfaced via pipeline.lastError + menu text.
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
                        statusIndicatorManager.hide()
                    }
                }
            }
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
