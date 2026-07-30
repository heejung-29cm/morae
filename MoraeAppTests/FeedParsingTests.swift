import MoraeCore
import XCTest
@testable import MoraeApp

final class FeedParsingTests: XCTestCase {
    func testRSSMapsOnlyMetadataAndSkipsInvalidItems() throws {
        let source = makeSource(name: "RSS Source")
        let data = try FixtureLoader.data(named: "rss-feed", extension: "xml")

        let candidates = try FeedMetadataParser().parseRSS(
            data: data,
            source: source
        )

        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates[0].title, "Swift concurrency patterns")
        XCTAssertEqual(
            candidates[0].articleURL.absoluteString,
            "https://fixture.invalid/articles/concurrency?utm_source=test"
        )
        XCTAssertEqual(candidates[0].sourceID, source.id)
        XCTAssertEqual(candidates[0].sourceName, source.name)
        XCTAssertEqual(candidates[0].sourceURL, source.feedURL)
        XCTAssertTrue(candidates[0].isOfficialSource)
        XCTAssertEqual(
            candidates[0].publishedAt,
            Date(timeIntervalSince1970: 1_785_294_000)
        )
        XCTAssertEqual(candidates[1].title, "Date is optional")
        XCTAssertNil(candidates[1].publishedAt)
    }

    func testRSSParserRejectsNonRSSInput() throws {
        XCTAssertThrowsError(
            try FeedMetadataParser().parseRSS(
                data: Data(
                    """
                    <?xml version="1.0"?>
                    <feed xmlns="http://www.w3.org/2005/Atom"></feed>
                    """.utf8
                ),
                source: makeSource(name: "Wrong format")
            )
        )
    }

    private func makeSource(name: String) -> FeedSource {
        let instant = Date(unixMilliseconds: 1_775_039_400_000)
        return FeedSource(
            id: UUID(uuidString: "bc344bad-9e99-4b4a-abf0-029551cfad31")!,
            name: name,
            feedURL: URL(string: "https://fixture.invalid/rss.xml")!,
            isOfficial: true,
            createdAt: instant,
            updatedAt: instant
        )
    }
}
