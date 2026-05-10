import AppKit
import Foundation
import Observation

struct ContextSourceConfig: Codable, Equatable, Identifiable {
    var kind: LLMContextItem.Kind
    var enabled: Bool
    var priority: Int
    /// Cap for this source as a percentage of `maxTotalCharacters`. Higher-priority
    /// sources fill first; whatever they don't use stays in the shared budget for
    /// lower-priority sources. Caps may sum above 100% — the total budget is the
    /// hard ceiling.
    var maxBudgetPercent: Int

    var id: LLMContextItem.Kind { kind }
}

/// Single source of truth for context-collection tuning constants.
/// Keep all numeric defaults here so future adjustments don't require UI changes.
enum ContextDefaults {
    static let maxTotalCharacters = 4_000
    static let ocrTriggerThreshold = 50

    static let sources: [ContextSourceConfig] = [
        ContextSourceConfig(kind: .selectedText, enabled: true, priority: 10, maxBudgetPercent: 50),
        ContextSourceConfig(kind: .inputText, enabled: true, priority: 20, maxBudgetPercent: 50),
        ContextSourceConfig(kind: .windowContent, enabled: true, priority: 30, maxBudgetPercent: 60),
        ContextSourceConfig(kind: .windowTitle, enabled: true, priority: 40, maxBudgetPercent: 10),
        ContextSourceConfig(kind: .applicationName, enabled: true, priority: 50, maxBudgetPercent: 5),
        ContextSourceConfig(kind: .screenshotOCR, enabled: false, priority: 60, maxBudgetPercent: 60),
    ]
}

@Observable
final class ContextSettingsStore {
    private static let storageKey = "ContextSettingsStore.sources"
    private static let ocrTriggerThresholdKey = "ContextSettingsStore.ocrTriggerThreshold"
    private static let debugLoggingEnabledKey = "ContextSettingsStore.debugLoggingEnabled"

    var sources: [ContextSourceConfig] {
        didSet { save() }
    }

    var ocrTriggerThreshold: Int {
        didSet { UserDefaults.standard.set(ocrTriggerThreshold, forKey: Self.ocrTriggerThresholdKey) }
    }

    var debugLoggingEnabled: Bool {
        didSet { UserDefaults.standard.set(debugLoggingEnabled, forKey: Self.debugLoggingEnabledKey) }
    }

    var maxTotalCharacters: Int { ContextDefaults.maxTotalCharacters }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([ContextSourceConfig].self, from: data) {
            sources = Self.mergeDefaults(with: decoded)
        } else {
            sources = Self.defaultSources
        }

        let savedThreshold = UserDefaults.standard.integer(forKey: Self.ocrTriggerThresholdKey)
        ocrTriggerThreshold = savedThreshold > 0 ? savedThreshold : ContextDefaults.ocrTriggerThreshold

        debugLoggingEnabled = UserDefaults.standard.bool(forKey: Self.debugLoggingEnabledKey)
    }

    func config(for kind: LLMContextItem.Kind) -> ContextSourceConfig {
        sources.first { $0.kind == kind }
            ?? Self.defaultSources.first { $0.kind == kind }
            ?? ContextSourceConfig(kind: kind, enabled: false, priority: 100, maxBudgetPercent: 0)
    }

    func update(_ source: ContextSourceConfig) {
        guard let index = sources.firstIndex(where: { $0.kind == source.kind }) else {
            sources.append(source)
            return
        }
        sources[index] = source
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sources) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    /// Keep the user's `enabled` choice from persisted state, but always take
    /// `priority` / `maxBudgetPercent` from `ContextDefaults` — those are no longer
    /// user-tunable and may be adjusted between releases.
    private static func mergeDefaults(with saved: [ContextSourceConfig]) -> [ContextSourceConfig] {
        defaultSources.map { defaultSource in
            guard let savedSource = saved.first(where: { $0.kind == defaultSource.kind }) else {
                return defaultSource
            }
            var merged = defaultSource
            merged.enabled = savedSource.enabled
            return merged
        }
    }

    static var defaultSources: [ContextSourceConfig] { ContextDefaults.sources }
}

struct ContextAggregator {
    var collector: BasicContextCollector
    var screenshotOCRCollector: ScreenshotOCRCollector
    var settings: ContextSettingsStore
    var skipOCR: Bool

    init(
        collector: BasicContextCollector = BasicContextCollector(),
        screenshotOCRCollector: ScreenshotOCRCollector = ScreenshotOCRCollector(),
        settings: ContextSettingsStore,
        skipOCR: Bool = false
    ) {
        self.collector = collector
        self.screenshotOCRCollector = screenshotOCRCollector
        self.settings = settings
        self.skipOCR = skipOCR
    }

    func collect(snapshot: [LLMContextItem]? = nil, targetPID: pid_t? = nil, targetAppName: String? = nil) -> [LLMContextItem] {
        var rawCollected: [LLMContextItem]
        if let snapshot {
            rawCollected = snapshot
        } else {
            rawCollected = collector.collect(targetPID: targetPID, targetAppName: targetAppName)
        }

        let ocrConfig = settings.config(for: .screenshotOCR)
        if ocrConfig.enabled && !skipOCR {
            let windowContentInfo = rawCollected
                .filter { $0.kind == .windowContent }
                .reduce(0) { $0 + ContextTextCleaner.informationalCharCount($1.text) }

            if windowContentInfo < settings.ocrTriggerThreshold {
                if let ocrText = screenshotOCRCollector.collect() {
                    rawCollected.append(LLMContextItem(kind: .screenshotOCR, text: ocrText, priority: ocrConfig.priority))
                }
            }
        }

        let filtered = rawCollected.compactMap { item -> LLMContextItem? in
            let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if item.isSensitive { return nil }
            let config = settings.config(for: item.kind)
            if !config.enabled { return nil }
            if trimmed.isEmpty { return nil }
            var normalized = item
            normalized.text = trimmed
            return normalized
        }

        var itemsByKind: [LLMContextItem.Kind: [LLMContextItem]] = [:]
        for item in filtered {
            itemsByKind[item.kind, default: []].append(item)
        }

        let totalBudget = settings.maxTotalCharacters
        var remainingBudget = totalBudget
        var result: [LLMContextItem] = []

        // Higher-priority sources fill first. Each source can consume at most
        // its `maxBudgetPercent` of the total budget, but never more than what
        // remains after higher-priority sources have taken their share.
        let orderedSources = settings.sources
            .filter { $0.enabled }
            .sorted { $0.priority < $1.priority }

        for source in orderedSources {
            guard remainingBudget > 0 else { break }
            guard let items = itemsByKind[source.kind], !items.isEmpty else { continue }

            let sourceCap = max(0, totalBudget * source.maxBudgetPercent / 100)
            let sourceBudget = min(sourceCap, remainingBudget)
            guard sourceBudget > 0 else { continue }

            var sourceUsed = 0
            for item in items {
                let available = sourceBudget - sourceUsed
                guard available > 0 else { break }
                let truncatedText = String(item.text.prefix(available))
                var normalized = item
                normalized.priority = source.priority
                normalized.text = truncatedText
                result.append(normalized)
                sourceUsed += truncatedText.count
            }

            remainingBudget -= sourceUsed
        }

        return result
    }
}

enum ContextTextCleaner {
    /// Aggressively normalize AX-derived text for use as an LLM "known-vocabulary" hint.
    /// Layout fidelity is not preserved; the goal is to maximize informational density.
    ///
    /// Pipeline:
    /// - Drop control characters (incl. NUL filler from terminal AX trees), keep \n \t.
    /// - Per line: collapse internal whitespace runs to a single space, then trim.
    /// - Drop "decoration-only" lines (those whose info chars — letters/digits/CJK —
    ///   make up less than a small fraction of the line, or whose info-char count is < 2).
    /// - Collapse consecutive blank lines into one blank line.
    static func clean(_ raw: String) -> String {
        let stripped = stripControlChars(raw)
        let lines = stripped.split(separator: "\n", omittingEmptySubsequences: false)

        var output: [String] = []
        var lastWasBlank = false
        for line in lines {
            let collapsed = collapseInternalWhitespace(String(line))
            let trimmed = collapsed.trimmingCharacters(in: .whitespaces)

            if isDecorationOnly(trimmed) {
                if !output.isEmpty && !lastWasBlank {
                    output.append("")
                    lastWasBlank = true
                }
                continue
            }

            output.append(trimmed)
            lastWasBlank = false
        }

        while output.last?.isEmpty == true { output.removeLast() }
        return output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Count of "informational" characters in cleaned text — letters, digits, CJK ranges.
    /// Used by callers (e.g. OCR trigger) to judge whether the text carries real signal.
    static func informationalCharCount(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { acc, s in
            acc + (isInfoScalar(s) ? 1 : 0)
        }
    }

    private static func stripControlChars(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        out.reserveCapacity(s.unicodeScalars.count)
        for scalar in s.unicodeScalars {
            let v = scalar.value
            if v == 0x09 || v == 0x0A {
                out.append(scalar)
            } else if v < 0x20 || v == 0x7F {
                continue
            } else {
                out.append(scalar)
            }
        }
        return String(out)
    }

    private static func collapseInternalWhitespace(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var inSpace = false
        for scalar in s.unicodeScalars {
            let isWs = scalar.value == 0x20 || scalar.value == 0x09
            if isWs {
                if !inSpace {
                    out.unicodeScalars.append(Unicode.Scalar(0x20)!)
                    inSpace = true
                }
            } else {
                out.unicodeScalars.append(scalar)
                inSpace = false
            }
        }
        return out
    }

    private static func isDecorationOnly(_ line: String) -> Bool {
        if line.isEmpty { return true }
        var info = 0
        var total = 0
        for scalar in line.unicodeScalars {
            if scalar.value == 0x20 { continue }
            total += 1
            if isInfoScalar(scalar) { info += 1 }
        }
        if total == 0 { return true }
        if info < 2 { return true }
        // If less than ~25% of non-space chars are informational, treat as decoration.
        return info * 4 < total
    }

    private static func isInfoScalar(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        if (0x30...0x39).contains(v) { return true } // 0-9
        if (0x41...0x5A).contains(v) { return true } // A-Z
        if (0x61...0x7A).contains(v) { return true } // a-z
        // Common CJK ranges (Han, Hiragana, Katakana, Hangul, fullwidth letters/digits).
        if (0x3040...0x30FF).contains(v) { return true }
        if (0x3400...0x4DBF).contains(v) { return true }
        if (0x4E00...0x9FFF).contains(v) { return true }
        if (0xAC00...0xD7AF).contains(v) { return true }
        if (0xFF10...0xFF19).contains(v) { return true } // fullwidth digits
        if (0xFF21...0xFF3A).contains(v) { return true } // fullwidth A-Z
        if (0xFF41...0xFF5A).contains(v) { return true } // fullwidth a-z
        if (0x20000...0x2FFFF).contains(v) { return true } // CJK Ext B-F
        return false
    }
}

enum ContextDebugLogger {
    static func log(_ context: [LLMContextItem], budget: Int? = nil) {
        NSLog("[TingMo][Context] ---- context dump ----")
        if context.isEmpty {
            NSLog("[TingMo][Context] (empty)")
        } else {
            var totalChars = 0
            for item in context {
                let visualized = Self.visualize(item.text)
                let stats = Self.charStats(item.text)
                NSLog("[TingMo][Context] [%@] priority=%d chars=%d %@: %@",
                      item.kind.rawValue, item.priority, item.text.count, stats, visualized)
                totalChars += item.text.count
            }
            if let budget {
                NSLog("[TingMo][Context] total: %d/%d chars", totalChars, budget)
            }
        }
        NSLog("[TingMo][Context] ---- end ----")
    }

    private static func visualize(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if v == 0x0A { out += "\\n" }
            else if v == 0x09 { out += "\\t" }
            else if v == 0x20 { out += "·" }
            else if v < 0x20 || v == 0x7F { out += String(format: "\\x%02x", v) }
            else { out.unicodeScalars.append(scalar) }
        }
        return out
    }

    private static func charStats(_ text: String) -> String {
        var space = 0, newline = 0, control = 0, printable = 0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if v == 0x20 { space += 1 }
            else if v == 0x0A { newline += 1 }
            else if v < 0x20 || v == 0x7F { control += 1 }
            else { printable += 1 }
        }
        return "(sp=\(space) nl=\(newline) ctl=\(control) prn=\(printable))"
    }

}
