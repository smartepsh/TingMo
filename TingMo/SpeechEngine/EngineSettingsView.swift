import SwiftUI

/// Settings panel section for engine + language selection.
///
/// Layout:
///   • Language picker (applies to every engine)
///   • Engine list grouped by Local / Remote
///   • Compatibility warning if active engine can't serve current language
struct EngineSettingsView: View {
    @Bindable var engineRegistry: EngineRegistry
    @Bindable var languagePreference: LanguagePreference

    var body: some View {
        Section {
            Picker(String(localized: "Language"), selection: $languagePreference.current) {
                ForEach(LanguagePreference.availableLanguages) { lang in
                    Text(lang.name).tag(lang.code)
                }
            }

            if let active = engineRegistry.activeEngine,
               !active.supportsLanguage(languagePreference.current)
            {
                Label(
                    String(localized: "\(active.info.name) does not support \(LanguagePreference.displayName(for: languagePreference.current)). Pick another engine or language."),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        } header: {
            Text("Language")
        }

        Section {
            ForEach(localEngines, id: \.info.id) { engine in
                engineRow(for: engine)
            }
        } header: {
            Text("Local Engines")
        }

        Section {
            ForEach(remoteEngines, id: \.info.id) { engine in
                engineRow(for: engine)
            }
            if remoteEngines.isEmpty {
                Text(String(localized: "No remote engine configured. Add an API key below."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Remote Engines")
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func engineRow(for engine: any SpeechEngine) -> some View {
        let isActive = engineRegistry.activeEngineID == engine.info.id
        let compatible = engine.supportsLanguage(languagePreference.current)
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(engine.info.name)
                        .fontWeight(isActive ? .semibold : .regular)
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                HStack(spacing: 8) {
                    Text(engine.info.type == .local
                        ? String(localized: "Local")
                        : String(localized: "Remote"))
                    if let size = engine.info.modelSize {
                        Text(size)
                    }
                    if !compatible {
                        Text(String(localized: "Incompatible with \(LanguagePreference.displayName(for: languagePreference.current))"))
                            .foregroundStyle(.orange)
                    } else if !engine.info.isReady {
                        Text(statusLabel(for: engine))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(activateButtonTitle(for: engine, isActive: isActive, compatible: compatible)) {
                engineRegistry.setActiveEngine(engine.info.id)
            }
            .disabled(isActive || !compatible || !engine.info.isReady)
        }
    }

    private func statusLabel(for engine: any SpeechEngine) -> String {
        if engine is ParakeetEngine {
            return ParakeetEngine.comingSoonLabel
        }
        if engine.info.type == .remote {
            return String(localized: "Missing API key")
        }
        return String(localized: "Not downloaded")
    }

    private func activateButtonTitle(for engine: any SpeechEngine, isActive: Bool, compatible: Bool) -> String {
        if isActive { return String(localized: "Active") }
        if !compatible { return String(localized: "Incompatible") }
        if !engine.info.isReady { return String(localized: "Unavailable") }
        return String(localized: "Use")
    }

    // MARK: - Grouping

    private var localEngines: [any SpeechEngine] {
        engineRegistry.engines.filter { $0.info.type == .local }
    }

    private var remoteEngines: [any SpeechEngine] {
        engineRegistry.engines.filter { $0.info.type == .remote }
    }
}
