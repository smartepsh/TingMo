import CoreAudio
import Foundation
import Observation
import SwiftUI

@Observable
final class AudioDeviceManager {
    /// Ordered device list — online + historical offline devices, reflecting user's priority order.
    var devices: [AudioDevice] = []

    /// Whether a recording session is active (set externally by the recording pipeline).
    /// Clearing it drops the bound device so the two can never drift apart.
    var isRecording = false {
        didSet {
            if !isRecording { recordingDeviceUID = nil }
        }
    }

    /// UID of the device the active recording is bound to. Set alongside
    /// `isRecording` so a disconnect only interrupts when it is *this* device
    /// that went away — unrelated devices dropping off must not cut a session
    /// short. Nil means the recording device is unknown, which is treated
    /// conservatively as "any disconnect is relevant".
    var recordingDeviceUID: String?

    /// Set when the active device disconnects during recording.
    var deviceDisconnectedDuringRecording = false

    private static let storageKey = "AudioDeviceManager.persistedDevices"

    init() {
        loadPersistedDevices()
        refreshOnlineStatus()
        installDeviceChangeListener()
    }

    deinit {
        removeDeviceChangeListener()
    }

    // MARK: - Public API

    /// Refresh all device online/offline statuses and discover new devices.
    func refreshOnlineStatus() {
        let onlineDevices = AudioDeviceEnumerator.enumerateInputDevices()
        let onlineUIDs = Set(onlineDevices.map(\.uid))

        // Mark existing devices online/offline and update names for online ones
        for i in devices.indices {
            if let onlineDevice = onlineDevices.first(where: { $0.uid == devices[i].uid }) {
                devices[i].isOnline = true
                devices[i].name = onlineDevice.name
            } else {
                devices[i].isOnline = false
            }
        }

        // Add newly discovered devices at the end
        let existingUIDs = Set(devices.map(\.uid))
        for device in onlineDevices where !existingUIDs.contains(device.uid) {
            devices.append(device)
        }

        persist()
    }

    /// Move device from one position to another (drag-to-reorder).
    func moveDevices(from source: IndexSet, to destination: Int) {
        devices.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    /// Remove a historical (offline) device from the list.
    func removeDevice(at offsets: IndexSet) {
        devices.remove(atOffsets: offsets)
        persist()
    }

    func removeDevice(_ device: AudioDevice) {
        devices.removeAll { $0.uid == device.uid }
        persist()
    }

    /// Returns the first online device from the priority list.
    func firstOnlineDevice() -> AudioDevice? {
        devices.first(where: \.isOnline)
    }

    /// Returns a specific device by UID, if it is online.
    func onlineDevice(uid: String) -> AudioDevice? {
        devices.first { $0.uid == uid && $0.isOnline }
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func loadPersistedDevices() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let saved = try? JSONDecoder().decode([AudioDevice].self, from: data)
        else { return }
        devices = saved
    }

    // MARK: - CoreAudio Listener

    private var listenerBlock: AudioObjectPropertyListenerBlock?

    private func installDeviceChangeListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.handleDeviceChange()
            }
        }
        listenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )
    }

    private func removeDeviceChangeListener() {
        guard let block = listenerBlock else { return }
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )
        listenerBlock = nil
    }

    private func handleDeviceChange() {
        let previouslyOnline = Set(devices.filter(\.isOnline).map(\.uid))
        refreshOnlineStatus()
        let nowOnline = Set(devices.filter(\.isOnline).map(\.uid))

        // Only the device being recorded from matters. Other devices dropping
        // off the system (displays, virtual devices, a second interface) must
        // not interrupt an in-progress recording.
        let disconnected = previouslyOnline.subtracting(nowOnline)
        guard isRecording, !disconnected.isEmpty else { return }

        let affectsRecording = recordingDeviceUID.map(disconnected.contains) ?? true
        if affectsRecording {
            deviceDisconnectedDuringRecording = true
            isRecording = false
            recordingDeviceUID = nil
        }
    }
}
