import SwiftUI

/// Settings panel section for engine + language selection.
///
/// Layout:
///   • Input Languages multi-select (for engine filtering)
///   • Compatible engines list
///   • Engine list grouped by Local / Remote
struct EngineSettingsView: View {
    @Bindable var engineRegistry: EngineRegistry
    @Bindable var languagePreference: LanguagePreference
    @Bindable var presetStore: ConfigPresetStore

    private var selectedSpeechEngine: (any SpeechEngine)? {
        engineRegistry.engine(id: presetStore.defaultPreset.speechEngineID)
    }

    var body: some View {
        Section {
            ForEach(LanguagePreference.availableLanguages) { lang in
                Toggle(lang.name, isOn: languageBinding(for: lang.code))
            }
        } header: {
            Text("Input Languages")
        } footer: {
            Text("Select languages you will speak. Engines that support all selected languages are shown below.")
        }

        Section {
            ForEach(compatibleEngines, id: \.info.id) { engine in
                engineRow(for: engine, isCompatible: true)
            }
            if compatibleEngines.isEmpty {
                Text(String(localized: "No engines support all selected languages."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Compatible Engines")
        }

        if !incompatibleEngines.isEmpty {
            Section {
                ForEach(incompatibleEngines, id: \.info.id) { engine in
                    engineRow(for: engine, isCompatible: false)
                }
            } header: {
                Text("Incompatible Engines")
            }
        }
    }

    // MARK: - Engine Filtering

    private var compatibleEngines: [any SpeechEngine] {
        let selected = languagePreference.selectedLanguages
        if selected.isEmpty {
            return engineRegistry.engines
        }
        return engineRegistry.engines.filter { engine in
            selected.allSatisfy { engine.supportsLanguage($0) }
        }
    }

    private var incompatibleEngines: [any SpeechEngine] {
        let selected = languagePreference.selectedLanguages
        if selected.isEmpty {
            return []
        }
        return engineRegistry.engines.filter { engine in
            !selected.allSatisfy { engine.supportsLanguage($0) }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func engineRow(for engine: any SpeechEngine, isCompatible: Bool) -> some View {
        let isActive = presetStore.defaultPreset.speechEngineID == engine.info.id
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
                    if !isCompatible {
                        Text(String(localized: "Does not support all selected languages"))
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

            Button(activateButtonTitle(for: engine, isActive: isActive, compatible: isCompatible)) {
                presetStore.defaultPreset.speechEngineID = engine.info.id
                engineRegistry.setActiveEngine(engine.info.id)
            }
            .disabled(isActive || !isCompatible || !engine.info.isReady)
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

    // MARK: - Bindings

    private func languageBinding(for code: String) -> Binding<Bool> {
        Binding(
            get: { languagePreference.selectedLanguages.contains(code) },
            set: { isSelected in
                if isSelected {
                    languagePreference.selectedLanguages.insert(code)
                } else {
                    languagePreference.selectedLanguages.remove(code)
                }
            }
        )
    }
}
