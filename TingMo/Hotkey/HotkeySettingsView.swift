import Carbon.HIToolbox
import SwiftUI

struct HotkeySettingsView: View {
    let hotkeyManager: HotkeyManager

    @State private var isRecordingHotkey = false
    @State private var keyMonitor: Any?
    @State private var flagsMonitor: Any?
    /// Tracks the combo being built up while keys are held.
    @State private var pendingKeyCode: Int?
    @State private var pendingModifiers: NSEvent.ModifierFlags = []
    /// Display string for the combo being built.
    @State private var pendingDisplayName: String = ""
    /// Set when a rejected combo was attempted, so the hint can explain why.
    @State private var rejectionMessage: String?

    private var recordingHintText: String {
        rejectionMessage ?? String(
            localized: "Press your desired key combination, or Esc to cancel. fn on its own is supported; other modifiers need a regular key."
        )
    }

    var body: some View {
        Section {
            HStack {
                Text("Global Hotkey")
                Spacer()
                Button(recordingButtonLabel) {
                    if isRecordingHotkey {
                        cancelRecording()
                    } else {
                        startRecording()
                    }
                }
                .buttonStyle(.bordered)
            }

            if isRecordingHotkey {
                Text(recordingHintText)
                    .font(.caption)
                    .foregroundStyle(rejectionMessage == nil ? Color.secondary : Color.red)
            }
        } header: {
            Text("Hotkey")
        }

        Section {
            ForEach(hotkeyManager.excludedApps, id: \.self) { bundleID in
                HStack {
                    Text(bundleID)
                    Spacer()
                    Button(role: .destructive) {
                        hotkeyManager.excludedApps.removeAll { $0 == bundleID }
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Button(String(localized: "Add Current App")) {
                if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                   !hotkeyManager.excludedApps.contains(bundleID)
                {
                    hotkeyManager.excludedApps.append(bundleID)
                }
            }
        } header: {
            Text("Excluded Apps")
        } footer: {
            Text("The global hotkey will be ignored in these applications.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var recordingButtonLabel: String {
        if isRecordingHotkey {
            return pendingDisplayName.isEmpty ? String(localized: "Press a key...") : pendingDisplayName
        }
        return hotkeyManager.hotkey.displayName
    }

    private func startRecording() {
        isRecordingHotkey = true
        pendingKeyCode = nil
        pendingModifiers = []
        pendingDisplayName = ""
        rejectionMessage = nil

        // Monitor keyDown and keyUp — captures regular keys with or without modifiers
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            let keyCode = Int(event.keyCode)

            if event.type == .keyDown {
                if keyCode == kVK_Escape && pendingKeyCode == nil && pendingModifiers.isEmpty {
                    cancelRecording()
                    return event
                }
                // Record the non-modifier key and update display
                pendingKeyCode = keyCode
                pendingModifiers = event.modifierFlags.intersection([.control, .option, .shift, .command, .function])
                // Strip .function for F-keys since it's implicit
                if isFunctionKey(keyCode) {
                    pendingModifiers.remove(.function)
                }
                updatePendingDisplay()
                return nil
            }

            if event.type == .keyUp {
                // Key released — if we have a pending key, finalize the combo
                if pendingKeyCode != nil {
                    commitRecording()
                }
                return nil
            }

            return event
        }

        // Monitor flagsChanged — captures modifier presses/releases
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            let currentModifiers = event.modifierFlags.intersection([.control, .option, .shift, .command, .function])

            if pendingKeyCode != nil {
                // A non-modifier key is already captured; update modifiers but wait for key-up
                pendingModifiers = currentModifiers
                if isFunctionKey(pendingKeyCode!) {
                    pendingModifiers.remove(.function)
                }
                updatePendingDisplay()
                return nil
            }

            if currentModifiers.isEmpty && !pendingModifiers.isEmpty {
                // All modifiers released — commit only if this is a bare fn.
                // Other modifier-only combos (⌘, ⌥, ⌃, ⇧) would swallow the
                // key system-wide and collide with ordinary shortcuts.
                if Int(event.keyCode) == kVK_Function, pendingModifiers == [.function] {
                    commitModifierOnlyRecording(keyCode: Int(event.keyCode))
                } else {
                    rejectModifierOnlyRecording()
                }
                return nil
            }

            // Modifiers are being built up
            pendingModifiers = currentModifiers
            updatePendingDisplay()
            return nil
        }
    }

    private func updatePendingDisplay() {
        let combo = HotkeyCombination(
            keyCode: pendingKeyCode ?? -1,
            modifiers: Int(pendingModifiers.rawValue)
        )
        if pendingKeyCode != nil {
            pendingDisplayName = combo.displayName
        } else if !pendingModifiers.isEmpty {
            // Show modifier symbols only
            var parts: [String] = []
            if pendingModifiers.contains(.control) { parts.append("⌃") }
            if pendingModifiers.contains(.option) { parts.append("⌥") }
            if pendingModifiers.contains(.shift) { parts.append("⇧") }
            if pendingModifiers.contains(.command) { parts.append("⌘") }
            if pendingModifiers.contains(.function) { parts.append("fn") }
            pendingDisplayName = parts.joined() + "…"
        }
    }

    private func commitRecording() {
        guard let keyCode = pendingKeyCode else { return }
        hotkeyManager.hotkey = HotkeyCombination(
            keyCode: keyCode,
            modifiers: Int(pendingModifiers.rawValue)
        )
        stopMonitors()
    }

    /// Keep recording so the user can retry without re-entering the field.
    private func rejectModifierOnlyRecording() {
        rejectionMessage = String(
            localized: "That combination needs a regular key. Only fn works on its own."
        )
        pendingKeyCode = nil
        pendingModifiers = []
        pendingDisplayName = ""
    }

    private func commitModifierOnlyRecording(keyCode: Int) {
        hotkeyManager.hotkey = HotkeyCombination(
            keyCode: keyCode,
            modifiers: Int(pendingModifiers.rawValue)
        )
        stopMonitors()
    }

    private func cancelRecording() {
        stopMonitors()
    }

    private func stopMonitors() {
        isRecordingHotkey = false
        pendingKeyCode = nil
        pendingModifiers = []
        pendingDisplayName = ""
        rejectionMessage = nil
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
    }

    /// Returns true for F1-F20 key codes, which implicitly include .function flag.
    private func isFunctionKey(_ keyCode: Int) -> Bool {
        let fKeys: Set<Int> = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
            kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
            kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18,
            kVK_F19, kVK_F20,
        ]
        return fKeys.contains(keyCode)
    }
}
