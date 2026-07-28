import AVFoundation
import Foundation

/// One file required by a sherpa-onnx model.
struct SherpaOnnxModelFile: Sendable, Hashable {
    let remotePath: String
    let localName: String
    let reportsProgress: Bool

    init(_ path: String, localName: String? = nil, reportsProgress: Bool = false) {
        self.remotePath = path
        self.localName = localName ?? path
        self.reportsProgress = reportsProgress
    }
}

/// Everything that differs between offline models handled by sherpa-onnx.
///
/// The C recognizer config contains pointers allocated by the vendor helpers,
/// so it is intentionally built immediately before recognizer construction.
struct SherpaOnnxModelDescriptor: Identifiable, @unchecked Sendable {
    typealias ConfigBuilder = @Sendable (URL) -> SherpaOnnxOfflineRecognizerConfig

    let engineID: String
    let repoID: String
    let folderName: String
    let engineName: String
    let modelDisplayName: String
    let languages: [String]
    let languageDisplayName: String
    let modelSize: String
    let files: [SherpaOnnxModelFile]
    let makeRecognizerConfig: ConfigBuilder

    var id: String { engineID }

    static var builtInModels: [Self] {
        [.senseVoice, .paraformerZh]
    }

    var modelFolder: URL {
        Self.modelsDirectory.appendingPathComponent(folderName, isDirectory: true)
    }

    func fileURL(_ localName: String) -> URL {
        modelFolder.appendingPathComponent(localName)
    }

    var isModelInstalled: Bool {
        let fm = FileManager.default
        return !files.isEmpty && files.allSatisfy {
            fm.fileExists(atPath: fileURL($0.localName).path)
        }
    }

    var diskUsage: Int64 {
        let fm = FileManager.default
        return files.reduce(Int64(0)) { total, file in
            let attributes = try? fm.attributesOfItem(atPath: fileURL(file.localName).path)
            return total + ((attributes?[.size] as? Int64) ?? 0)
        }
    }

    private static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("TingMo/Models", isDirectory: true)
    }
}

/// Shared offline sherpa-onnx engine implementation.
///
/// Model-specific metadata and recognizer configuration live in a descriptor;
/// downloads, installation, loading and audio conversion stay identical across
/// SenseVoice, Paraformer and any future compatible model.
class SherpaOnnxEngine: DownloadableEngine, @unchecked Sendable {
    let descriptor: SherpaOnnxModelDescriptor
    var info: EngineInfo

    /// Guards recognizer construction and invalidation.
    private let lock = NSLock()
    private var recognizer: SherpaOnnxOfflineRecognizer?

    private let loadState = NSLock()
    private var _modelLoadState: ModelLoadState = .unloaded

    init(descriptor: SherpaOnnxModelDescriptor) {
        self.descriptor = descriptor
        self.info = EngineInfo(
            id: descriptor.engineID,
            name: descriptor.engineName,
            type: .local,
            supportedLanguages: descriptor.languages,
            supportsStreaming: false,
            modelSize: descriptor.modelSize,
            isReady: descriptor.isModelInstalled
        )
    }

    // MARK: - DownloadableEngine

    var modelLoadState: ModelLoadState {
        loadState.lock()
        defer { loadState.unlock() }
        return _modelLoadState
    }

    var isModelDownloaded: Bool { descriptor.isModelInstalled }

    var diskUsage: Int64 { descriptor.diskUsage }

    final func downloadModel(
        endpoint: String? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        if descriptor.isModelInstalled { return }

        let host = (endpoint?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? DownloadSourcePreference.defaultEndpoint
        let base = host.hasSuffix("/") ? String(host.dropLast()) : host

        let downloads: [(file: SherpaOnnxModelFile, url: URL)] = try descriptor.files.map { file in
            guard let url = URL(
                string: "\(base)/\(descriptor.repoID)/resolve/main/\(file.remotePath)"
            ) else {
                throw SpeechEngineError.modelNotFound
            }
            return (file, url)
        }

        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent(
            "\(descriptor.engineID)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        for download in downloads {
            try Task.checkCancellation()
            let destination = staging.appendingPathComponent(download.file.localName)
            try fm.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try await Self.download(
                from: download.url,
                to: destination,
                progress: download.file.reportsProgress ? progress : nil
            )
        }
        try Task.checkCancellation()

        // Publish the complete directory in one move. A cancelled or failed
        // transfer remains in the temporary directory and can never satisfy the
        // descriptor's all-files installation check.
        let finalFolder = descriptor.modelFolder
        try fm.createDirectory(
            at: finalFolder.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? fm.removeItem(at: finalFolder)
        try fm.moveItem(at: staging, to: finalFolder)

        info.isReady = true
    }

    func loadModel() async throws {
        guard descriptor.isModelInstalled else {
            throw SpeechEngineError.modelNotDownloaded
        }
        if isModelLoaded { return }

        setLoadState(.loading)
        do {
            _ = try makeRecognizerIfNeeded()
            setLoadState(.loaded)
        } catch {
            setLoadState(.failed(error.localizedDescription))
            throw error
        }
    }

    @discardableResult
    func deleteLocalFiles() -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: descriptor.modelFolder.path) else { return false }
        do {
            try fm.removeItem(at: descriptor.modelFolder)
        } catch {
            return false
        }

        lock.lock()
        recognizer = nil
        lock.unlock()

        setLoadState(.unloaded)
        info.isReady = false
        return true
    }

    private func setLoadState(_ state: ModelLoadState) {
        loadState.lock()
        _modelLoadState = state
        loadState.unlock()
    }

    // MARK: - Download helpers

    private static let downloadSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 3600
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

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

    // MARK: - Recognizer lifecycle

    private func makeRecognizerIfNeeded() throws -> SherpaOnnxOfflineRecognizer {
        lock.lock()
        defer { lock.unlock() }

        if let recognizer { return recognizer }
        guard descriptor.isModelInstalled else {
            throw SpeechEngineError.modelNotDownloaded
        }

        var config = descriptor.makeRecognizerConfig(descriptor.modelFolder)
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
                throw SpeechEngineError.transcriptionFailed(
                    underlying: ReadError.bufferAllocationFailed
                )
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

        let ratio = targetRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(file.length) * ratio) + 4096
        guard let output = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: capacity
        ) else {
            throw SpeechEngineError.transcriptionFailed(
                underlying: ReadError.bufferAllocationFailed
            )
        }

        var reachedEnd = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if reachedEnd {
                inputStatus.pointee = .endOfStream
                return nil
            }
            guard let chunk = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: 8192
            ) else {
                inputStatus.pointee = .endOfStream
                return nil
            }
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
