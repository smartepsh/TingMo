import Foundation

/// Handles external triggers for dictation via CLI (XPC/URL scheme) and AppleScript.
///
/// CLI usage (via custom URL scheme):
///   open "tingmo://toggle"
///   open "tingmo://start"
///   open "tingmo://stop"
///
/// AppleScript usage:
///   tell application "TingMo" to open location "tingmo://toggle"
///
/// A full CLI binary (`tingmo`) can be added later as a helper tool
/// that simply invokes `open tingmo://<command>`.
enum ExternalTriggerService {
    /// Handle an incoming URL and dispatch to the hotkey manager.
    static func handleURL(_ url: URL, hotkeyManager: HotkeyManager) {
        guard url.scheme == "tingmo" else { return }

        switch url.host {
        case "toggle":
            hotkeyManager.triggerToggle()
        case "start":
            hotkeyManager.triggerStart()
        case "stop":
            hotkeyManager.triggerStop()
        default:
            break
        }
    }
}
