import AVFoundation
import XCTest

@testable import TingMo

/// Exercises the real sherpa-onnx runtime against real audio. These tests are
/// skipped when the model is not installed, so a fresh checkout still passes.
final class SenseVoiceEngineTests: XCTestCase {
    /// Reference clips shipped with the model release, used to prove the engine
    /// decodes without relying on a hand-made fixture.
    private var testWavsDirectory: URL? {
        let candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SpeechEngine
            .deletingLastPathComponent()  // TingMoTests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent(
                ".deps/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17/test_wavs",
                isDirectory: true
            )
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private func skipUnlessModelInstalled() throws {
        try XCTSkipUnless(
            SenseVoiceEngine.isModelInstalled,
            "SenseVoice model not installed; see scripts/build-sherpa-onnx.sh"
        )
    }

    func testEngineIsReadyWhenModelInstalled() throws {
        try skipUnlessModelInstalled()
        let engine = SenseVoiceEngine()
        XCTAssertTrue(engine.info.isReady)
        XCTAssertTrue(engine.supportsLanguage("zh"))
        XCTAssertFalse(engine.supportsLanguage("de"), "German should stay on Whisper")
    }

    func testTranscribesEnglishReferenceClip() async throws {
        try skipUnlessModelInstalled()
        let wavs = try XCTUnwrap(testWavsDirectory, "reference wavs missing")
        let engine = SenseVoiceEngine()

        let stream = try await engine.transcribe(
            audioURL: wavs.appendingPathComponent("en.wav"),
            language: ""
        )

        var text = ""
        for await result in stream {
            switch result {
            case .partial(let s), .final(let s): text = s
            }
        }

        XCTAssertFalse(
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "engine returned no text"
        )
        // Assert on a stable phrase rather than the full string so punctuation
        // or ITN changes in a future model release don't make this brittle.
        XCTAssertTrue(
            text.lowercased().contains("called for the boy"),
            "unexpected transcription: \(text)"
        )
    }

    func testTranscribesMandarinReferenceClip() async throws {
        try skipUnlessModelInstalled()
        let wavs = try XCTUnwrap(testWavsDirectory, "reference wavs missing")
        let engine = SenseVoiceEngine()

        let stream = try await engine.transcribe(
            audioURL: wavs.appendingPathComponent("zh.wav"),
            language: ""
        )

        var text = ""
        for await result in stream {
            switch result {
            case .partial(let s), .final(let s): text = s
            }
        }

        XCTAssertFalse(
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "engine returned no text"
        )
        // The leading 开 is the tell: the WSYue Cantonese fine-tune drops it and
        // returns "放时间…", a silent deletion that still reads as fluent Chinese.
        // Asserting on it catches a wrong model being installed — merely checking
        // for CJK characters would not.
        XCTAssertTrue(
            text.contains("开放时间"),
            "unexpected transcription (wrong model installed?): \(text)"
        )
    }

    /// Resampling correctness matters because capture format may change; a
    /// 44.1 kHz source must still decode to the same words.
    func testResamplesNonNativeSampleRate() async throws {
        try skipUnlessModelInstalled()
        let wavs = try XCTUnwrap(testWavsDirectory, "reference wavs missing")

        let source = try AVAudioFile(forReading: wavs.appendingPathComponent("en.wav"))
        let upsampledURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sensevoice-44k-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: upsampledURL) }

        let outFormat = try XCTUnwrap(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)
        )
        // Held as an Optional so it can be released before the engine reads the
        // file: AVAudioFile only flushes to disk on deallocation, and a still-open
        // writer leaves a zero-length file behind.
        var outFile: AVAudioFile? = try AVAudioFile(forWriting: upsampledURL, settings: outFormat.settings)
        let converter = try XCTUnwrap(AVAudioConverter(from: source.processingFormat, to: outFormat))

        let inBuffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: AVAudioFrameCount(source.length))
        )
        try source.read(into: inBuffer)
        let outCapacity = AVAudioFrameCount(Double(source.length) * 44100.0 / source.processingFormat.sampleRate) + 4096
        let outBuffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity))

        var fed = false
        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, status in
            if fed {
                status.pointee = .endOfStream
                return nil
            }
            fed = true
            status.pointee = .haveData
            return inBuffer
        }
        XCTAssertNil(error)
        try outFile?.write(from: outBuffer)
        outFile = nil

        let engine = SenseVoiceEngine()
        let stream = try await engine.transcribe(audioURL: upsampledURL, language: "")
        var text = ""
        for await result in stream {
            switch result {
            case .partial(let s), .final(let s): text = s
            }
        }

        XCTAssertTrue(
            text.lowercased().contains("called for the boy"),
            "resampled audio decoded differently: \(text)"
        )
    }
}

/// Exercises the real download path end to end. Separate from the decode tests
/// because it pulls ~158 MB over the network.
final class SenseVoiceDownloadTests: XCTestCase {
    func testDownloadsAndInstallsModel() async throws {
        try XCTSkipIf(
            SenseVoiceEngine.isModelInstalled,
            "model already installed; move it aside to exercise the download"
        )

        let engine = SenseVoiceEngine()
        XCTAssertFalse(engine.info.isReady)

        let progressSeen = NSMutableArray()
        try await engine.downloadModel(endpoint: nil) { fraction in
            synchronized(progressSeen) { progressSeen.add(fraction) }
        }

        XCTAssertTrue(SenseVoiceEngine.isModelInstalled, "model files missing after download")
        XCTAssertTrue(engine.info.isReady, "isReady not flipped after download")
        XCTAssertGreaterThan(engine.diskUsage, 200_000_000, "model smaller than expected")

        // Require *intermediate* progress, not just the final 1.0 the download
        // reports unconditionally on success. Asserting merely "some progress
        // arrived" passed even while the delegate was never wired up, so the
        // bar sat at zero for the entire 239 MB transfer.
        let fractions = (progressSeen as? [Double]) ?? []
        let midway = fractions.filter { $0 > 0.01 && $0 < 0.99 }
        XCTAssertFalse(
            midway.isEmpty,
            "no intermediate progress reported (saw \(fractions.count) values: \(fractions.prefix(5)))"
        )

        // The engine must be usable immediately after downloading.
        try await engine.loadModel()
        XCTAssertTrue(engine.isModelLoaded)
    }
}

private func synchronized(_ lock: Any, _ body: () -> Void) {
    objc_sync_enter(lock)
    defer { objc_sync_exit(lock) }
    body()
}
