import Foundation

/// A local engine whose model is fetched on demand rather than bundled.
///
/// `EngineRegistry` owns the download/prepare orchestration — progress,
/// cancellation, error reporting, disk accounting — and previously reached for
/// `WhisperKitEngine` directly to do it. Everything it actually needed is
/// declared here instead, so a second local engine participates without the
/// registry knowing its concrete type.
protocol DownloadableEngine: AnyObject, SpeechEngine {
    /// Runtime load state, separate from "the files are on disk": a downloaded
    /// model still has to be read into memory before the first transcription.
    var modelLoadState: ModelLoadState { get }

    /// Whether the model files are present on disk.
    var isModelDownloaded: Bool { get }

    /// Size of the on-disk model in bytes, or 0 when absent.
    var diskUsage: Int64 { get }

    /// Fetch the model. Must be a no-op when it is already present.
    /// - Parameters:
    ///   - endpoint: mirror host honouring the user's download-source choice.
    ///     Engines that do not resolve through a mirror may ignore it.
    ///   - progress: fractional progress in 0...1.
    func downloadModel(
        endpoint: String?,
        progress: (@Sendable (Double) -> Void)?
    ) async throws

    /// Load the downloaded model into memory. Must be safe to call repeatedly;
    /// concurrent callers should share one load rather than starting several.
    func loadModel() async throws

    /// Remove the on-disk model. Returns false when there was nothing to delete
    /// or the removal failed.
    @discardableResult
    func deleteLocalFiles() -> Bool
}

/// Load state shared by every downloadable engine.
///
/// Hoisted out of `WhisperKitEngine` so the registry can describe preparation
/// uniformly. `WhisperKitEngine.ModelLoadState` remains as a type alias for
/// call sites that still spell it that way.
enum ModelLoadState: Equatable, Sendable {
    case unloaded
    case loading
    case loaded
    case failed(String)
}

extension DownloadableEngine {
    var isModelLoaded: Bool { modelLoadState == .loaded }
}
