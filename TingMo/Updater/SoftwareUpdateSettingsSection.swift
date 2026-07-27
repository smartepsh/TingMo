import SwiftUI

struct SoftwareUpdateSettingsSection: View {
    @Bindable var updateManager: UpdateManager

    var body: some View {
        Section {
            LabeledContent(String(localized: "Current Version")) {
                Text(updateManager.currentVersionString)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Toggle(
                String(localized: "Automatically check for updates"),
                isOn: $updateManager.automaticChecksEnabled
            )

            statusContent

            HStack {
                primaryButton

                if updateManager.latestRelease != nil {
                    Button(String(localized: "View Release Notes")) {
                        updateManager.openLatestReleasePage()
                    }
                }
            }
        } header: {
            Text("Software Update")
        } footer: {
            Text("TingMo checks the latest GitHub Release at most once per day. Updates are downloaded to your Downloads folder and opened for installation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch updateManager.state {
        case .idle:
            EmptyView()
        case .checking:
            Label(String(localized: "Checking for updates…"), systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                .foregroundStyle(.secondary)
        case .upToDate:
            Label(String(localized: "TingMo is up to date."), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .updateAvailable:
            if let version = updateManager.latestRelease?.version {
                Label(
                    String(localized: "TingMo \(version.description) is available."),
                    systemImage: "arrow.down.circle.fill"
                )
                .foregroundStyle(Color.accentColor)
            }
        case .downloading:
            Label(String(localized: "Downloading update…"), systemImage: "arrow.down.circle")
                .foregroundStyle(.secondary)
        case .downloaded:
            Label(
                String(localized: "The update installer has been downloaded and opened."),
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch updateManager.state {
        case .updateAvailable:
            Button(String(localized: "Download Update")) {
                Task { await updateManager.downloadAvailableUpdate() }
            }
            .buttonStyle(.borderedProminent)
        case .downloaded:
            Button(String(localized: "Open Installer Again")) {
                updateManager.openDownloadedUpdate()
            }
        default:
            Button(String(localized: "Check for Updates…")) {
                Task { await updateManager.checkForUpdates() }
            }
            .disabled(updateManager.isBusy)
        }
    }
}
