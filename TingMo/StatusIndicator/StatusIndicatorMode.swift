import AppKit
import Foundation

enum StatusIndicatorMode: String, CaseIterable, Identifiable, Codable {
    case notch
    case topCenter
    case floatingWindow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notch: String(localized: "Notch")
        case .topCenter: String(localized: "Top Center")
        case .floatingWindow: String(localized: "Floating Window")
        }
    }

    var description: String {
        switch self {
        case .notch: String(localized: "Embed in the camera notch area")
        case .topCenter: String(localized: "Show at top center of screen")
        case .floatingWindow: String(localized: "Floating window with transcription preview")
        }
    }

    /// Whether any connected screen has a notch (for settings UI hint).
    static var anyScreenHasNotch: Bool {
        NSScreen.screens.contains { screenHasNotch($0) }
    }

    /// Check if a specific screen has a notch.
    static func screenHasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
    }

    /// Resolve the effective mode for a given screen.
    func effective(on screen: NSScreen) -> StatusIndicatorMode {
        if self == .notch && !Self.screenHasNotch(screen) {
            return .topCenter
        }
        return self
    }
}
