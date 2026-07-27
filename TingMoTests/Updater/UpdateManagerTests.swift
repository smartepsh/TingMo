import Foundation
import XCTest
@testable import TingMo

final class UpdateManagerTests: XCTestCase {
    func testVersionParsesTagPrefixAndBuildMetadata() throws {
        XCTAssertEqual(try XCTUnwrap(AppVersion("v1.2.3")).description, "1.2.3")
        XCTAssertEqual(try XCTUnwrap(AppVersion("1.2.3+42")), AppVersion("1.2.3"))
    }

    func testVersionComparisonUsesNumericComponents() throws {
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.9.0")), try XCTUnwrap(AppVersion("1.10.0")))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.2.3")), try XCTUnwrap(AppVersion("2.0.0")))
        XCTAssertEqual(AppVersion("1.2"), AppVersion("1.2.0"))
    }

    func testVersionRejectsMalformedValues() {
        XCTAssertNil(AppVersion("release-1.2.3"))
        XCTAssertNil(AppVersion("1.two.3"))
        XCTAssertNil(AppVersion(""))
    }

    func testDecodesLatestReleaseAndSelectsDMGAsset() throws {
        let payload = #"""
        {
          "tag_name": "v1.2.0",
          "name": "TingMo 1.2.0",
          "body": "Bug fixes",
          "html_url": "https://github.com/smartepsh/TingMo/releases/tag/v1.2.0",
          "assets": [
            {
              "name": "TingMo-v1.2.0.dmg.sha256",
              "browser_download_url": "https://example.com/TingMo-v1.2.0.dmg.sha256",
              "digest": "sha256:ignored"
            },
            {
              "name": "TingMo-v1.2.0.dmg",
              "browser_download_url": "https://example.com/TingMo-v1.2.0.dmg",
              "digest": "sha256:abcdef"
            }
          ]
        }
        """#

        let release = try GitHubRelease.decode(Data(payload.utf8))

        XCTAssertEqual(release.version, AppVersion("1.2.0"))
        XCTAssertEqual(release.version?.description, "1.2.0")
        XCTAssertEqual(release.diskImageAsset?.name, "TingMo-v1.2.0.dmg")
        XCTAssertEqual(release.diskImageAsset?.sha256Digest, "abcdef")
    }

    func testMalformedReleasePayloadThrows() {
        XCTAssertThrowsError(try GitHubRelease.decode(Data(#"{"name":"missing tag"}"#.utf8)))
    }
}
