import Foundation
import Observation

/// Persists the user's preferred HuggingFace endpoint used for WhisperKit
/// model downloads. Defaults to the official HF; users on restricted
/// networks can swap to a mirror (e.g. hf-mirror.com) or a private host.
@Observable
@MainActor
final class DownloadSourcePreference {
    private static let storageKey = "DownloadSourcePreference.endpoint"

    /// Current endpoint URL string (no trailing slash). Empty means "use default".
    var endpoint: String {
        didSet {
            NSLog("[TingMo][DownloadSource] endpoint changed '\(oldValue)' → '\(endpoint)'")
            UserDefaults.standard.set(endpoint, forKey: Self.storageKey)
        }
    }

    /// Presets shown in the settings picker.
    struct Preset: Identifiable, Hashable, Sendable {
        let id: String
        let label: String
        let endpoint: String
    }

    static let presets: [Preset] = [
        Preset(id: "huggingface", label: "HuggingFace (默认)", endpoint: "https://huggingface.co"),
        Preset(id: "hf-mirror", label: "hf-mirror.com (国内镜像)", endpoint: "https://hf-mirror.com"),
        Preset(id: "custom", label: String(localized: "Custom…"), endpoint: ""),
    ]

    static let defaultEndpoint = presets[0].endpoint

    init() {
        endpoint = UserDefaults.standard.string(forKey: Self.storageKey) ?? Self.defaultEndpoint
    }

    /// Endpoint value to actually pass to WhisperKit. Falls back to default
    /// when the user stored an empty custom value.
    var effectiveEndpoint: String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultEndpoint : trimmed
    }

    /// Matches the current endpoint to a preset ID, or "custom" if it's
    /// something user-entered.
    var matchingPresetID: String {
        Self.presets.first(where: { $0.endpoint == endpoint })?.id ?? "custom"
    }
}
