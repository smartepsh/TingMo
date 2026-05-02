import Foundation
import Observation

struct ContextSourceConfig: Codable, Equatable, Identifiable {
    var kind: LLMContextItem.Kind
    var enabled: Bool
    var priority: Int

    var id: LLMContextItem.Kind { kind }
}

@Observable
final class ContextSettingsStore {
    private static let storageKey = "ContextSettingsStore.sources"

    var sources: [ContextSourceConfig] {
        didSet { save() }
    }

    var maxCharactersPerItem: Int {
        didSet { UserDefaults.standard.set(maxCharactersPerItem, forKey: Self.maxCharactersPerItemKey) }
    }

    var maxTotalCharacters: Int {
        didSet { UserDefaults.standard.set(maxTotalCharacters, forKey: Self.maxTotalCharactersKey) }
    }

    var debugLoggingEnabled: Bool {
        didSet { UserDefaults.standard.set(debugLoggingEnabled, forKey: Self.debugLoggingEnabledKey) }
    }

    private static let maxCharactersPerItemKey = "ContextSettingsStore.maxCharactersPerItem"
    private static let maxTotalCharactersKey = "ContextSettingsStore.maxTotalCharacters"
    private static let debugLoggingEnabledKey = "ContextSettingsStore.debugLoggingEnabled"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([ContextSourceConfig].self, from: data) {
            sources = Self.mergeDefaults(with: decoded)
        } else {
            sources = Self.defaultSources
        }

        let savedPerItem = UserDefaults.standard.integer(forKey: Self.maxCharactersPerItemKey)
        maxCharactersPerItem = savedPerItem > 0 ? savedPerItem : 1_200

        let savedTotal = UserDefaults.standard.integer(forKey: Self.maxTotalCharactersKey)
        maxTotalCharacters = savedTotal > 0 ? savedTotal : 4_000

        debugLoggingEnabled = UserDefaults.standard.bool(forKey: Self.debugLoggingEnabledKey)
    }

    func config(for kind: LLMContextItem.Kind) -> ContextSourceConfig {
        sources.first { $0.kind == kind }
            ?? Self.defaultSources.first { $0.kind == kind }
            ?? ContextSourceConfig(kind: kind, enabled: false, priority: 100)
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

    private static func mergeDefaults(with saved: [ContextSourceConfig]) -> [ContextSourceConfig] {
        defaultSources.map { defaultSource in
            saved.first { $0.kind == defaultSource.kind } ?? defaultSource
        }
    }

    static let defaultSources: [ContextSourceConfig] = [
        ContextSourceConfig(kind: .selectedText, enabled: true, priority: 10),
        ContextSourceConfig(kind: .inputText, enabled: true, priority: 20),
        ContextSourceConfig(kind: .windowTitle, enabled: true, priority: 30),
        ContextSourceConfig(kind: .applicationName, enabled: true, priority: 40),
        ContextSourceConfig(kind: .clipboard, enabled: true, priority: 50),
    ]
}

struct ContextDiagnosticItem: Identifiable {
    let id = UUID()
    let kind: LLMContextItem.Kind
    let text: String
    let priority: Int
    let characterCount: Int
    let isTruncated: Bool
    let isFiltered: Bool
    let filterReason: FilterReason?

    enum FilterReason {
        case sensitiveContent
        case disabledByUser
        case emptyText
        case budgetExceeded
    }
}

struct ContextDiagnostics {
    let rawItems: [ContextDiagnosticItem]
    let finalItems: [ContextDiagnosticItem]
    let timestamp: Date
    let totalBudget: Int
    let usedBudget: Int
}

struct ContextAggregator {
    var collector: BasicContextCollector
    var settings: ContextSettingsStore

    init(collector: BasicContextCollector = BasicContextCollector(), settings: ContextSettingsStore) {
        self.collector = collector
        self.settings = settings
    }

    func collect() -> [LLMContextItem] {
        var remainingBudget = settings.maxTotalCharacters
        let prioritized = collector.collect()
            .compactMap { item -> LLMContextItem? in
                guard !item.isSensitive else { return nil }
                let config = settings.config(for: item.kind)
                guard config.enabled else { return nil }

                let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }

                var normalized = item
                normalized.priority = config.priority
                normalized.text = trimmed
                return normalized
            }
            .sorted { lhs, rhs in
                lhs.priority == rhs.priority ? lhs.kind.rawValue < rhs.kind.rawValue : lhs.priority < rhs.priority
            }

        return prioritized.compactMap { item in
            guard remainingBudget > 0 else { return nil }
            let perItemBudget = max(1, min(settings.maxCharactersPerItem, remainingBudget))
            var normalized = item
            normalized.text = String(item.text.prefix(perItemBudget))
            remainingBudget -= normalized.text.count
            return normalized
        }
    }
}

enum ContextDebugLogger {
    static func log(_ context: [LLMContextItem]) {
        if context.isEmpty {
            NSLog("[TingMo] LLM context: empty")
            return
        }

        let summary = context.map { item in
            let preview = item.text
                .replacingOccurrences(of: "\n", with: "\\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(240)
            return "\(item.kind.rawValue)(priority=\(item.priority), chars=\(item.text.count)): \(preview)"
        }
        .joined(separator: " | ")

        NSLog("[TingMo] LLM context: \(summary)")
    }
}
