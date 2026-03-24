import SwiftUI

struct PermissionStatusView: View {
    let type: PermissionType
    let status: PermissionStatus
    let onRequest: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.systemImage)
                .font(.title2)
                .foregroundStyle(status == .granted ? .green : .secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(type.displayName)
                        .fontWeight(.medium)

                    if !type.isRequired {
                        Text("Optional")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }

                Text(type.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if status == .granted {
                Label(String(localized: "Granted"), systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else if status == .notDetermined {
                Button(String(localized: "Grant Access")) {
                    onRequest()
                }
                .controlSize(.small)
            } else {
                Button(String(localized: "Open Settings")) {
                    onOpenSettings()
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
