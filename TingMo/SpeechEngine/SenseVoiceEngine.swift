import AVFoundation
import Foundation

/// SenseVoice (FunASR) engine running on CPU via sherpa-onnx.
///
/// Prototype for the pipeline upgrade described in PLAN.md Phase 1. SenseVoice
/// is a ~234M non-autoregressive CTC model: it has no 30s fixed window and no
/// token-by-token decode, so short-utterance latency is far below Whisper's.
/// Its errors are homophone substitutions, which the downstream LLM correction
/// pass is well suited to repair — that complementarity, not raw CER, is the
/// reason this engine is worth having.
///
/// The sherpa-onnx runtime is linked into the app, but the model itself is
/// fetched on demand through `EngineRegistry` like the WhisperKit variants.
/// Until it is downloaded, `isReady` is false and the engine stays out of the
/// recognition-engine menu.
final class SenseVoiceEngine: DownloadableEngine, @unchecked Sendable {
    static let engineID = "sensevoice"

    /// zh / yue / en / ja / ko, per the model card. Other languages stay on
    /// Whisper, which remains registered alongside this engine.
    static let languages = ["zh", "yue", "en", "ja", "ko"]

    /// Pinned to the 2024-07-17 repo — stock SenseVoice-Small from FunAudioLLM.
    /// The later 2025-09-09 release looks like a newer build of the same model
    /// but is the WSYue Cantonese fine-tune: same speed, yet it drops words in
    /// Mandarin ("开放时间" → "放时间") and mangles Japanese and Korean. Do not
    /// bump this without benchmarking both on the same audio.
    static let repoID = "csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"

    var info: EngineInfo

    /// Guards `recognizer` — `transcribe` may be called from any task.
    private let lock = NSLock()
    private var recognizer: SherpaOnnxOfflineRecognizer?

    private let loadState = NSLock()
    private var _modelLoadState: ModelLoadState = .unloaded

    init() {
        self.info = EngineInfo(
            id: Self.engineID,
            name: "SenseVoice (中/粤/英/日/韩)",
            type: .local,
            supportedLanguages: Self.languages,
            supportsStreaming: false,
            modelSize: "226 MB",
            isReady: Self.isModelInstalled
        )
    }

    // MARK: - DownloadableEngine

    var modelLoadState: ModelLoadState {
        loadState.lock()
        defer { loadState.unlock() }
        return _modelLoadState
    }

    var isModelDownloaded: Bool { Self.isModelInstalled }

    var diskUsage: Int64 {
        let fm = FileManager.default
        return [Self.modelPath, Self.tokensPath].reduce(Int64(0)) { total, url in
            let attributes = try? fm.attributesOfItem(atPath: url.path)
            return total + ((attributes?[.size] as? Int64) ?? 0)
        }
    }

    /// Downloads the two files the recognizer needs straight from HuggingFace,
    /// honouring the user's mirror choice so a China-based user can point at
    /// hf-mirror.com like they already do for the Whisper models.
    func downloadModel(
        endpoint: String? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        if Self.isModelInstalled { return }

        let host = (endpoint?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? DownloadSourcePreference.defaultEndpoint
        let base = host.hasSuffix("/") ? String(host.dropLast()) : host

        guard
            let modelURL = URL(string: "\(base)/\(Self.repoID)/resolve/main/model.int8.onnx"),
            let tokensURL = URL(string: "\(base)/\(Self.repoID)/resolve/main/tokens.txt")
        else {
            throw SpeechEngineError.modelNotFound
        }

        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("sensevoice-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        // The model is ~239 MB and tokens ~308 KB, so the model's byte counts
        // carry the progress bar on their own.
        let stagedModel = staging.appendingPathComponent("model.int8.onnx")
        let stagedTokens = staging.appendingPathComponent("tokens.txt")
        try await Self.download(from: modelURL, to: stagedModel, progress: progress)
        try Task.checkCancellation()
        try await Self.download(from: tokensURL, to: stagedTokens, progress: nil)

        // Move into place only once both files are present, so an interrupted
        // download can never leave a half-installed folder that reads as ready.
        try fm.createDirectory(at: Self.modelFolder, withIntermediateDirectories: true)
        try? fm.removeItem(at: Self.modelPath)
        try? fm.removeItem(at: Self.tokensPath)
        try fm.moveItem(at: stagedModel, to: Self.modelPath)
        try fm.moveItem(at: stagedTokens, to: Self.tokensPath)

        info.isReady = true
    }

    /// Builds the recognizer up front so the first utterance does not pay the
    /// ~500 ms graph load. Safe to call repeatedly.
    func loadModel() async throws {
        guard Self.isModelInstalled else { throw SpeechEngineError.modelNotDownloaded }
        if isModelLoaded { return }

        loadState.lock()
        _modelLoadState = .loading
        loadState.unlock()

        do {
            _ = try makeRecognizerIfNeeded()
            loadState.lock()
            _modelLoadState = .loaded
            loadState.unlock()
        } catch {
            loadState.lock()
            _modelLoadState = .failed(error.localizedDescription)
            loadState.unlock()
            throw error
        }
    }

    @discardableResult
    func deleteLocalFiles() -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Self.modelFolder.path) else { return false }
        do {
            try fm.removeItem(at: Self.modelFolder)
        } catch {
            return false
        }

        lock.lock()
        recognizer = nil
        lock.unlock()

        loadState.lock()
        _modelLoadState = .unloaded
        loadState.unlock()

        info.isReady = false
        return true
    }

    // MARK: - Download helpers

    /// Session tuned for a single large asset: the default 60 s
    /// `timeoutIntervalForRequest` is a per-response idle timeout that a
    /// multi-hundred-megabyte transfer over a slow link trips easily, so the
    /// resource budget is what actually bounds this download.
    private static let downloadSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 3600
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    /// Downloads to a temporary file, reporting progress by observing the
    /// task's own `Progress` object.
    ///
    /// Two approaches were tried and rejected: `download(from:delegate:)` never
    /// delivered `didWriteData` to its per-task delegate, and consuming
    /// `bytes(from:)` byte-by-byte was slow enough that the server dropped the
    /// connection partway through. `URLSessionDownloadTask` keeps the fast
    /// system-managed transfer while exposing progress through KVO.
    private static func download(
        from url: URL,
        to destination: URL,
        progress: (@Sendable (Double) -> Void)?
    ) async throws {
        let observed = ProgressBox()

        let temporary: URL = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = downloadSession.downloadTask(with: url) { location, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard
                        let location,
                        let http = response as? HTTPURLResponse,
                        (200..<300).contains(http.statusCode)
                    else {
                        continuation.resume(throwing: SpeechEngineError.modelNotFound)
                        return
                    }
                    // The completion handler's file is deleted as soon as this
                    // returns, so it has to be moved out synchronously.
                    let staged = location.deletingLastPathComponent()
                        .appendingPathComponent("staged-\(UUID().uuidString)")
                    do {
                        try FileManager.default.moveItem(at: location, to: staged)
                        continuation.resume(returning: staged)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }

                if let progress {
                    observed.observe(task.progress, onProgress: progress)
                }
                observed.store(task)
                task.resume()
            }
        } onCancel: {
            observed.cancel()
        }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        progress?(1.0)
    }

    /// Holds the KVO observation and task handle for one download.
    private final class ProgressBox: @unchecked Sendable {
        private let lock = NSLock()
        private var observation: NSKeyValueObservation?
        private var task: URLSessionDownloadTask?

        func observe(_ progress: Progress, onProgress: @escaping @Sendable (Double) -> Void) {
            let token = progress.observe(\.fractionCompleted, options: [.new]) { progress, _ in
                onProgress(progress.fractionCompleted)
            }
            lock.lock()
            observation = token
            lock.unlock()
        }

        func store(_ task: URLSessionDownloadTask) {
            lock.lock()
            self.task = task
            lock.unlock()
        }

        func cancel() {
            lock.lock()
            let task = self.task
            lock.unlock()
            task?.cancel()
        }
    }


    // MARK: - Model location

    /// Folder holding `model.int8.onnx` + `tokens.txt`, alongside the
    /// WhisperKit models so cleanup stays in one place.
    static var modelFolder: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("TingMo/Models", isDirectory: true)
            .appendingPathComponent("sensevoice", isDirectory: true)
    }

    static var modelPath: URL { modelFolder.appendingPathComponent("model.int8.onnx") }
    static var tokensPath: URL { modelFolder.appendingPathComponent("tokens.txt") }

    static var isModelInstalled: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: modelPath.path) && fm.fileExists(atPath: tokensPath.path)
    }

    // MARK: - Recognizer lifecycle

    /// Builds the recognizer on first use and reuses it afterwards. Construction
    /// loads a 226 MB ONNX graph, so doing it per utterance would dominate the
    /// latency we are trying to measure.
    private func makeRecognizerIfNeeded() throws -> SherpaOnnxOfflineRecognizer {
        lock.lock()
        defer { lock.unlock() }

        if let recognizer { return recognizer }
        guard Self.isModelInstalled else { throw SpeechEngineError.modelNotDownloaded }

        // `language: ""` lets SenseVoice auto-detect across its five languages,
        // matching how DictationPipeline calls us (it passes "" for auto).
        let senseVoice = sherpaOnnxOfflineSenseVoiceModelConfig(
            model: Self.modelPath.path,
            language: "",
            useInverseTextNormalization: true
        )
        let modelConfig = sherpaOnnxOfflineModelConfig(
            tokens: Self.tokensPath.path,
            numThreads: 2,
            provider: "cpu",
            debug: 0,
            senseVoice: senseVoice
        )
        let featConfig = sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 80)
        var config = sherpaOnnxOfflineRecognizerConfig(
            featConfig: featConfig,
            modelConfig: modelConfig
        )

        let built = SherpaOnnxOfflineRecognizer(config: &config)
        recognizer = built
        return built
    }

    // MARK: - Transcription

    func transcribe(audioURL: URL, language: String) async throws -> AsyncStream<TranscriptionResult> {
        let recognizer = try makeRecognizerIfNeeded()
        let (samples, sampleRate) = try Self.readSamples(at: audioURL)

        let text = recognizer.decode(samples: samples, sampleRate: sampleRate).text

        return AsyncStream { continuation in
            continuation.yield(.final(text))
            continuation.finish()
        }
    }

    /// Reads a file into the mono 16 kHz float samples sherpa-onnx expects.
    /// The capture path already writes 16 kHz mono, but converting defensively
    /// keeps this correct for imported audio and for any future capture change.
    private static func readSamples(at url: URL) throws -> (samples: [Float], sampleRate: Int) {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw SpeechEngineError.transcriptionFailed(underlying: error)
        }

        let targetRate = 16000.0
        let sourceFormat = file.processingFormat
        let needsConversion = sourceFormat.sampleRate != targetRate
            || sourceFormat.channelCount != 1
            || sourceFormat.commonFormat != .pcmFormatFloat32

        guard needsConversion else {
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            ) else {
                throw SpeechEngineError.transcriptionFailed(underlying: ReadError.bufferAllocationFailed)
            }
            try? file.read(into: buffer)
            return (Self.floats(from: buffer), Int(sourceFormat.sampleRate))
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw SpeechEngineError.transcriptionFailed(underlying: ReadError.converterUnavailable)
        }

        // Resampling can emit more frames than a naive ratio suggests; pad the
        // capacity so the converter is never truncated mid-utterance.
        let ratio = targetRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(file.length) * ratio) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            throw SpeechEngineError.transcriptionFailed(underlying: ReadError.bufferAllocationFailed)
        }

        var reachedEnd = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if reachedEnd {
                inputStatus.pointee = .endOfStream
                return nil
            }
            guard let chunk = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 8192) else {
                inputStatus.pointee = .endOfStream
                return nil
            }
            // `read(into:)` signals end-of-file by throwing rather than by
            // returning zero frames, so a throw here is the normal way this
            // loop terminates — not a failure. Genuine read problems surface
            // as an empty result, which the pipeline already reports as
            // "no speech".
            do {
                try file.read(into: chunk)
            } catch {
                reachedEnd = true
                inputStatus.pointee = .endOfStream
                return nil
            }
            if chunk.frameLength == 0 {
                reachedEnd = true
                inputStatus.pointee = .endOfStream
                return nil
            }
            inputStatus.pointee = .haveData
            return chunk
        }

        if status == .error, let conversionError {
            throw SpeechEngineError.transcriptionFailed(underlying: conversionError)
        }

        return (Self.floats(from: output), Int(targetRate))
    }

    private static func floats(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    private enum ReadError: Error {
        case bufferAllocationFailed
        case converterUnavailable
    }
}
