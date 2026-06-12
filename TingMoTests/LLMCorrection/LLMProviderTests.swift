import XCTest
@testable import TingMo

final class LLMProviderTests: XCTestCase {

    func testProvidersDecodeFromRawValues() throws {
        func decode(_ raw: String) throws -> LLMProviderID {
            try JSONDecoder().decode(LLMProviderID.self, from: Data("\"\(raw)\"".utf8))
        }
        XCTAssertEqual(try decode("openai-compatible"), .openAICompatible)
        XCTAssertEqual(try decode("deepseek"), .deepseek)
        XCTAssertEqual(try decode("anthropic"), .anthropic)
        XCTAssertThrowsError(try decode("lmstudio"), "retired providers are gone for good")
    }

    func testLoopbackHostDetection() {
        XCTAssertTrue(LLMConfig.isLoopbackHost(in: "http://localhost:8000/v1/chat/completions"))
        XCTAssertTrue(LLMConfig.isLoopbackHost(in: "http://127.0.0.1:1234"))
        XCTAssertFalse(LLMConfig.isLoopbackHost(in: "https://api.deepseek.com/v1/chat/completions"))
        XCTAssertFalse(LLMConfig.isLoopbackHost(in: "not a url"))
    }
}
