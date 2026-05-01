import Foundation

struct STTInstance: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var displayName: String
    var provider: STTProviderID
    var keychainService: String

    init(
        id: UUID = UUID(),
        displayName: String? = nil,
        provider: STTProviderID = .groq,
        keychainService: String? = nil
    ) {
        let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        self.id = id
        self.displayName = trimmedName
        self.provider = provider
        self.keychainService = keychainService ?? Self.keychainService(for: id)
    }

    static func keychainService(for id: UUID) -> String {
        "tingmo.stt.instance.\(id.uuidString)"
    }
}
