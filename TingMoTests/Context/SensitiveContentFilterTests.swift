import XCTest
@testable import TingMo

final class SensitiveContentFilterTests: XCTestCase {

    // MARK: - keep

    func testKeepsOrdinaryText() {
        assertKeep("Hello world, this is just a normal sentence.")
    }

    func testKeepsBareKeywordMentionInProse() {
        // No assignment form — just talking about passwords.
        assertKeep("Click 'Forgot password' if you need to reset your password.")
    }

    func testKeepsRandomLookingUuid() {
        // UUIDs are high-entropy but not credentials.
        assertKeep("Request id: 550e8400-e29b-41d4-a716-446655440000")
    }

    // MARK: - drop: structured tokens

    func testDropsOpenAIStyleKey() {
        assertDrop("Use sk-proj-abcDEF1234567890ghIJKL to call the API.", reason: "openai-style-key")
    }

    func testDropsGitHubToken() {
        assertDrop("token: ghp_abcdefghijklmnopqrstuvwxyz0123456789AB", reasonContains: "github-token")
    }

    func testDropsAWSAccessKey() {
        assertDrop("AKIAIOSFODNN7EXAMPLE leaked here", reason: "aws-access-key")
    }

    func testDropsSlackToken() {
        assertDrop("xoxb-1234567890-abcdefghij", reason: "slack-token")
    }

    func testDropsJWT() {
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4ifQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        assertDrop("Authorization: Bearer \(jwt)", reasonContains: "jwt")
    }

    func testDropsPrivateKeyBlock() {
        let pem = """
        -----BEGIN RSA PRIVATE KEY-----
        MIIEpAIBAAKCAQEAxxxxxxxxxxxxxxxxxxxx
        -----END RSA PRIVATE KEY-----
        """
        assertDrop(pem, reason: "private-key")
    }

    // MARK: - drop: credit card via Luhn

    func testDropsValidCreditCardNumber() {
        // 4111 1111 1111 1111 is the canonical Visa test number (valid Luhn).
        assertDrop("Card: 4111 1111 1111 1111 expires 12/30", reason: "credit-card")
    }

    func testKeepsInvalidLuhnDigits() {
        // 16 digits but bad Luhn — should not be flagged as a card.
        assertKeep("Order number 1234 5678 9012 3456 confirmed.")
    }

    // MARK: - redact: assignment forms

    func testRedactsPasswordAssignment() {
        let decision = SensitiveContentFilter.evaluate("user=alice password=hunter2!!")
        switch decision {
        case .redact(let text, _):
            XCTAssertFalse(text.contains("hunter2"), "redacted text leaked password: \(text)")
            XCTAssertTrue(text.contains("***"))
        default:
            XCTFail("expected redact, got \(decision)")
        }
    }

    func testRedactsApiKeyColonAssignment() {
        let decision = SensitiveContentFilter.evaluate(#"api_key: "super-secret-value-1234""#)
        switch decision {
        case .redact(let text, _):
            XCTAssertFalse(text.contains("super-secret-value-1234"))
            XCTAssertTrue(text.contains("***"))
        default:
            XCTFail("expected redact, got \(decision)")
        }
    }

    func testRedactsMultipleAssignmentsOnSameLine() {
        let decision = SensitiveContentFilter.evaluate("password=abcd1234 token=zyxw9876")
        switch decision {
        case .redact(let text, _):
            XCTAssertFalse(text.contains("abcd1234"))
            XCTAssertFalse(text.contains("zyxw9876"))
        default:
            XCTFail("expected redact, got \(decision)")
        }
    }

    // MARK: - helpers

    private func assertKeep(_ text: String, file: StaticString = #file, line: UInt = #line) {
        let decision = SensitiveContentFilter.evaluate(text)
        XCTAssertEqual(decision, .keep, "expected .keep for \(text), got \(decision)", file: file, line: line)
    }

    private func assertDrop(_ text: String, reason: String, file: StaticString = #file, line: UInt = #line) {
        let decision = SensitiveContentFilter.evaluate(text)
        XCTAssertEqual(decision, .drop(reason: reason), file: file, line: line)
    }

    private func assertDrop(_ text: String, reasonContains: String, file: StaticString = #file, line: UInt = #line) {
        let decision = SensitiveContentFilter.evaluate(text)
        switch decision {
        case .drop(let r):
            XCTAssertTrue(r.contains(reasonContains), "expected reason containing \(reasonContains), got \(r)", file: file, line: line)
        default:
            XCTFail("expected drop, got \(decision)", file: file, line: line)
        }
    }
}
