import AppKit
import ApplicationServices
import Foundation

/// Captures the small, low-latency context set used by M3.
struct BasicContextCollector {
    func collect() -> [LLMContextItem] {
        var items: [LLMContextItem] = []

        let frontmostApp = NSWorkspace.shared.frontmostApplication
        if let appName = frontmostApp?.localizedName,
           !appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(LLMContextItem(kind: .applicationName, text: appName, priority: 40))
        }

        if AXIsProcessTrusted(), let pid = frontmostApp?.processIdentifier {
            let appElement = AXUIElementCreateApplication(pid)
            let focusedElement = appElement.axElementAttribute(kAXFocusedUIElementAttribute as CFString)
            let focusedWindow = appElement.axElementAttribute(kAXFocusedWindowAttribute as CFString)
                ?? focusedElement?.axElementAttribute(kAXWindowAttribute as CFString)

            if let title = focusedWindow?.axStringAttribute(kAXTitleAttribute as CFString) {
                items.append(LLMContextItem(kind: .windowTitle, text: title, priority: 30))
            }

            if let focusedElement, !focusedElement.isSensitiveTextField {
                if let selectedText = focusedElement.axStringAttribute(kAXSelectedTextAttribute as CFString) {
                    items.append(LLMContextItem(kind: .selectedText, text: selectedText, priority: 10))
                }
                if let inputText = focusedElement.axStringAttribute(kAXValueAttribute as CFString) {
                    items.append(LLMContextItem(kind: .inputText, text: inputText, priority: 20))
                }
            }
        }

        if let clipboard = NSPasteboard.general.string(forType: .string),
           !clipboard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(LLMContextItem(
                kind: .clipboard,
                text: clipboard,
                priority: 50,
                isSensitive: Self.looksSensitive(clipboard)
            ))
        }

        return deduplicated(items)
    }

    private func deduplicated(_ items: [LLMContextItem]) -> [LLMContextItem] {
        var seen = Set<String>()
        return items.compactMap { item in
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let key = "\(item.kind.rawValue):\(text)"
            guard seen.insert(key).inserted else { return nil }
            var normalized = item
            normalized.text = text
            return normalized
        }
    }

    private static func looksSensitive(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let secretWords = ["password", "passwd", "secret", "api_key", "apikey", "token", "bearer "]
        if secretWords.contains(where: { lowercased.contains($0) }) {
            return true
        }

        let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if compact.count >= 32,
           compact.range(of: #"^[A-Za-z0-9_\-\.=]+$"#, options: .regularExpression) != nil {
            return true
        }

        return false
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
