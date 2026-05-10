import SwiftUI
import CoreGraphics

struct ContextSettingsSection: View {
    @Bindable var settings: ContextSettingsStore
    @State private var showPermissionAlert = false

    var body: some View {
        Section {
            HStack {
                Toggle(String(localized: "Screenshot OCR"), isOn: ocrEnabledBinding)

                Text(String(localized: "Needs Screen Recording"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        } header: {
            Text("Context")
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

    private var ocrEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.screenshotOCREnabled },
            set: { enabled in
                if enabled {
                    let hasAccess = CGPreflightScreenCaptureAccess()
                    if !hasAccess {
                        CGRequestScreenCaptureAccess()
                        showPermissionAlert = true
                        return
                    }
                }
                settings.screenshotOCREnabled = enabled
            }
        )
    }
}
