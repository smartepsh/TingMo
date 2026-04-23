import AVFoundation
import CoreAudio
import Foundation

/// Captures microphone audio to a temporary WAV file in the format
/// WhisperKit expects: 16 kHz mono Float32 PCM.
///
/// Usage:
///   let capture = AudioCapture()
///   try capture.start()
///   ...
///   let url = try capture.stop()  // WAV on disk, ready to transcribe
final class AudioCapture {
    enum CaptureError: Error, LocalizedError {
        case alreadyRunning
        case notRunning
        case engineFailure(underlying: Error)
        case writerFailure(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .alreadyRunning: "Audio capture is already running."
            case .notRunning: "Audio capture is not running."
            case .engineFailure(let e): "Audio engine error: \(e.localizedDescription)"
            case .writerFailure(let e): "Audio file writer error: \(e.localizedDescription)"
            }
        }
    }

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var fileURL: URL?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var isRunning = false

    /// Last-known audio level 0.0–1.0 (peak of recent buffer). Observable via polling.
    private(set) var audioLevel: Float = 0.0
    /// Running max peak across the whole capture session, for diagnostics.
    private(set) var sessionPeak: Float = 0.0
    private var totalFrames: Int = 0

    /// Start capture, optionally binding a specific input device by UID.
    /// When `preferredDeviceUID` is nil or unresolvable, the system default
    /// input is used.
    func start(preferredDeviceUID: String? = nil) throws {
        guard !isRunning else { throw CaptureError.alreadyRunning }
        sessionPeak = 0
        totalFrames = 0

        let input = engine.inputNode

        if let uid = preferredDeviceUID,
           let deviceID = AudioDeviceEnumerator.deviceID(forUID: uid) {
            do {
                try Self.setInputDevice(on: input, deviceID: deviceID)
                NSLog("[TingMo] AudioCapture bound inputNode to device uid=\(uid) id=\(deviceID)")
            } catch {
                NSLog("[TingMo] AudioCapture failed to bind device uid=\(uid): \(error); falling back to system default")
            }
        }

        let inputFormat = input.outputFormat(forBus: 0)
        NSLog("[TingMo] AudioCapture start: input format sr=\(inputFormat.sampleRate) ch=\(inputFormat.channelCount) fmt=\(inputFormat.commonFormat.rawValue)")

        // Whisper wants 16 kHz mono Float32.
        guard let wantFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw CaptureError.engineFailure(underlying: NSError(domain: "AudioCapture", code: -1))
        }
        targetFormat = wantFormat

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tingmo-\(UUID().uuidString).wav")
        fileURL = url

        do {
            // AVAudioFile written in Whisper's target format directly.
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
            file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw CaptureError.writerFailure(underlying: error)
        }

        if inputFormat.sampleRate != wantFormat.sampleRate || inputFormat.channelCount != wantFormat.channelCount {
            converter = AVAudioConverter(from: inputFormat, to: wantFormat)
        } else {
            converter = nil
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }

        engine.prepare()

        do {
            try engine.start()
            NSLog("[TingMo] AudioCapture engine started; running=\(engine.isRunning)")
        } catch {
            input.removeTap(onBus: 0)
            file = nil
            try? FileManager.default.removeItem(at: url)
            throw CaptureError.engineFailure(underlying: error)
        }

        isRunning = true
    }

    /// Stop capture and return the written WAV URL.
    @discardableResult
    func stop() throws -> URL {
        guard isRunning else { throw CaptureError.notRunning }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRunning = false
        NSLog("[TingMo] AudioCapture stop: sessionPeak=\(sessionPeak) totalFrames=\(totalFrames)")

        let url = fileURL
        file = nil
        fileURL = nil
        converter = nil
        targetFormat = nil
        audioLevel = 0.0

        guard let url else { throw CaptureError.notRunning }
        return url
    }

    /// Cancel capture and delete the partial file.
    func cancel() {
        if isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            isRunning = false
        }
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        file = nil
        fileURL = nil
        converter = nil
        targetFormat = nil
        audioLevel = 0.0
    }

    // MARK: - Buffer handling

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        updateLevel(buffer)

        guard let file else { return }

        let output: AVAudioPCMBuffer
        if let converter, let targetFormat {
            let ratio = targetFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            var error: NSError?
            var supplied = false
            let status = converter.convert(to: converted, error: &error) { _, inputStatus in
                if supplied {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                supplied = true
                inputStatus.pointee = .haveData
                return buffer
            }
            if status == .error || converted.frameLength == 0 { return }
            output = converted
        } else {
            output = buffer
        }

        try? file.write(from: output)
    }

    private func updateLevel(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }
        var peak: Float = 0
        let samples = channelData[0]
        for i in 0..<frameLength {
            let v = abs(samples[i])
            if v > peak { peak = v }
        }
        audioLevel = min(peak, 1.0)
        if peak > sessionPeak { sessionPeak = peak }
        totalFrames += frameLength
    }

    // MARK: - Device binding

    /// Bind the input node's underlying HAL audio unit to a specific device.
    /// Must be called before `engine.start()`.
    private static func setInputDevice(on input: AVAudioInputNode, deviceID: AudioDeviceID) throws {
        var id = deviceID
        let unit = input.audioUnit
        guard let unit else {
            throw CaptureError.engineFailure(underlying: NSError(domain: "AudioCapture", code: -2))
        }
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw CaptureError.engineFailure(underlying: NSError(domain: NSOSStatusErrorDomain, code: Int(status)))
        }
    }
}
