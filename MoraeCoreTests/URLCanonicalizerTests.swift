import MoraeCore
import XCTest

final class URLCanonicalizerTests: XCTestCase {
    func testCanonicalizationTable() throws {
        let cases: [(input: String, expected: String)] = [
            (
                "HTTPS://Example.COM:443#section",
                "https://example.com/"
            ),
            (
                "http://EXAMPLE.com:80/path?b=2&a=1&utm_source=feed",
                "http://example.com/path?a=1&b=2"
            ),
            (
                "https://example.com:8443/path?gclid=x&ref=r&keep=yes",
                "https://example.com:8443/path?keep=yes"
            ),
            (
                "https://example.com/path?z=2&z=1&FBCLID=x",
                "https://example.com/path?z=1&z=2"
            ),
            (
                "https://example.com/path?utm_custom=x",
                "https://example.com/path"
            ),
        ]
        let canonicalizer = URLCanonicalizer()

        for item in cases {
            let result = try canonicalizer.canonicalize(
                XCTUnwrap(URL(string: item.input))
            )
            XCTAssertEqual(
                result.absoluteString,
                item.expected,
                "Input: \(item.input)"
            )
        }
    }

    func testRejectsURLWithoutHost() throws {
        XCTAssertThrowsError(
            try URLCanonicalizer().canonicalize(
                XCTUnwrap(URL(string: "file:///tmp/article"))
            )
        ) { error in
            XCTAssertEqual(
                error as? URLCanonicalizationError,
                .missingSchemeOrHost
            )
        }
    }
}
