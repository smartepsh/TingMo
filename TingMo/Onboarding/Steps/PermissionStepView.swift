import Combine
import SwiftUI

struct PermissionStepView: View {
    let type: PermissionType
    let permissionManager: PermissionManager

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: type.systemImage)
                .font(.system(size: 48))
                .foregroundStyle(
                    permissionManager.status(for: type) == .granted ? Color.green : Color.accentColor
                )

            Text(type.displayName)
                .font(.title)
                .fontWeight(.bold)

            Text(type.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

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
            .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onReceive(timer) { _ in
            permissionManager.refreshAll()
        }
    }
}
