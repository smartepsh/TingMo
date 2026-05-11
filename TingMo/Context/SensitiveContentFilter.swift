import Foundation

/// Filters context text before it is handed to the LLM. The goal is to never
/// leak credentials/PII into the prompt — false negatives are acceptable
/// (context is just a vocabulary hint for correction), but a false positive
/// is preferable to a leak.
///
/// Rules are intentionally precise (structured patterns + assignment forms)
/// rather than broad keyword matching, so that decisions are explainable and
/// easy to verify with fixtures.
enum SensitiveContentFilter {
    enum Decision: Equatable {
        case keep
        case drop(reason: String)
        case redact(text: String, reason: String)
    }

    static func evaluate(_ text: String) -> Decision {
        if text.isEmpty { return .keep }

        for rule in dropRules {
            if rule.regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                return .drop(reason: rule.name)
            }
        }

        if containsLuhnCreditCard(text) {
            return .drop(reason: "credit-card")
        }

        if let redacted = redactAssignments(text) {
            return .redact(text: redacted.text, reason: redacted.reason)
        }

        return .keep
    }

    // MARK: - Drop rules

    private struct DropRule {
        let name: String
        let regex: NSRegularExpression
    }

    private static let dropRules: [DropRule] = [
        rule("private-key", #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#),
        rule("aws-access-key", #"\bAKIA[0-9A-Z]{16}\b"#),
        rule("slack-token", #"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"#),
        rule("github-token", #"\bgh[pousr]_[A-Za-z0-9]{36,}\b"#),
        rule("openai-style-key", #"\bsk-[A-Za-z0-9_-]{20,}\b"#),
        rule("jwt", #"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#),
    ]

    private static func rule(_ name: String, _ pattern: String) -> DropRule {
        // Patterns are compile-time constants; force-unwrap is safe and a
        // failure here would be a programmer error caught immediately.
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        return DropRule(name: name, regex: regex)
    }

    // MARK: - Credit card (Luhn)

    private static let creditCardCandidate = try! NSRegularExpression(
        pattern: #"\b(?:\d[ -]?){12,18}\d\b"#,
        options: []
    )

    private static func containsLuhnCreditCard(_ text: String) -> Bool {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        var found = false
        creditCardCandidate.enumerateMatches(in: text, options: [], range: range) { match, _, stop in
            guard let match else { return }
            let candidate = nsText.substring(with: match.range)
            let digits = candidate.unicodeScalars.filter { ("0"..."9").contains(Character($0)) }
            let digitString = String(String.UnicodeScalarView(digits))
            if digitString.count >= 13, digitString.count <= 19, luhnValid(digitString) {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    private static func luhnValid(_ digits: String) -> Bool {
        var sum = 0
        var alt = false
        for ch in digits.reversed() {
            guard let d = ch.wholeNumberValue else { return false }
            var n = d
            if alt {
                n *= 2
                if n > 9 { n -= 9 }
            }
            sum += n
            alt.toggle()
        }
        return sum % 10 == 0
    }

    // MARK: - Assignment-form redaction

    /// Matches `keyword <sep> value` where keyword is one of the sensitive
    /// names, sep is `:` or `=` (optionally surrounded by spaces, optionally
    /// with quotes around the value). Only the assignment form triggers — a
    /// bare mention of "password" in prose is left alone.
    private static let assignmentRegex = try! NSRegularExpression(
        pattern: #"(?i)\b(password|passwd|passcode|secret|api[_-]?key|access[_-]?token|auth[_-]?token|token)\b\s*[:=]\s*["']?([^\s"',;]{4,})["']?"#,
        options: []
    )

    private static func redactAssignments(_ text: String) -> (text: String, reason: String)? {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = assignmentRegex.matches(in: text, options: [], range: range)
        guard !matches.isEmpty else { return nil }

        var result = text
        // Replace from the end so earlier ranges stay valid.
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3, let valueRange = Range(match.range(at: 2), in: result) else { continue }
            result.replaceSubrange(valueRange, with: "***")
        }
        return (result, "assignment-redacted")
    }
}
