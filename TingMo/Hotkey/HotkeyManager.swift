import Carbon.HIToolbox
import Cocoa
import Combine
import Foundation
import Observation

/// Represents a hotkey combination.
struct HotkeyCombination: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int

    static let optionD = HotkeyCombination(keyCode: kVK_ANSI_D, modifiers: Int(NSEvent.ModifierFlags.option.rawValue))

    var displayName: String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        if flags.contains(.function) { parts.append("fn") }
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        let keyName = KeyCodeNames.name(for: keyCode)
        // Don't duplicate modifier name if it's a modifier-only hotkey
        if !KeyCodeNames.isModifierKeyCode(keyCode) {
            parts.append(keyName)
        } else if parts.isEmpty {
            parts.append(keyName)
        }
        return parts.joined()
    }
}

/// Hotkey recording modes.
enum RecordingMode {
    case toggle
    case pressToRecord
}

/// Events emitted by the hotkey system.
enum HotkeyEvent {
    case startRecording
    case stopRecording(mode: RecordingMode)
    case cancelRecording
}

/// Manages global hotkey listening via CGEvent tap.
@Observable
final class HotkeyManager {
    /// The current hotkey combination (persisted).
    var hotkey: HotkeyCombination {
        didSet { persistHotkey(); reinstallTap() }
    }

    /// Application bundle IDs to exclude from hotkey interception.
    var excludedApps: [String] {
        didSet { persistExcludedApps() }
    }

    /// Short-press threshold in seconds.
    let shortPressThreshold: TimeInterval = 0.3

    /// Event publisher for hotkey actions.
    let eventPublisher = PassthroughSubject<HotkeyEvent, Never>()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyDownTime: Date?
    private var isToggleRecording = false

    private static let hotkeyKey = "HotkeyManager.hotkey"
    private static let excludedAppsKey = "HotkeyManager.excludedApps"

    init() {
        // Load persisted hotkey
        if let data = UserDefaults.standard.data(forKey: Self.hotkeyKey),
           let saved = try? JSONDecoder().decode(HotkeyCombination.self, from: data)
        {
            hotkey = saved
        } else {
            hotkey = .optionD
        }

        // Load excluded apps
        excludedApps = UserDefaults.standard.stringArray(forKey: Self.excludedAppsKey) ?? []
    }

    // MARK: - Tap Management

    func start() {
        installTap()
    }

    func stop() {
        removeTap()
    }

    private func reinstallTap() {
        removeTap()
        installTap()
    }

    private func installTap() {
        guard eventTap == nil else { return }

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleEvent(proxy: proxy, type: type, event: event)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: selfPtr
        ) else {
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }

    // MARK: - Event Handling

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if disabled by the system
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        // Handle flagsChanged for modifier-only hotkeys
        if type == .flagsChanged {
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            guard keyCode == hotkey.keyCode && matchesModifiers(flags) else {
                return Unmanaged.passRetained(event)
            }
            if isExcludedAppFocused() {
                return Unmanaged.passRetained(event)
            }
            // Treat flagsChanged press as a toggle trigger
            handleHotkeyDown()
            // Schedule a simulated "up" after threshold to support toggle mode
            DispatchQueue.main.asyncAfter(deadline: .now() + shortPressThreshold + 0.05) { [weak self] in
                self?.handleHotkeyUp()
            }
            return nil
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Check for ESC during toggle recording
        if keyCode == kVK_Escape && type == .keyDown && isToggleRecording {
            isToggleRecording = false
            keyDownTime = nil
            eventPublisher.send(.cancelRecording)
            return nil // consume the event
        }

        // Check if this is our hotkey
        guard keyCode == hotkey.keyCode && matchesModifiers(flags) else {
            return Unmanaged.passRetained(event)
        }

        // Check excluded apps
        if isExcludedAppFocused() {
            return Unmanaged.passRetained(event)
        }

        if type == .keyDown {
            handleHotkeyDown()
        } else if type == .keyUp {
            handleHotkeyUp()
        }

        return nil // consume the event
    }

    private func handleHotkeyDown() {
        guard keyDownTime == nil else { return } // ignore repeats
        keyDownTime = Date()

        if !isToggleRecording {
            // First press — start recording immediately.
            // For the second press in toggle mode, defer the decision to keyUp
            // so that both short and long second-presses stop cleanly.
            eventPublisher.send(.startRecording)
        }
    }

    private func handleHotkeyUp() {
        guard let downTime = keyDownTime else { return }
        let duration = Date().timeIntervalSince(downTime)
        keyDownTime = nil

        if isToggleRecording {
            // Release of the second press — stop toggle recording regardless of duration.
            isToggleRecording = false
            eventPublisher.send(.stopRecording(mode: .toggle))
        } else if duration < shortPressThreshold {
            // First press was short → enter toggle mode (recording already started).
            isToggleRecording = true
        } else {
            // First press was long → press-to-record, stop on release.
            eventPublisher.send(.stopRecording(mode: .pressToRecord))
        }
    }

    private func matchesModifiers(_ flags: CGEventFlags) -> Bool {
        let expected = NSEvent.ModifierFlags(rawValue: UInt(hotkey.modifiers))
        let relevant: NSEvent.ModifierFlags = [.control, .option, .shift, .command, .function]
        var actual = NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue)).intersection(relevant)
        // Strip .function for F-keys since macOS sends it implicitly
        if isFunctionKey(hotkey.keyCode) {
            actual.remove(.function)
        }
        return actual == expected.intersection(relevant)
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

    private func isExcludedAppFocused() -> Bool {
        guard !excludedApps.isEmpty,
              let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        else { return false }
        return excludedApps.contains(bundleID)
    }

    // MARK: - Persistence

    private func persistHotkey() {
        if let data = try? JSONEncoder().encode(hotkey) {
            UserDefaults.standard.set(data, forKey: Self.hotkeyKey)
        }
    }

    private func persistExcludedApps() {
        UserDefaults.standard.set(excludedApps, forKey: Self.excludedAppsKey)
    }

    // MARK: - External Triggers (CLI / AppleScript)

    func triggerToggle() {
        if isToggleRecording {
            isToggleRecording = false
            eventPublisher.send(.stopRecording(mode: .toggle))
        } else {
            isToggleRecording = true
            eventPublisher.send(.startRecording)
        }
    }

    func triggerStart() {
        guard !isToggleRecording else { return }
        isToggleRecording = true
        eventPublisher.send(.startRecording)
    }

    func triggerStop() {
        guard isToggleRecording else { return }
        isToggleRecording = false
        eventPublisher.send(.stopRecording(mode: .toggle))
    }
}
