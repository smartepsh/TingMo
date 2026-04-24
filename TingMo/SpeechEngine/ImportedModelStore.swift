import Foundation
import Observation

/// Persists the list of user-imported WhisperKit models.
///
/// Imported models live under `Application Support/TingMo/Models/Imported/<id>/`
/// and are validated at import time (the three required .mlmodelc bundles
/// must be present). A lightweight manifest is stored in UserDefaults so we
/// can register them alongside the built-in variants at launch.
@Observable
@MainActor
final class ImportedModelStore {
    private static let storageKey = "ImportedModelStore.models"

    struct ImportedModel: Codable, Identifiable, Hashable, Sendable {
        /// Stable ID — derived from the source folder name, sanitised.
        let id: String
        /// User-facing display name (defaults to id).
        var displayName: String

        var engineID: String {
            "\(WhisperKitEngine.engineID)-imported-\(id)"
        }

        var folderURL: URL {
            ImportedModelStore.rootDirectory.appendingPathComponent(id, isDirectory: true)
        }
    }

    enum ImportError: LocalizedError {
        case missingSubmodel(name: String)
        case copyFailed(underlying: Error)
        case duplicateID(String)
        case invalidSource

        var errorDescription: String? {
            switch self {
            case .missingSubmodel(let name):
                return String(localized: "Invalid model: required bundle '\(name)' is missing.")
            case .copyFailed(let err):
                return String(localized: "Failed to copy model: \(err.localizedDescription)")
            case .duplicateID(let id):
                return String(localized: "A model named '\(id)' is already imported.")
            case .invalidSource:
                return String(localized: "The selected item is not a valid WhisperKit model folder.")
            }
        }
    }

    /// All currently imported models (persisted).
    private(set) var models: [ImportedModel] = []

    init() {
        load()
    }

    /// Root directory under Application Support that holds all imported models.
    static var rootDirectory: URL {
        WhisperKitEngine.modelsDirectory.appendingPathComponent("Imported", isDirectory: true)
    }

    static let requiredSubmodels = [
        "AudioEncoder.mlmodelc",
        "MelSpectrogram.mlmodelc",
        "TextDecoder.mlmodelc",
    ]

    /// Validate that `folder` contains the three required .mlmodelc bundles.
    static func validateFolder(_ folder: URL) -> ImportError? {
        for name in requiredSubmodels {
            let path = folder.appendingPathComponent(name, isDirectory: true).path
            if !FileManager.default.fileExists(atPath: path) {
                return .missingSubmodel(name: name)
            }
        }
        return nil
    }

    /// Copy the user's folder into our managed Imported directory and
    /// register a new ImportedModel. Validates on entry; rolls back on copy
    /// failure; rejects duplicate IDs.
    @discardableResult
    func importFolder(_ source: URL) throws -> ImportedModel {
        NSLog("[TingMo][ImportedModel] import start source=\(source.path)")
        let values = try? source.resourceValues(forKeys: [.isDirectoryKey])
        guard values?.isDirectory == true else {
            NSLog("[TingMo][ImportedModel] import aborted — source is not a directory")
            throw ImportError.invalidSource
        }

        if let validationError = Self.validateFolder(source) {
            NSLog("[TingMo][ImportedModel] import aborted — validation error=\(validationError)")
            throw validationError
        }

        let id = sanitise(source.lastPathComponent)
        if models.contains(where: { $0.id == id }) {
            NSLog("[TingMo][ImportedModel] import aborted — duplicate id=\(id)")
            throw ImportError.duplicateID(id)
        }

        let destinationRoot = Self.rootDirectory
        try FileManager.default.createDirectory(
            at: destinationRoot,
            withIntermediateDirectories: true
        )
        let destination = destinationRoot.appendingPathComponent(id, isDirectory: true)

        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            NSLog("[TingMo][ImportedModel] copy FAILED id=\(id) error=\(error)")
            try? FileManager.default.removeItem(at: destination)
            throw ImportError.copyFailed(underlying: error)
        }

        let model = ImportedModel(id: id, displayName: source.lastPathComponent)
        models.append(model)
        save()
        NSLog("[TingMo][ImportedModel] import success id=\(id) folder=\(destination.path)")
        return model
    }

    /// Remove the model directory and drop it from the manifest.
    func remove(_ model: ImportedModel) {
        NSLog("[TingMo][ImportedModel] remove id=\(model.id) folder=\(model.folderURL.path)")
        try? FileManager.default.removeItem(at: model.folderURL)
        models.removeAll { $0.id == model.id }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([ImportedModel].self, from: data)
        else { return }
        // Drop models whose on-disk directory has gone missing.
        models = decoded.filter {
            FileManager.default.fileExists(atPath: $0.folderURL.path)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(models) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func sanitise(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let filtered = raw.unicodeScalars.filter { allowed.contains($0) }
        let id = String(String.UnicodeScalarView(filtered))
        return id.isEmpty ? "imported-\(UUID().uuidString.prefix(6))" : id
    }
}
