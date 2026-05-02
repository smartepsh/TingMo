import SwiftUI

/// Settings panel section for managing local WhisperKit model downloads.
///
/// Responsibilities:
///   • Pick the HF endpoint (official / mirror / custom)
///   • List every WhisperKit variant with disk size, progress, retry, delete
///   • Show total disk usage across downloaded models
struct ModelDownloadView: View {
    @Bindable var engineRegistry: EngineRegistry
    @Bindable var downloadSource: DownloadSourcePreference
    @Bindable var presetStore: ConfigPresetStore

    @State private var endpointPresetID: String
    @State private var customEndpoint: String
    @State private var pendingDeleteEngineID: String?
    @State private var pendingCancelEngineID: String?

    init(
        engineRegistry: EngineRegistry,
        downloadSource: DownloadSourcePreference,
        presetStore: ConfigPresetStore
    ) {
        self.engineRegistry = engineRegistry
        self.downloadSource = downloadSource
        self.presetStore = presetStore
        _endpointPresetID = State(initialValue: downloadSource.matchingPresetID)
        _customEndpoint = State(initialValue: downloadSource.endpoint)
    }

    var body: some View {
        Section {
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
        } header: {
            Text("Download Source")
        }

        Section {
            ForEach(WhisperKitEngine.availableModels) { model in
                modelRow(model: model)
            }

            HStack {
                Text(String(localized: "Total disk usage"))
                Spacer()
                Text(totalDiskUsageFormatted)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("WhisperKit Models")
        } footer: {
            Text(String(localized: "Models install to ~/Library/Application Support/TingMo/Models. Changing the download source does not affect models already on disk."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func modelRow(model: WhisperKitEngine.WhisperModel) -> some View {
        let engineID = "\(WhisperKitEngine.engineID)-\(model.id)"
        let progress = engineRegistry.progress(for: engineID)
        let error = engineRegistry.downloadError(for: engineID)
        let downloaded = WhisperKitEngine.isModelDownloaded(model)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name).fontWeight(.medium)
                    Text(subtitle(
                        model: model,
                        downloaded: downloaded,
                        progress: progress,
                        error: error
                    ))
                    .font(.caption)
                    .foregroundStyle(error == nil ? .secondary : Color.red)
                }
                Spacer()
                controls(engineID: engineID,
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

    private func subtitle(
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
    private func controls(engineID: String, downloaded: Bool, progress: Double?, hasError: Bool) -> some View {
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

    // MARK: - Aggregate

    private var totalDiskUsageFormatted: String {
        _ = engineRegistry.diskUsageVersion
        let total = WhisperKitEngine.availableModels.reduce(Int64(0)) {
            $0 + WhisperKitEngine.diskUsage(for: $1)
        }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}
