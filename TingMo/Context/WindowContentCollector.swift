import AppKit
import ApplicationServices
import Foundation

struct WindowContentCollector {
    /// Hard cap for the AX-tree traversal accumulator. This is a safety brake against
    /// pathological windows (e.g. a terminal with 10MB of scrollback) — not an output
    /// budget. Output budgeting is the aggregator's job (`ContextDefaults`).
    private static let traversalCharBudget = 50_000

    func collect(targetPID: pid_t? = nil) -> String? {
        let trusted = AXIsProcessTrusted()
        NSLog("[TingMo][WindowContent] AXIsProcessTrusted=%@", trusted ? "true" : "false")
        guard trusted else { return nil }

        let resolvedPID: pid_t
        if let targetPID {
            resolvedPID = targetPID
        } else if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            resolvedPID = pid
        } else {
            NSLog("[TingMo][WindowContent] No frontmost application")
            return nil
        }
        let pid = resolvedPID

        let appElement = AXUIElementCreateApplication(pid)

        var focusedElementValue: CFTypeRef?
        let focusedElementErr = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)
        var focusedWindowValue: CFTypeRef?
        let focusedWindowErr = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowValue)
        NSLog("[TingMo][WindowContent] AXErr focusedElement=%d focusedWindow=%d", focusedElementErr.rawValue, focusedWindowErr.rawValue)

        let focusedElement = appElement.axElementAttribute(kAXFocusedUIElementAttribute as CFString)
        let focusedWindow = appElement.axElementAttribute(kAXFocusedWindowAttribute as CFString)
            ?? focusedElement?.axElementAttribute(kAXWindowAttribute as CFString)

        NSLog("[TingMo][WindowContent] pid=%d focusedElement=%@ focusedWindow=%@",
              pid, focusedElement.debugDescription, focusedWindow.debugDescription)

        var visited = ObjectIdentifierSet()
        var texts: [String] = []

        if let focusedWindow {
            traverse(element: focusedWindow, visited: &visited, texts: &texts, cap: Self.traversalCharBudget)
        } else if let windows = appElement.axWindowList(), let first = windows.first {
            NSLog("[TingMo][WindowContent] Falling back to first of %d windows", windows.count)
            traverse(element: first, visited: &visited, texts: &texts, cap: Self.traversalCharBudget)
        } else {
            NSLog("[TingMo][WindowContent] No focused window and no windows in window list for pid=%d", pid)
            return nil
        }

        let joined = texts.joined(separator: "\n")
        let cleaned = ContextTextCleaner.clean(joined)
        let info = ContextTextCleaner.informationalCharCount(cleaned)
        NSLog("[TingMo][WindowContent] raw=%d elements=%d cleaned=%d info=%d", joined.count, texts.count, cleaned.count, info)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func traverse(
        element: AXUIElement,
        visited: inout ObjectIdentifierSet,
        texts: inout [String],
        cap: Int
    ) {
        let id = ObjectIdentifier(element as AnyObject)
        guard visited.insert(id) else { return }

        if let value = element.axStringAttribute(kAXValueAttribute as CFString) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed.count > 1 {
                texts.append(trimmed)
            }
        }

        guard let children = element.axChildren else { return }

        for child in children {
            let currentUsed = texts.reduce(0) { $0 + $1.count }
            guard currentUsed < cap else { break }
            traverse(element: child, visited: &visited, texts: &texts, cap: cap)
        }
    }
}

private struct ObjectIdentifierSet {
    private var storage = Set<ObjectIdentifier>()

    mutating func insert(_ id: ObjectIdentifier) -> Bool {
        storage.insert(id).inserted
    }
}

private extension AXUIElement {
    func axElementAttribute(_ attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute, &value) == .success else { return nil }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func axStringAttribute(_ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute, &value) == .success else { return nil }
        return value as? String
    }

    var axChildren: [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, kAXChildrenAttribute as CFString, &value) == .success else {
            return nil
        }
        guard let array = value as? [AXUIElement] else { return nil }
        return array
    }

    func axWindowList() -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, kAXWindowsAttribute as CFString, &value) == .success else {
            return nil
        }
        guard let array = value as? [AXUIElement] else { return nil }
        return array
    }
}
