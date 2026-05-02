import SwiftUI
import UniformTypeIdentifiers

/// Combined settings section for all local speech engines: WhisperKit model
/// downloads and user-imported model folders.
struct LocalProviderSection: View {
    @Bindable var engineRegistry: EngineRegistry
    @Bindable var downloadSource: DownloadSourcePreference
    @Bindable var importedModelStore: ImportedModelStore
    @Bindable var presetStore: ConfigPresetStore

    @State private var endpointPresetID: String
    @State private var customEndpoint: String
    @State private var lastImportError: String?
    @State private var isDropTargeted = false
    @State private var pendingDeleteEngineID: String?
    @State private var pendingCancelEngineID: String?
    @State private var pendingRemoveModelID: String?

    init(
        engineRegistry: EngineRegistry,
        downloadSource: DownloadSourcePreference,
        importedModelStore: ImportedModelStore,
        presetStore: ConfigPresetStore
    ) {
        self.engineRegistry = engineRegistry
        self.downloadSource = downloadSource
        self.importedModelStore = importedModelStore
        self.presetStore = presetStore
        _endpointPresetID = State(initialValue: downloadSource.matchingPresetID)
        _customEndpoint = State(initialValue: downloadSource.endpoint)
    }

    var body: some View {
        Section {
            // Download Source config
            Picker(String(localized: "Download Source"), selection: $endpointPresetID) {
                ForEach(DownloadSourcePreference.presets) { preset in
                    Text(preset.label).tag(preset.id)
                }
            }
            .onChange(of: endpointPresetID) { _, newID in
                if newID == "custom" { return }
                if let preset = DownloadSourcePreference.presets.first(where: { $0.id == newID }) {
                    downloadSource.endpoint = preset.endpoint
                    customEndpoint = preset.endpoint
                }
            }

            if endpointPresetID == "custom" {
                TextField(
                    String(localized: "Endpoint URL"),
                    text: $customEndpoint,
                    prompt: Text("https://example.com")
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    downloadSource.endpoint = customEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            Text(String(localized: "Current endpoint: \(downloadSource.effectiveEndpoint)"))
                .font(.caption)
                .foregroundStyle(.secondary)

            // WhisperKit built-in models
            Text("Whisper Models")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(WhisperKitEngine.availableModels) { model in
                whisperKitModelRow(model: model)
            }

            HStack {
                Text(String(localized: "Total disk usage"))
                Spacer()
                Text(totalDiskUsageFormatted)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Imported models
            Text("Imported Models")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(importedModelStore.models) { model in
                let isPending = pendingRemoveModelID == model.id
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
                    Button {
                        if isPending {
                            removeImportedModel(model)
                            pendingRemoveModelID = nil
                        } else {
                            pendingRemoveModelID = model.id
                        }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(isPending ? .red : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .onHover { inside in
                        if !inside && isPending {
                            pendingRemoveModelID = nil
                        }
                    }
                }
            }

            dropZone
                .frame(height: 70)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4])
                        )
                )
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)

            if let lastImportError {
                Label(lastImportError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Local Provider")
        } footer: {
            Text(String(localized: "Models install to ~/Library/Application Support/TingMo/Models. Drop a folder containing AudioEncoder.mlmodelc, MelSpectrogram.mlmodelc and TextDecoder.mlmodelc to import."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - WhisperKit Model Row

    @ViewBuilder
    private func whisperKitModelRow(model: WhisperKitEngine.WhisperModel) -> some View {
        let engineID = "\(WhisperKitEngine.engineID)-\(model.id)"
        let progress = engineRegistry.progress(for: engineID)
        let error = engineRegistry.downloadError(for: engineID)
        let downloaded = WhisperKitEngine.isModelDownloaded(model)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name).fontWeight(.medium)
                    Text(whisperKitSubtitle(
                        model: model,
                        downloaded: downloaded,
                        progress: progress,
                        error: error
                    ))
                    .font(.caption)
                    .foregroundStyle(error == nil ? .secondary : Color.red)
                }
                Spacer()
                whisperKitControls(engineID: engineID,
                                   downloaded: downloaded,
                                   progress: progress,
                                   hasError: error != nil)
            }
            if let p = progress {
                ProgressView(value: p)
            }
        }
        .padding(.vertical, 2)
    }

    private func whisperKitSubtitle(
        model: WhisperKitEngine.WhisperModel,
        downloaded: Bool,
        progress: Double?,
        error: String?
    ) -> String {
        if let error { return "\(String(localized: "Failed")): \(error)" }
        if let progress {
            return "\(Int(progress * 100))%"
        }
        if downloaded {
            let bytes = WhisperKitEngine.diskUsage(for: model)
            let sizeStr = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            return "\(String(localized: "Installed")) · \(sizeStr)"
        }
        return "\(model.size) · \(String(localized: "Not installed"))"
    }

    @ViewBuilder
    private func whisperKitControls(engineID: String, downloaded: Bool, progress: Double?, hasError: Bool) -> some View {
        HStack(spacing: 8) {
            if progress != nil {
                let isPending = pendingCancelEngineID == engineID
                Button {
                    if isPending {
                        engineRegistry.cancelDownload(engineID: engineID)
                        pendingCancelEngineID = nil
                    } else {
                        pendingCancelEngineID = engineID
                    }
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(isPending ? .red : .secondary)
                }
                .buttonStyle(.borderless)
                .onHover { inside in
                    if !inside && isPending {
                        pendingCancelEngineID = nil
                    }
                }
            } else if hasError {
                Button(String(localized: "Retry")) {
                    engineRegistry.clearDownloadError(for: engineID)
                    engineRegistry.downloadModel(engineID: engineID, makeActiveWhenDone: false)
                }
            } else if downloaded {
                let isActive = presetStore.defaultPreset.speechEngineID == engineID
                let isPending = pendingDeleteEngineID == engineID
                Button {
                    if isActive {
                        _ = engineRegistry.deleteDownloadedModel(engineID: engineID)
                        presetStore.replaceSpeechEngineSelection(
                            deletedID: engineID,
                            fallbackID: WhisperKitEngine.defaultModelEngineID
                        )
                    } else if isPending {
                        _ = engineRegistry.deleteDownloadedModel(engineID: engineID)
                        presetStore.replaceSpeechEngineSelection(
                            deletedID: engineID,
                            fallbackID: WhisperKitEngine.defaultModelEngineID
                        )
                        pendingDeleteEngineID = nil
                    } else {
                        pendingDeleteEngineID = engineID
                    }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(isPending ? .red : .secondary)
                }
                .buttonStyle(.borderless)
                .onHover { inside in
                    if !inside && isPending {
                        pendingDeleteEngineID = nil
                    }
                }
            } else {
                Button {
                    engineRegistry.downloadModel(engineID: engineID, makeActiveWhenDone: false)
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Imported Model Helpers

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
        .background(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
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

    private func importFolder(_ url: URL) {
        lastImportError = nil
        do {
            _ = try importedModelStore.importFolder(url)
            engineRegistry.refreshImportedEngines()
        } catch {
            lastImportError = error.localizedDescription
        }
    }

    private func removeImportedModel(_ model: ImportedModelStore.ImportedModel) {
        if presetStore.defaultPreset.speechEngineID == model.engineID {
            presetStore.replaceSpeechEngineSelection(
                deletedID: model.engineID,
                fallbackID: WhisperKitEngine.defaultModelEngineID
            )
            engineRegistry.setActiveEngine(WhisperKitEngine.defaultModelEngineID)
        }
        importedModelStore.remove(model)
        engineRegistry.refreshImportedEngines()
    }

    // MARK: - Aggregate

    private var totalDiskUsageFormatted: String {
        _ = engineRegistry.diskUsageVersion
        let total = WhisperKitEngine.availableModels.reduce(Int64(0)) {
            $0 + WhisperKitEngine.diskUsage(for: $1)
        }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}
