import Foundation
import Observation

/// Persists the user's selected input languages for engine filtering.
///
/// Multiple languages can be selected to find engines that support all of them.
/// This is a filtering/discovery tool, not a runtime hint passed to engines.
///
/// Engines that can't serve all selected languages surface a compatibility
/// warning at the settings UI.
@Observable
@MainActor
final class LanguagePreference {
    private static let storageKey = "LanguagePreference.selectedLanguages"
    private static let legacyStorageKey = "LanguagePreference.currentLanguage"

    /// Selected ISO codes for engine filtering (empty means "no filter").
    var selectedLanguages: Set<String> {
        didSet {
            NSLog("[TingMo][Language] selectedLanguages changed \(oldValue) → \(selectedLanguages)")
            save()
        }
    }

    init() {
        selectedLanguages = Self.load()
    }

    // MARK: - Persistence

    private func save() {
        let array = Array(selectedLanguages)
        UserDefaults.standard.set(array, forKey: Self.storageKey)
    }

    private static func load() -> Set<String> {
        // Try new storage first
        if let array = UserDefaults.standard.array(forKey: storageKey) as? [String] {
            return Set(array)
        }
        // Migrate from legacy single-language storage
        if let legacy = UserDefaults.standard.string(forKey: legacyStorageKey), !legacy.isEmpty {
            return [legacy]
        }
        return []
    }

    // MARK: - Languages

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
