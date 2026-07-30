import MoraeCore
import XCTest

final class FeedCandidateDeduplicatorTests: XCTestCase {
    func testDeduplicatesCanonicalURLsIndependentlyOfInputOrder() throws {
        let duplicateFromCommunity = candidate(
            sourceID: "10000000-0000-0000-0000-000000000001",
            sourceName: "Community Mirror",
            articleURL: "https://EXAMPLE.com:443/post?utm_source=rss&b=2&a=1#top",
            title: "Mirror title",
            publishedAt: Date(timeIntervalSince1970: 200),
            isOfficial: false
        )
        let duplicateFromOfficial = candidate(
            sourceID: "10000000-0000-0000-0000-000000000002",
            sourceName: "Official",
            articleURL: "https://example.com/post?a=1&b=2",
            title: "Official title",
            publishedAt: Date(timeIntervalSince1970: 100),
            isOfficial: true
        )
        let distinct = candidate(
            sourceID: "10000000-0000-0000-0000-000000000003",
            sourceName: "Official",
            articleURL: "https://example.com/another",
            title: "Another",
            publishedAt: nil,
            isOfficial: true
        )
        let deduplicator = FeedCandidateDeduplicator()

        let forward = try deduplicator.deduplicate([
            duplicateFromCommunity,
            distinct,
            duplicateFromOfficial,
        ])
        let reversed = try deduplicator.deduplicate([
            duplicateFromOfficial,
            distinct,
            duplicateFromCommunity,
        ])

        XCTAssertEqual(forward, reversed)
        XCTAssertEqual(forward.count, 2)
        XCTAssertEqual(
            forward.map(\.articleURL.absoluteString),
            [
                "https://example.com/another",
                "https://example.com/post?a=1&b=2",
            ]
        )
        XCTAssertEqual(forward.last?.sourceName, "Official")
        XCTAssertEqual(forward.last?.title, "Official title")
    }

    private func candidate(
        sourceID: String,
        sourceName: String,
        articleURL: String,
        title: String,
        publishedAt: Date?,
        isOfficial: Bool
    ) -> FeedCandidate {
        FeedCandidate(
            sourceID: UUID(uuidString: sourceID)!,
            sourceName: sourceName,
            sourceURL: URL(string: "https://source.invalid/feed")!,
            articleURL: URL(string: articleURL)!,
            title: title,
            publishedAt: publishedAt,
            isOfficialSource: isOfficial
        )
    }
}
