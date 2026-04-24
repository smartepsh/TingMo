import Foundation
import Observation

/// Persists the user's current transcription language preference (ISO / BCP-47
/// code like "zh", "en"). Single global value: we don't store a per-engine
/// language since users overwhelmingly transcribe in one language at a time.
///
/// Engines that can't serve the current language surface a compatibility
/// warning at the settings UI and when activated.
@Observable
@MainActor
final class LanguagePreference {
    private static let storageKey = "LanguagePreference.currentLanguage"
    private static let defaultLanguage = "zh"

    /// Current ISO code passed to the engine (empty string means "auto-detect").
    var current: String {
        didSet {
            NSLog("[TingMo][Language] current changed \(oldValue) → \(current)")
            UserDefaults.standard.set(current, forKey: Self.storageKey)
        }
    }

    init() {
        current = UserDefaults.standard.string(forKey: Self.storageKey) ?? Self.defaultLanguage
    }

    /// Languages we expose in settings pickers. Kept intentionally small:
    /// the ones WhisperKit handles well + the ones the remote engines cover.
    /// Each entry is an ISO code + a user-facing display name.
    static let availableLanguages: [Language] = [
        Language(code: "en", name: "English"),
        Language(code: "zh", name: "中文"),
        Language(code: "ja", name: "日本語"),
        Language(code: "ko", name: "한국어"),
        Language(code: "de", name: "Deutsch"),
        Language(code: "fr", name: "Français"),
        Language(code: "es", name: "Español"),
        Language(code: "pt", name: "Português"),
        Language(code: "ru", name: "Русский"),
        Language(code: "it", name: "Italiano"),
    ]

    struct Language: Identifiable, Hashable, Sendable {
        let code: String
        let name: String
        var id: String { code }
    }

    static func displayName(for code: String) -> String {
        availableLanguages.first(where: { $0.code == code })?.name ?? code.uppercased()
    }
}
