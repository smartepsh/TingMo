import XCTest
@testable import TingMo

final class LLMModelListFetcherTests: XCTestCase {

    func testParsesOpenAIStyleModelList() throws {
        let payload = """
        {"object":"list","data":[
            {"id":"Qwen3-4B-Instruct-2507-MLX-4bit","object":"model","created":1,"owned_by":"omlx"},
            {"id":"gpt-oss-120b-MXFP4-Q8","object":"model","created":2,"owned_by":"omlx"}
        ]}
        """
        let models = try LLMModelListFetcher.parse(Data(payload.utf8))
        XCTAssertEqual(models, ["Qwen3-4B-Instruct-2507-MLX-4bit", "gpt-oss-120b-MXFP4-Q8"])
    }

    func testPreservesServerOrdering() throws {
        let payload = #"{"data":[{"id":"b"},{"id":"a"},{"id":"c"}]}"#
        XCTAssertEqual(try LLMModelListFetcher.parse(Data(payload.utf8)), ["b", "a", "c"])
    }

    func testEmptyCatalogParsesToEmptyList() throws {
        XCTAssertEqual(try LLMModelListFetcher.parse(Data(#"{"data":[]}"#.utf8)), [])
    }

    func testMalformedPayloadThrowsInvalidResponse() {
        XCTAssertThrowsError(try LLMModelListFetcher.parse(Data("not json".utf8))) { error in
            guard case LLMModelListFetcher.FetchError.invalidResponse = error else {
                return XCTFail("expected invalidResponse, got \(error)")
            }
        }
    }
}
