import AppKit
import SwiftUI

/// Combined settings section for all local speech engines: recommended
/// sherpa-onnx models and the larger WhisperKit family.
struct LocalProviderSection: View {
    @Bindable var engineRegistry: EngineRegistry
    @Bindable var downloadSource: DownloadSourcePreference
    @Bindable var presetStore: ConfigPresetStore

    @State private var endpointPresetID: String
    @State private var customEndpoint: String
    @State private var pendingDeleteEngineID: String?
    @State private var pendingCancelEngineID: String?
    @State private var isSherpaGroupExpanded = true
    @State private var isWhisperGroupExpanded = false

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

            DisclosureGroup(isExpanded: $isSherpaGroupExpanded) {
                ForEach(SherpaOnnxModelDescriptor.builtInModels) { descriptor in
                    sherpaOnnxModelRow(descriptor: descriptor)
                        .padding(.leading, 24)
                }
            } label: {
                modelGroupLabel(
                    title: String(localized: "Sherpa ONNX Models"),
                    badge: String(localized: "Recommended")
                )
            }

            DisclosureGroup(isExpanded: $isWhisperGroupExpanded) {
                ForEach(WhisperKitEngine.availableModels) { model in
                    whisperKitModelRow(model: model)
                        .padding(.leading, 24)
                }
            } label: {
                modelGroupLabel(title: String(localized: "Whisper Models"))
            }

            HStack {
                Text(String(localized: "Total disk usage"))
                Spacer()
                Text(totalDiskUsageFormatted)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button(action: openModelsDirectory) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Show Models in Finder"))
                .accessibilityLabel(String(localized: "Show Models in Finder"))
            }
        } header: {
            Text("Local Provider")
        } footer: {
            Text(String(localized: "Models install to ~/Library/Application Support/TingMo/Models. Changing the download source does not affect models already on disk."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func modelGroupLabel(title: String, badge: String? = nil) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout.weight(.semibold))
            if let badge {
                recommendationBadge(badge)
            }
        }
    }

    @ViewBuilder
    private func recommendationBadge(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
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
    private func sherpaOnnxModelRow(descriptor: SherpaOnnxModelDescriptor) -> some View {
        let engineID = descriptor.engineID
        let progress = engineRegistry.progress(for: engineID)
        let error = engineRegistry.downloadError(for: engineID)
        let downloaded = descriptor.isModelInstalled

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.modelDisplayName).fontWeight(.medium)
                    Text(sherpaOnnxSubtitle(
                        descriptor: descriptor,
                        downloaded: downloaded,
                        progress: progress,
                        error: error
                    ))
                    .font(.caption)
                    .foregroundStyle(error == nil ? .secondary : Color.red)
                }
                Spacer()
                whisperKitControls(
                    engineID: engineID,
                    downloaded: downloaded,
                    progress: progress,
                    hasError: error != nil
                )
            }
            if let progress {
                ProgressView(value: progress)
            }
        }
        .padding(.vertical, 2)
    }

    private func sherpaOnnxSubtitle(
        descriptor: SherpaOnnxModelDescriptor,
        downloaded: Bool,
        progress: Double?,
        error: String?
    ) -> String {
        if let error { return "\(String(localized: "Failed")): \(error)" }
        if let progress {
            return "\(String(localized: "Downloading")) \(Int(progress * 100))%"
        }
        if downloaded {
            let installedSize = ByteCountFormatter.string(
                fromByteCount: descriptor.diskUsage,
                countStyle: .file
            )
            return "\(descriptor.modelSize) · \(String(localized: "Downloaded")) (\(installedSize))"
        }
        return "\(descriptor.modelSize) · \(descriptor.languageDisplayName)"
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
                    engineRegistry.downloadModel(engineID: engineID)
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
                        engineRegistry.prepareEngine(WhisperKitEngine.defaultModelEngineID)
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
                    engineRegistry.downloadModel(engineID: engineID)
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Aggregate

    private func openModelsDirectory() {
        let directory = WhisperKitEngine.modelsDirectory
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(directory)
    }

    private var totalDiskUsageFormatted: String {
        _ = engineRegistry.diskUsageVersion
        let whisperTotal = WhisperKitEngine.availableModels.reduce(Int64(0)) {
            $0 + WhisperKitEngine.diskUsage(for: $1)
        }
        let sherpaTotal = SherpaOnnxModelDescriptor.builtInModels.reduce(Int64(0)) {
            $0 + $1.diskUsage
        }
        return ByteCountFormatter.string(
            fromByteCount: whisperTotal + sherpaTotal,
            countStyle: .file
        )
    }
}
