import Foundation

enum STTProviderID: String, Codable, CaseIterable, Identifiable {
    case groq
    case elevenlabs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groq: String(localized: "Groq")
        case .elevenlabs: String(localized: "ElevenLabs")
        }
    }

    var defaultInstanceName: String {
        switch self {
        case .groq: String(localized: "Groq Whisper")
        case .elevenlabs: String(localized: "ElevenLabs Scribe")
        }
    }

    var supportedLanguages: [String] {
        switch self {
        case .groq:
            ["en", "zh", "ja", "ko", "de", "fr", "es", "pt", "ru", "it"]
        case .elevenlabs:
            ["en", "zh", "ja", "ko", "de", "fr", "es", "pt", "it", "nl",
             "pl", "ru", "tr", "ar", "hi"]
        }
    }

    func supportsLanguage(_ code: String) -> Bool {
        supportedLanguages.contains(code)
    }
}
