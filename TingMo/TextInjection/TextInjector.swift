import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Injects text into the focused field by writing to the pasteboard,
/// synthesizing Cmd+V, and restoring the original pasteboard contents
/// after a configurable delay.
///
/// The restore delay gives the target app time to consume the paste
/// before we swap the clipboard back. 500 ms is a reasonable default;
/// users who rely on clipboard managers or slow apps may want longer.
final class TextInjector {
    static let shared = TextInjector()

    private static let restoreDelayKey = "TextInjection.restoreDelay"
    private static let defaultRestoreDelay: TimeInterval = 0.5

    private init() {}

    /// Delay before the original pasteboard is restored, in seconds.
    var restoreDelay: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: Self.restoreDelayKey)
        return stored > 0 ? stored : Self.defaultRestoreDelay
    }

    func setRestoreDelay(_ seconds: TimeInterval) {
        UserDefaults.standard.set(seconds, forKey: Self.restoreDelayKey)
    }

    /// Paste `text` at the current cursor, then restore the prior pasteboard.
    ///
    /// - Throws: `TextInjectionError.emptyText` when `text` is empty or
    ///           whitespace-only; the pipeline should surface an error
    ///           via the status UI instead of pasting nothing.
    func inject(_ text: String) async throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TextInjectionError.emptyText
        }

        // AXIsProcessTrusted drives whether synthesized key events reach
        // other apps. If the user hasn't granted Accessibility access, the
        // Cmd+V we post to the HID tap is silently dropped and the paste
        // never lands — surface this as an error instead of pretending the
        // inject succeeded.
        if !AXIsProcessTrusted() {
            NSLog("[TingMo][Inject] aborted — Accessibility permission not granted")
            throw TextInjectionError.accessibilityNotGranted
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(from: pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            snapshot.restore(to: pasteboard)
            throw TextInjectionError.pasteboardWriteFailed
        }

        try synthesizeCmdV()

        try? await Task.sleep(for: .seconds(restoreDelay))
        snapshot.restore(to: pasteboard)
    }

    // MARK: - Cmd+V synthesis

    private func synthesizeCmdV() throws {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw TextInjectionError.syntheticEventFailed
        }

        let vKeyCode = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else {
            throw TextInjectionError.syntheticEventFailed
        }

        down.flags = .maskCommand
        up.flags = .maskCommand

        // Post to the HID event tap so the event appears system-wide,
        // matching a real keystroke.
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

enum TextInjectionError: Error, LocalizedError {
    case emptyText
    case pasteboardWriteFailed
    case syntheticEventFailed
    case accessibilityNotGranted

    var errorDescription: String? {
        switch self {
        case .emptyText: "No text to paste."
        case .pasteboardWriteFailed: "Failed to write text to the clipboard."
        case .syntheticEventFailed: "Failed to synthesize the paste keystroke."
        case .accessibilityNotGranted:
            String(localized: "Accessibility permission is required to paste. Enable TingMo in System Settings → Privacy & Security → Accessibility.")
        }
    }
}

// MARK: - Pasteboard snapshot

/// Snapshot of every pasteboard item's data for every type, so we can
/// restore the clipboard byte-for-byte after a paste.
private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(from pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    entry[type] = data
                }
            }
            return entry
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let newItems: [NSPasteboardItem] = items.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            return item
        }
        if !newItems.isEmpty {
            pasteboard.writeObjects(newItems)
        }
    }
}
