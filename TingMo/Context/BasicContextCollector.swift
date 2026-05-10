import AppKit
import ApplicationServices
import Foundation

/// Captures the small, low-latency context set used by M3.
struct BasicContextCollector {
    var windowContentCollector: WindowContentCollector

    init(windowContentCollector: WindowContentCollector = WindowContentCollector()) {
        self.windowContentCollector = windowContentCollector
    }

    func collect(targetPID: pid_t? = nil, targetAppName: String? = nil) -> [LLMContextItem] {
        var items: [LLMContextItem] = []

        let runningApp: NSRunningApplication?
        if let targetPID {
            runningApp = NSRunningApplication(processIdentifier: targetPID)
        } else {
            runningApp = NSWorkspace.shared.frontmostApplication
        }
        let appName = targetAppName ?? runningApp?.localizedName
        if let appName {
            let cleaned = ContextTextCleaner.clean(appName)
            if !cleaned.isEmpty {
                items.append(LLMContextItem(kind: .applicationName, text: cleaned, priority: 40))
            }
        }

        if AXIsProcessTrusted(), let pid = targetPID ?? runningApp?.processIdentifier {
            NSLog("[TingMo][BasicContext] pid=%d appName=%@", pid, appName ?? "nil")
            let appElement = AXUIElementCreateApplication(pid)
            let focusedElement = appElement.axElementAttribute(kAXFocusedUIElementAttribute as CFString)
            let focusedWindow = appElement.axElementAttribute(kAXFocusedWindowAttribute as CFString)
                ?? focusedElement?.axElementAttribute(kAXWindowAttribute as CFString)
            NSLog("[TingMo][BasicContext] focusedElement=%@ focusedWindow=%@", focusedElement.debugDescription, focusedWindow.debugDescription)

            if let title = focusedWindow?.axStringAttribute(kAXTitleAttribute as CFString) {
                let cleaned = ContextTextCleaner.clean(title)
                if !cleaned.isEmpty {
                    items.append(LLMContextItem(kind: .windowTitle, text: cleaned, priority: 30))
                }
            }

            if let focusedElement, !focusedElement.isSensitiveTextField {
                if let selectedText = focusedElement.axStringAttribute(kAXSelectedTextAttribute as CFString) {
                    let cleaned = ContextTextCleaner.clean(selectedText)
                    if !cleaned.isEmpty {
                        items.append(LLMContextItem(kind: .selectedText, text: cleaned, priority: 10))
                    }
                }
                if let inputText = focusedElement.axStringAttribute(kAXValueAttribute as CFString) {
                    let cleaned = ContextTextCleaner.clean(inputText)
                    if !cleaned.isEmpty {
                        items.append(LLMContextItem(kind: .inputText, text: cleaned, priority: 20))
                    }
                }
            }
        }

        if let windowContent = windowContentCollector.collect(targetPID: targetPID) {
            items.append(LLMContextItem(kind: .windowContent, text: windowContent, priority: 15))
        }

        return deduplicated(items)
    }

    private func deduplicated(_ items: [LLMContextItem]) -> [LLMContextItem] {
        var seen = Set<String>()
        var normalizedItems: [LLMContextItem] = []
        for item in items {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let key = "\(item.kind.rawValue):\(text)"
            guard seen.insert(key).inserted else { continue }
            var normalized = item
            normalized.text = text
            normalizedItems.append(normalized)
        }

        return collapseSelectedAndInputText(normalizedItems)
    }

    /// Drop `inputText` when it is fully covered by `selectedText` (e.g. user selected the
    /// entire field, or the focused element exposes the same value via both attributes).
    /// When `inputText` strictly contains `selectedText`, keep both — the selection still
    /// carries distinct "what the user is focused on" signal.
    private func collapseSelectedAndInputText(_ items: [LLMContextItem]) -> [LLMContextItem] {
        guard let selected = items.first(where: { $0.kind == .selectedText })?.text,
              let input = items.first(where: { $0.kind == .inputText })?.text else {
            return items
        }

        if selected == input || selected.contains(input) {
            return items.filter { $0.kind != .inputText }
        }
        return items
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

    var isSensitiveTextField: Bool {
        let role = axStringAttribute(kAXRoleAttribute as CFString)?.lowercased() ?? ""
        let subrole = axStringAttribute(kAXSubroleAttribute as CFString)?.lowercased() ?? ""
        if subrole.contains("secure") || subrole.contains("password") {
            return true
        }

        let metadata = [
            axStringAttribute(kAXDescriptionAttribute as CFString),
            axStringAttribute(kAXTitleAttribute as CFString),
            axStringAttribute("AXPlaceholderValue" as CFString),
            axStringAttribute("AXIdentifier" as CFString),
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        return role.contains("secure")
            || metadata.contains("password")
            || metadata.contains("passcode")
            || metadata.contains("secret")
            || metadata.contains("token")
    }
}
