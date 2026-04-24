import Foundation

/// How the audio input device is selected when a preset is active.
enum DeviceSelectionMode: String, Codable, CaseIterable, Identifiable {
    /// Use the macOS system default audio input device.
    case system
    /// Use a specific device pinned in local audio device settings.
    case specified
    /// Iterate the local priority list and use the first online device.
    case priority

    var id: String { rawValue }
}

/// A named configuration bundle combining engine, language, LLM, device mode, and dictionaries.
struct ConfigPreset: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var engineID: String
    var language: String
    var deviceSelectionMode: DeviceSelectionMode
    /// UIDs of the specified device (only used when mode == .specified).
    var specifiedDeviceUID: String?
    var llm: LLMConfig
    /// IDs of active dictionaries for this preset.
    var activeDictionaryIDs: [UUID]
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String = String(localized: "Default"),
        engineID: String = "apple-speech",
        language: String = "zh-Hans",
        deviceSelectionMode: DeviceSelectionMode = .system,
        specifiedDeviceUID: String? = nil,
        llm: LLMConfig = LLMConfig(),
        activeDictionaryIDs: [UUID] = [],
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.engineID = engineID
        self.language = language
        self.deviceSelectionMode = deviceSelectionMode
        self.specifiedDeviceUID = specifiedDeviceUID
        self.llm = llm
        self.activeDictionaryIDs = activeDictionaryIDs
        self.sortOrder = sortOrder
    }
}
