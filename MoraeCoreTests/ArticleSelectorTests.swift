import MoraeCore
import XCTest

final class ArticleSelectorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testFreshnessBucketsUseFixedNow() throws {
        let candidates = [
            candidate(path: "day-15", ageInDays: 15),
            candidate(path: "day-8", ageInDays: 8),
            candidate(path: "day-4", ageInDays: 4),
            candidate(path: "day-2", ageInDays: 2),
            candidate(path: "day-1", ageInDays: 1),
        ]

        let selected = try ArticleSelector().select(
            from: candidates,
            interests: [],
            readURLs: [],
            recentlyRecommendedURLs: [],
            now: now
        )

        XCTAssertEqual(selected?.articleURL.lastPathComponent, "day-1")
    }

    func testInterestOfficialAndUnreadSignalsAffectSelection() throws {
        let favored = candidate(
            path: "favored",
            title: "Swift concurrency for the web",
            ageInDays: 4,
            isOfficial: true
        )
        let freshButRead = candidate(
            path: "fresh",
            title: "Unrelated release",
            ageInDays: 1,
            isOfficial: false
        )

        let selected = try ArticleSelector().select(
            from: [freshButRead, favored],
            interests: ["Swift", "web"],
            readURLs: [freshButRead.articleURL],
            recentlyRecommendedURLs: [],
            now: now
        )

        XCTAssertEqual(selected?.articleURL, favored.articleURL)
    }

    func testRecentPenaltyIsRemovedWhenEveryCandidateIsRecent() throws {
        let best = candidate(path: "best", ageInDays: 1, isOfficial: true)
        let old = candidate(path: "old", ageInDays: 14)

        let withOneFreshURL = try ArticleSelector().select(
            from: [best, old],
            interests: [],
            readURLs: [],
            recentlyRecommendedURLs: [best.articleURL],
            now: now
        )
        XCTAssertEqual(withOneFreshURL?.articleURL, old.articleURL)

        let allRecent = try ArticleSelector().select(
            from: [best, old],
            interests: [],
            readURLs: [],
            recentlyRecommendedURLs: [best.articleURL, old.articleURL],
            now: now
        )
        XCTAssertEqual(allRecent?.articleURL, best.articleURL)
    }

    func testTieUsesPublishedDateThenCanonicalURL() throws {
        let earlier = candidate(path: "z", ageInDays: 1)
        let laterA = candidate(path: "a", ageInDays: 0)
        let laterB = candidate(path: "b", ageInDays: 0)

        let selected = try ArticleSelector().select(
            from: [laterB, earlier, laterA],
            interests: [],
            readURLs: [],
            recentlyRecommendedURLs: [],
            now: now
        )

        XCTAssertEqual(selected?.articleURL, laterA.articleURL)
    }

    func testCuratedWeightCanOutrankFresherUnweightedSource() throws {
        let curated = candidate(
            path: "curated",
            ageInDays: 4,
            selectionWeight: 45
        )
        let fresh = candidate(
            path: "fresh",
            ageInDays: 1,
            selectionWeight: 0
        )

        let selected = try ArticleSelector().select(
            from: [fresh, curated],
            interests: [],
            readURLs: [],
            recentlyRecommendedURLs: [],
            now: now
        )

        XCTAssertEqual(selected?.articleURL, curated.articleURL)
    }

    func testArticlesOlderThanThirtyDaysAreExcluded() throws {
        let stale = candidate(
            path: "stale",
            ageInDays: 31,
            selectionWeight: 100
        )
        let fresh = candidate(
            path: "fresh",
            ageInDays: 10,
            selectionWeight: 0
        )

        let selected = try ArticleSelector().select(
            from: [stale, fresh],
            interests: [],
            readURLs: [],
            recentlyRecommendedURLs: [],
            now: now
        )

        XCTAssertEqual(selected?.articleURL, fresh.articleURL)
    }

    func testArticleWithoutPublishedDateIsExcluded() throws {
        let undated = candidate(
            path: "undated",
            ageInDays: nil,
            selectionWeight: 100
        )

        let selected = try ArticleSelector().select(
            from: [undated],
            interests: [],
            readURLs: [],
            recentlyRecommendedURLs: [],
            now: now
        )

        XCTAssertNil(selected)
    }

    func testStaleDuplicateDoesNotHideEligibleVersion() throws {
        let stale = candidate(
            path: "same?utm_source=stale",
            ageInDays: 31,
            selectionWeight: 100
        )
        let fresh = candidate(
            path: "same",
            ageInDays: 10,
            selectionWeight: 0
        )

        let selected = try ArticleSelector().select(
            from: [stale, fresh],
            interests: [],
            readURLs: [],
            recentlyRecommendedURLs: [],
            now: now
        )

        XCTAssertEqual(selected?.articleURL, fresh.articleURL)
    }

    func testAIFETopicStronglyOutranksFresherInfrastructureTopic() throws {
        let preferred = candidate(
            path: "preferred",
            title: "AI로 브라우저 에이전트를 설계한 경험",
            ageInDays: 14,
            selectionWeight: 0
        )
        let infrastructure = candidate(
            path: "infrastructure",
            title: "Kubernetes infrastructure deployment",
            ageInDays: 1,
            selectionWeight: 45
        )

        let selected = try ArticleSelector().select(
            from: [infrastructure, preferred],
            interests: [],
            readURLs: [],
            recentlyRecommendedURLs: [],
            now: now
        )

        XCTAssertEqual(selected?.articleURL, preferred.articleURL)
    }

    private func candidate(
        path: String,
        title: String = "Article",
        ageInDays: Int?,
        isOfficial: Bool = false,
        selectionWeight: Int = 0
    ) -> FeedCandidate {
        FeedCandidate(
            sourceID: UUID(),
            sourceName: "Source",
            sourceURL: URL(string: "https://source.invalid/feed")!,
            articleURL: URL(string: "https://example.com/\(path)")!,
            title: title,
            publishedAt: ageInDays.map {
                now.addingTimeInterval(-TimeInterval($0 * 86_400))
            },
            isOfficialSource: isOfficial,
            selectionWeight: selectionWeight
        )
    }
}
