import AVFoundation
import Observation
import Speech
import SwiftUI

enum PermissionStatus: String {
    case notDetermined
    case granted
    case denied
    case restricted
}

enum PermissionType: String, CaseIterable, Identifiable {
    case microphone
    case speechRecognition
    case accessibility
    case screenRecording

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .microphone: String(localized: "Microphone")
        case .speechRecognition: String(localized: "Speech Recognition")
        case .accessibility: String(localized: "Accessibility")
        case .screenRecording: String(localized: "Screen Recording")
        }
    }

    var description: String {
        switch self {
        case .microphone:
            String(localized: "Required for voice input")
        case .speechRecognition:
            String(localized: "Required for transcribing speech to text")
        case .accessibility:
            String(localized: "Required for reading screen context and text injection")
        case .screenRecording:
            String(localized: "Optional - enables screen context capture as fallback")
        }
    }

    var systemImage: String {
        switch self {
        case .microphone: "mic.fill"
        case .speechRecognition: "waveform"
        case .accessibility: "accessibility"
        case .screenRecording: "rectangle.on.rectangle"
        }
    }

    var isRequired: Bool {
        switch self {
        case .microphone, .speechRecognition, .accessibility: true
        case .screenRecording: false
        }
    }

    var systemSettingsURL: URL? {
        switch self {
        case .microphone:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .speechRecognition:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .screenRecording:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
    }
}

@Observable
final class PermissionManager {
    var microphoneStatus: PermissionStatus = .notDetermined
    var speechRecognitionStatus: PermissionStatus = .notDetermined
    var accessibilityStatus: PermissionStatus = .denied
    var screenRecordingStatus: PermissionStatus = .denied

    private var pollingTimer: Timer?

    var allRequiredGranted: Bool {
        microphoneStatus == .granted
            && speechRecognitionStatus == .granted
            && accessibilityStatus == .granted
    }

    init() {
        refreshAll()
    }

    /// Start periodic polling to detect permission changes made in System Settings.
    func startPolling() {
        stopPolling()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshAll()
        }
    }

    /// Stop periodic polling.
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    func status(for type: PermissionType) -> PermissionStatus {
        switch type {
        case .microphone: microphoneStatus
        case .speechRecognition: speechRecognitionStatus
        case .accessibility: accessibilityStatus
        case .screenRecording: screenRecordingStatus
        }
    }

    func refreshAll() {
        refreshMicrophone()
        refreshSpeechRecognition()
        refreshAccessibility()
        refreshScreenRecording()
    }

    // MARK: - Microphone

    private func refreshMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: microphoneStatus = .granted
        case .denied: microphoneStatus = .denied
        case .restricted: microphoneStatus = .restricted
        case .notDetermined: microphoneStatus = .notDetermined
        @unknown default: microphoneStatus = .notDetermined
        }
    }

    func requestMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneStatus = granted ? .granted : .denied
    }

    // MARK: - Speech Recognition

    private func refreshSpeechRecognition() {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: speechRecognitionStatus = .granted
        case .denied: speechRecognitionStatus = .denied
        case .restricted: speechRecognitionStatus = .restricted
        case .notDetermined: speechRecognitionStatus = .notDetermined
        @unknown default: speechRecognitionStatus = .notDetermined
        }
    }

    func requestSpeechRecognition() async {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        switch status {
        case .authorized: speechRecognitionStatus = .granted
        case .denied: speechRecognitionStatus = .denied
        case .restricted: speechRecognitionStatus = .restricted
        case .notDetermined: speechRecognitionStatus = .notDetermined
        @unknown default: speechRecognitionStatus = .notDetermined
        }
    }

    // MARK: - Accessibility

    private func refreshAccessibility() {
        let trusted = AXIsProcessTrusted()
        accessibilityStatus = trusted ? .granted : .denied
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        refreshAccessibility()
    }

    // MARK: - Screen Recording

    private func refreshScreenRecording() {
        let granted = CGPreflightScreenCaptureAccess()
        screenRecordingStatus = granted ? .granted : .denied
    }

    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
        refreshScreenRecording()
    }

    // MARK: - Open Settings

    func openSystemSettings(for type: PermissionType) {
        guard let url = type.systemSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    func request(for type: PermissionType) async {
        switch type {
        case .microphone:
            await requestMicrophone()
        case .speechRecognition:
            await requestSpeechRecognition()
        case .accessibility:
            requestAccessibility()
        case .screenRecording:
            requestScreenRecording()
        }
    }

    func canRequest(for type: PermissionType) -> Bool {
        let s = status(for: type)
        switch type {
        case .microphone, .speechRecognition:
            return s == .notDetermined
        case .accessibility, .screenRecording:
            return s == .denied
        }
    }
}
