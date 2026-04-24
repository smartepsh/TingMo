import SwiftUI
import UniformTypeIdentifiers

/// Settings section that lets users import local WhisperKit model folders
/// (either via an `.fileImporter` button or by dragging onto the drop zone)
/// and manage previously imported models.
struct ImportedModelSection: View {
    @Bindable var engineRegistry: EngineRegistry
    @Bindable var importedModelStore: ImportedModelStore

    @State private var showingImporter = false
    @State private var lastError: String?
    @State private var isTargeted = false

    var body: some View {
        Section {
            ForEach(importedModelStore.models) { model in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.displayName).fontWeight(.medium)
                        Text(model.folderURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button(String(localized: "Remove"), role: .destructive) {
                        remove(model)
                    }
                }
            }

            dropZone
                .frame(height: 70)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4])
                        )
                )
                .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)

            Button(String(localized: "Import Model Folder…")) {
                showingImporter = true
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { importFolder(url) }
                case .failure(let err):
                    lastError = err.localizedDescription
                }
            }

            if let lastError {
                Label(lastError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Imported Models")
        } footer: {
            Text(String(localized: "Drop or import a folder containing AudioEncoder.mlmodelc, MelSpectrogram.mlmodelc and TextDecoder.mlmodelc."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Drop zone

    @ViewBuilder
    private var dropZone: some View {
        VStack(spacing: 4) {
            Image(systemName: "square.and.arrow.down")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(String(localized: "Drop a WhisperKit model folder here"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard
                let data = item as? Data,
                let url = URL(dataRepresentation: data, relativeTo: nil)
            else { return }
            Task { @MainActor in
                importFolder(url)
            }
        }
        return true
    }

    // MARK: - Actions

    private func importFolder(_ url: URL) {
        lastError = nil
        do {
            _ = try importedModelStore.importFolder(url)
            engineRegistry.refreshImportedEngines()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func remove(_ model: ImportedModelStore.ImportedModel) {
        // If this imported model is currently active, fall back to the default
        // built-in tiny variant so the pipeline isn't left pointing at a
        // soon-to-be-deleted folder.
        if engineRegistry.activeEngineID == model.engineID {
            engineRegistry.setActiveEngine(WhisperKitEngine.defaultModelEngineID)
        }
        importedModelStore.remove(model)
        engineRegistry.refreshImportedEngines()
    }
}
