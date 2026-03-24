import Combine
import SwiftUI

@main
struct TingMoApp: App {
    @Environment(\.openWindow) private var openWindow
    @State private var isRecording = false
    @State private var permissionManager = PermissionManager()
    @State private var audioDeviceManager = AudioDeviceManager()
    @State private var hotkeyManager = HotkeyManager()
    @State private var engineRegistry = EngineRegistry()
    @State private var statusIndicatorManager = StatusIndicatorManager()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var didCheckOnboarding = false
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
        // Create a temporary reference to start the tap immediately.
        // The @State hotkeyManager will be the actual instance used by SwiftUI.
        // We rely on HotkeyManager.init() loading persisted settings,
        // and start() being called once the @State is available.
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

            Button(isRecording ? String(localized: "Stop Recording") : String(localized: "Start Recording")) {
                toggleRecording()
            }
            .keyboardShortcut("r", modifiers: .command)

            Divider()

            Button(String(localized: "Settings...")) {
                openWindow(id: "settings-window")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button(String(localized: "Quit")) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(nsImage: isRecording ? Self.menuBarIconRecording : Self.menuBarIcon)
                .onAppear {
                    // The menu bar icon's onAppear fires at app launch, unlike menu content
                    hotkeyManager.start()
                    subscribeToHotkeyEvents()
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

    private func toggleRecording() {
        isRecording.toggle()
        if isRecording {
            statusIndicatorManager.audioLevel = 0.3
            statusIndicatorManager.show()
        } else {
            statusIndicatorManager.hide()
        }
    }

    private func subscribeToHotkeyEvents() {
        guard hotkeyCancellable == nil else { return }
        hotkeyCancellable = hotkeyManager.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { event in
                switch event {
                case .startRecording:
                    if !isRecording {
                        toggleRecording()
                    }
                case .stopRecording:
                    if isRecording {
                        toggleRecording()
                    }
                case .cancelRecording:
                    if isRecording {
                        isRecording = false
                        statusIndicatorManager.hide()
                    }
                }
            }
    }
}
