import XCTest
@testable import TingMo

final class WhisperKitEngineTokenizerTests: XCTestCase {

    private func model(variant: String, importedFolder: URL? = nil) -> WhisperKitEngine.WhisperModel {
        WhisperKitEngine.WhisperModel(
            id: "test",
            variant: variant,
            name: "Test",
            size: "1 MB",
            importedFolder: importedFolder
        )
    }

    // MARK: - tokenizerRepo(for:)

    func testMapsPlainVariantsToMatchingOpenAIRepo() {
        XCTAssertEqual(
            WhisperKitEngine.tokenizerRepo(for: model(variant: "openai_whisper-tiny")),
            "openai/whisper-tiny"
        )
        XCTAssertEqual(
            WhisperKitEngine.tokenizerRepo(for: model(variant: "openai_whisper-medium")),
            "openai/whisper-medium"
        )
        XCTAssertEqual(
            WhisperKitEngine.tokenizerRepo(for: model(variant: "openai_whisper-large-v3")),
            "openai/whisper-large-v3"
        )
    }

    func testTurboVariantSharesLargeV3Tokenizer() {
        XCTAssertEqual(
            WhisperKitEngine.tokenizerRepo(for: model(variant: "openai_whisper-large-v3_turbo")),
            "openai/whisper-large-v3"
        )
    }

    func testV20240930VariantsShareLargeV3Tokenizer() {
        XCTAssertEqual(
            WhisperKitEngine.tokenizerRepo(for: model(variant: "openai_whisper-large-v3-v20240930")),
            "openai/whisper-large-v3"
        )
        XCTAssertEqual(
            WhisperKitEngine.tokenizerRepo(for: model(variant: "openai_whisper-large-v3-v20240930_626MB")),
            "openai/whisper-large-v3"
        )
    }

    func testQuantizedAndCompileSuffixesAreStripped() {
        XCTAssertEqual(
            WhisperKitEngine.tokenizerRepo(for: model(variant: "openai_whisper-small_216MB")),
            "openai/whisper-small"
        )
        XCTAssertEqual(
            WhisperKitEngine.tokenizerRepo(for: model(variant: "openai_whisper-large-v2_turbo_955MB")),
            "openai/whisper-large-v2"
        )
    }

    func testUnknownVariantHasNoTokenizerRepo() {
        XCTAssertNil(WhisperKitEngine.tokenizerRepo(for: model(variant: "distil-whisper_distil-large-v3")))
    }

    func testImportedModelHasNoTokenizerRepo() {
        let imported = model(
            variant: "openai_whisper-tiny",
            importedFolder: URL(fileURLWithPath: "/tmp/imported")
        )
        XCTAssertNil(WhisperKitEngine.tokenizerRepo(for: imported))
    }

    // MARK: - isTokenizerBundled(for:)

    func testTokenizerBundledRequiresBothFilesInModelFolder() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenizer-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let imported = model(variant: "openai_whisper-tiny", importedFolder: folder)
        XCTAssertFalse(WhisperKitEngine.isTokenizerBundled(for: imported))

        try Data("{}".utf8).write(to: folder.appendingPathComponent("tokenizer.json"))
        XCTAssertFalse(WhisperKitEngine.isTokenizerBundled(for: imported))

        try Data("{}".utf8).write(to: folder.appendingPathComponent("tokenizer_config.json"))
        XCTAssertTrue(WhisperKitEngine.isTokenizerBundled(for: imported))
    }
}
