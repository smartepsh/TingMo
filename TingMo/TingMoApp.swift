import SwiftUI

@main
struct TingMoApp: App {
    @Environment(\.openWindow) private var openWindow
    @State private var isRecording = false

    var body: some Scene {
        MenuBarExtra {
            Text("TingMo 听墨")
                .font(.headline)

            Divider()

            Button(isRecording ? "Stop Recording" : "Start Recording") {
                isRecording.toggle()
            }
            .keyboardShortcut("r", modifiers: .command)

            Divider()

            Button("Settings...") {
                openWindow(id: "settings-window")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: isRecording ? "mic.and.signal.meter.fill" : "mic.and.signal.meter")
        }

        Window("Settings", id: "settings-window") {
            SettingsView()
        }
    }
}
