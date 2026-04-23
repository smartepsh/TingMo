import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case microphone
    case accessibility
    case screenRecording
    case engineDownload
    case hotkeySetup
    case completion

    var id: Int { rawValue }

    var permissionType: PermissionType? {
        switch self {
        case .microphone: .microphone
        case .accessibility: .accessibility
        case .screenRecording: .screenRecording
        default: nil
        }
    }

    var isPlaceholder: Bool {
        switch self {
        case .engineDownload, .hotkeySetup: true
        default: false
        }
    }

    var placeholderIcon: String {
        switch self {
        case .engineDownload: "arrow.down.circle"
        case .hotkeySetup: "keyboard"
        default: ""
        }
    }

    var placeholderTitle: String {
        switch self {
        case .engineDownload: String(localized: "Speech Engine")
        case .hotkeySetup: String(localized: "Hotkey Setup")
        default: ""
        }
    }
}
