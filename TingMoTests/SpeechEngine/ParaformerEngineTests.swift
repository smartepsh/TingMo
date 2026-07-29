import XCTest

@testable import TingMo

/// Exercises Paraformer through the same shared sherpa-onnx engine used by the app.
/// Model files are intentionally not bundled; decode tests skip until the user
/// has downloaded Paraformer from Settings.
final class ParaformerEngineTests: XCTestCase {
    private var testWavsDirectory: URL? {
        let candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SpeechEngine
            .deletingLastPathComponent()  // TingMoTests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent(
                ".deps/sherpa-onnx-paraformer-zh-2024-03-09/test_wavs",
                isDirectory: true
            )
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private func skipUnlessModelInstalled() throws {
        try XCTSkipUnless(
            ParaformerEngine.isModelInstalled,
            "Paraformer model not installed; download it from Speech Recognition settings"
        )
    }

    func testDescriptorAndLanguageScope() {
        let engine = ParaformerEngine()
        XCTAssertEqual(engine.info.id, "paraformer-zh")
        XCTAssertEqual(ParaformerEngine.repoID, "csukuangfj/sherpa-onnx-paraformer-zh-2024-03-09")
        XCTAssertTrue(engine.supportsLanguage("zh"))
        XCTAssertTrue(engine.supportsLanguage("en"))
        XCTAssertFalse(engine.supportsLanguage("yue"))
        XCTAssertFalse(engine.supportsLanguage("ja"))
        XCTAssertFalse(engine.supportsLanguage("ko"))
        XCTAssertEqual(engine.info.isReady, ParaformerEngine.isModelInstalled)
        XCTAssertEqual(
            SherpaOnnxModelDescriptor.builtInModels.map(\.engineID),
            ["sensevoice", "paraformer-zh"]
        )
    }

    func testTranscribesMandarinReferenceClip() async throws {
        try skipUnlessModelInstalled()
        let wavs = try XCTUnwrap(testWavsDirectory, "Paraformer reference wavs missing")
        let text = try await transcribe(
            with: ParaformerEngine(),
            audioURL: wavs.appendingPathComponent("0.wav")
        )

        // Stable phrase from sherpa-onnx's published int8 reference output.
        XCTAssertTrue(text.contains("研究感兴趣"), "unexpected transcription: \(text)")
    }

    func testTranscribesMixedChineseEnglishReferenceClip() async throws {
        try skipUnlessModelInstalled()
        let wavs = try XCTUnwrap(testWavsDirectory, "Paraformer reference wavs missing")
        let text = try await transcribe(
            with: ParaformerEngine(),
            audioURL: wavs.appendingPathComponent("2-zh-en.wav")
        )
        let normalized = text.lowercased()

        // This clip says “yesterday was 星期一, today is Tuesday, 明天是星期三”.
        // Assert one stable token from each language so an accidental
        // monolingual model cannot pass by returning merely non-empty text.
        XCTAssertTrue(normalized.contains("tuesday"), "English missing: \(text)")
        XCTAssertTrue(text.contains("明天是星期三"), "Mandarin missing: \(text)")
    }

    private func transcribe(
        with engine: ParaformerEngine,
        audioURL: URL
    ) async throws -> String {
        let stream = try await engine.transcribe(audioURL: audioURL, language: "")
        var text = ""
        for await result in stream {
            switch result {
            case .partial(let value), .final(let value):
                text = value
            }
        }
        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        return text
    }
}
