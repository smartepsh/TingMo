import SwiftUI

struct AudioDeviceListView: View {
    let deviceManager: AudioDeviceManager

    var body: some View {
        List {
            ForEach(deviceManager.devices) { device in
                AudioDeviceRow(device: device, onRemove: {
                    deviceManager.removeDevice(device)
                })
            }
            .onMove { source, destination in
                deviceManager.moveDevices(from: source, to: destination)
            }
        }
        .overlay {
            if deviceManager.devices.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Audio Devices"),
                    systemImage: "mic.slash",
                    description: Text("No audio input devices found.")
                )
            }
        }
    }
}

private struct AudioDeviceRow: View {
    let device: AudioDevice
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.isOnline ? "mic.fill" : "mic.slash")
                .foregroundStyle(device.isOnline ? .primary : .tertiary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .foregroundStyle(device.isOnline ? .primary : .secondary)

                Text(device.isOnline ? String(localized: "Online") : String(localized: "Offline"))
                    .font(.caption)
                    .foregroundStyle(device.isOnline ? .green : .secondary)
            }

            Spacer()

            if !device.isOnline {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Remove historical device"))
            }
        }
        .padding(.vertical, 2)
    }
}
