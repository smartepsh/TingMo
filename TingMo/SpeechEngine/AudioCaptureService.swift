import AVFoundation
import Foundation
import Observation

/// Audio format requirements for speech engines.
struct AudioFormatRequirement: Sendable {
    let sampleRate: Double
    let channelCount: Int
    let commonFormat: AVAudioCommonFormat

    static let whisperKit = AudioFormatRequirement(sampleRate: 16000, channelCount: 1, commonFormat: .pcmFormatFloat32)
    static let appleSpeech = AudioFormatRequirement(sampleRate: 16000, channelCount: 1, commonFormat: .pcmFormatInt16)
    static let defaultFormat = AudioFormatRequirement(sampleRate: 16000, channelCount: 1, commonFormat: .pcmFormatFloat32)
}

/// Captures audio from the selected input device and provides it in the required format.
@Observable
final class AudioCaptureService {
    private var audioEngine: AVAudioEngine?
    private var outputFile: AVAudioFile?
    private(set) var isCapturing = false
    private(set) var currentAudioLevel: Float = 0

    /// Start capturing audio and save to a temporary file.
    /// - Parameters:
    ///   - deviceUID: The UID of the audio input device to use, or nil for system default.
    ///   - format: The required output audio format.
    /// - Returns: URL to the audio file being written.
    func startCapture(deviceUID: String?, format: AudioFormatRequirement = .defaultFormat) throws -> URL {
        guard !isCapturing else { throw AudioCaptureError.alreadyCapturing }

        let engine = AVAudioEngine()

        // Select input device if specified
        if let uid = deviceUID {
            try selectInputDevice(uid: uid, on: engine)
        }

        // Prepare engine to sync internal state after device change
        engine.prepare()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create output format
        guard let outputFormat = AVAudioFormat(
            commonFormat: format.commonFormat,
            sampleRate: format.sampleRate,
            channels: AVAudioChannelCount(format.channelCount),
            interleaved: false
        ) else {
            throw AudioCaptureError.formatCreationFailed
        }

        // Create temporary file for output
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        let file = try AVAudioFile(
            forWriting: tempURL,
            settings: outputFormat.settings,
            commonFormat: outputFormat.commonFormat,
            interleaved: false
        )

        // Install tap with format conversion
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioCaptureError.converterCreationFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.updateAudioLevel(buffer: buffer)
            self?.convertAndWrite(buffer: buffer, converter: converter, outputFormat: outputFormat, file: file)
        }

        try engine.start()
        audioEngine = engine
        outputFile = file
        isCapturing = true

        return tempURL
    }

    /// Stop capturing audio.
    func stopCapture() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        outputFile = nil
        isCapturing = false
        currentAudioLevel = 0
    }

    /// Discard the capture — stop and delete the file.
    func discardCapture(at url: URL) {
        stopCapture()
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Device Selection

    private func selectInputDevice(uid: String, on engine: AVAudioEngine) throws {
        guard var deviceID = AudioDeviceEnumerator.deviceID(forUID: uid) else {
            throw AudioCaptureError.deviceNotFound
        }
        let result = AudioUnitSetProperty(
            engine.inputNode.audioUnit!,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard result == noErr else {
            throw AudioCaptureError.deviceSelectionFailed
        }
    }

    // MARK: - Audio Level Metering

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frames {
            let sample = channelData[0][i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(max(frames, 1)))
        let db = 20 * log10(max(rms, 1e-7))
        // Normalize dB to 0–1 range (roughly -60dB to 0dB)
        let normalized = max(0, min(1, (db + 60) / 60))
        DispatchQueue.main.async {
            self.currentAudioLevel = normalized
        }
    }

    // MARK: - Format Conversion

    private func convertAndWrite(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat,
        file: AVAudioFile
    ) {
        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate
        )
        guard frameCapacity > 0,
              let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity)
        else { return }

        var error: NSError?
        var hasData = true
        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            if hasData {
                hasData = false
                outStatus.pointee = .haveData
                return buffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }

        if error == nil, convertedBuffer.frameLength > 0 {
            try? file.write(from: convertedBuffer)
        }
    }
}

enum AudioCaptureError: Error, LocalizedError {
    case alreadyCapturing
    case formatCreationFailed
    case converterCreationFailed
    case deviceNotFound
    case deviceSelectionFailed

    var errorDescription: String? {
        switch self {
        case .alreadyCapturing: "Audio capture is already in progress."
        case .formatCreationFailed: "Failed to create the required audio format."
        case .converterCreationFailed: "Failed to create audio format converter."
        case .deviceNotFound: "The specified audio device was not found."
        case .deviceSelectionFailed: "Failed to select the audio input device."
        }
    }
}
