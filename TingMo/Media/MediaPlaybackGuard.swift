import AppKit
import CoreAudio

/// Pauses system media playback while dictation records and resumes it
/// afterwards — the macOS counterpart of iOS audio-session interruption,
/// which AppKit does not provide.
///
/// Detection reads the default output device's "running somewhere" flag,
/// so anything audibly playing (Music, Spotify, a browser tab) counts.
/// Control posts the system play/pause media key, which the OS routes to
/// the current Now Playing app; the private MediaRemote framework would be
/// cleaner but is entitlement-locked for third parties since macOS 15.4.
final class MediaPlaybackGuard {
    private let isSystemAudioPlaying: () -> Bool
    private let togglePlayPause: () -> Void

    /// True while we owe the media app a resume. Exposed for tests.
    private(set) var pausedByUs = false

    init(
        isSystemAudioPlaying: @escaping () -> Bool = MediaPlaybackGuard.defaultOutputDeviceIsRunning,
        togglePlayPause: @escaping () -> Void = MediaPlaybackGuard.postPlayPauseMediaKey
    ) {
        self.isSystemAudioPlaying = isSystemAudioPlaying
        self.togglePlayPause = togglePlayPause
    }

    /// Pause playback if something is audibly playing. Call before the
    /// microphone opens so the music tail stays out of the recording.
    func pauseForRecording() {
        pausedByUs = false
        guard isSystemAudioPlaying() else { return }
        togglePlayPause()
        pausedByUs = true
    }

    /// Resume playback, but only when `pauseForRecording()` actually paused
    /// something. Safe to call from every recording-teardown path; it
    /// resumes at most once per pause.
    func resumeAfterRecording() {
        guard pausedByUs else { return }
        pausedByUs = false
        togglePlayPause()
    }

    // MARK: - System hooks

    /// Whether any process is currently rendering to the default output
    /// device. A paused player usually releases the device within a few
    /// seconds, so this tracks "audibly playing" closely enough.
    static func defaultOutputDeviceIsRunning() -> Bool {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let deviceStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard deviceStatus == noErr, deviceID != kAudioObjectUnknown else { return false }

        var isRunning: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        let runningStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &isRunning)
        return runningStatus == noErr && isRunning != 0
    }

    /// Post the hardware play/pause media key. The OS delivers it to the
    /// active Now Playing app, the same target the keyboard key controls.
    static func postPlayPauseMediaKey() {
        postPlayPauseKey(down: true)
        postPlayPauseKey(down: false)
    }

    private static func postPlayPauseKey(down: Bool) {
        let playKeyType: Int32 = 16 // NX_KEYTYPE_PLAY
        let flags: UInt = down ? 0x0A00 : 0x0B00 // NX key down / key up
        let data1 = Int((playKeyType << 16) | Int32(flags))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: flags),
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8, // NX_SUBTYPE_AUX_CONTROL_BUTTONS
            data1: data1,
            data2: -1
        ) else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
