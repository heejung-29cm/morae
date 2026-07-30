import GRDB
import MoraeCore
import XCTest
@testable import MoraeApp

final class FeedSourceRepositoryTests: XCTestCase {
    func testDefaultFeedFixtureContainsCuratedSourcesAndWeights() throws {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "DefaultFeeds",
                withExtension: "json"
            )
        )
        let data = try Data(contentsOf: url)
        let instant = Date(unixMilliseconds: 1_775_039_400_000)

        let sources = try DefaultFeedLoader.decode(data: data, at: instant)

        XCTAssertEqual(
            sources.map(\.name),
            [
                "GeekNews",
                "Korean FE Article",
            ]
        )
        XCTAssertTrue(sources.allSatisfy(\.isOfficial))
        XCTAssertTrue(sources.allSatisfy { $0.feedURL.scheme == "https" })
        XCTAssertEqual(
            sources.map(\.selectionWeight),
            [40, 60]
        )
    }

    func testSeedRunsOnlyOnceEvenAfterSourcesAreDeleted() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBFeedSourceRepository(database: database)
        let instant = Date(unixMilliseconds: 1_775_039_400_000)
        let sources = try DefaultFeedLoader.decode(
            data: fixtureData,
            at: instant
        )

        try await repository.seedDefaults(sources)
        let firstSeed = try await repository.enabledSources()
        XCTAssertEqual(firstSeed.map(\.name), ["Fixture"])

        try await database.writer.write { database in
            try database.execute(sql: "DELETE FROM feed_sources")
        }
        try await repository.seedDefaults(sources)

        let remainingSources = try await repository.enabledSources()
        XCTAssertTrue(remainingSources.isEmpty)
    }

    func testMarkCheckedPersistsTimestamp() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBFeedSourceRepository(database: database)
        let instant = Date(unixMilliseconds: 1_775_039_400_000)
        let source = try XCTUnwrap(
            DefaultFeedLoader.decode(data: fixtureData, at: instant).first
        )
        try await repository.seedDefaults([source])
        let checkedAt = Date(unixMilliseconds: 1_775_040_000_000)

        try await repository.markChecked(id: source.id, at: checkedAt)

        let checkedSource = try await repository.enabledSources().first
        XCTAssertEqual(checkedSource?.lastCheckedAt, checkedAt)
    }

    func testV3SeedDisablesRetiredDefaultsAndKeepsCustomSource()
        async throws
    {
        let database = try AppDatabase.inMemory()
        let repository = GRDBFeedSourceRepository(database: database)
        let instant = Date(unixMilliseconds: 1_775_039_400_000)
        let legacy = FeedSource(
            id: UUID(
                uuidString: "8b064c57-30c5-4b87-863f-edb32940237a"
            )!,
            name: "MDN Blog",
            feedURL: URL(
                string: "https://developer.mozilla.org/en-US/blog/rss.xml"
            )!,
            isOfficial: true,
            createdAt: instant,
            updatedAt: instant
        )
        let custom = FeedSource(
            id: UUID(),
            name: "Custom",
            feedURL: URL(string: "https://custom.invalid/feed.xml")!,
            isOfficial: false,
            createdAt: instant,
            updatedAt: instant
        )
        let retiredNewsletter = FeedSource(
            id: UUID(),
            name: "Frontend Focus",
            feedURL: URL(string: "https://frontendfoc.us/rss/")!,
            isOfficial: true,
            createdAt: instant,
            updatedAt: instant
        )
        try await database.writer.write { database in
            try FeedSourceRecord(source: legacy).insert(database)
            try FeedSourceRecord(source: custom).insert(database)
            try FeedSourceRecord(source: retiredNewsletter).insert(database)
            try database.execute(
                sql: """
                    INSERT INTO app_metadata (key, value)
                    VALUES ('default_feeds_seeded', '1')
                    """
            )
        }
        let defaultFeedsURL = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "DefaultFeeds",
                withExtension: "json"
            )
        )
        let curated = try DefaultFeedLoader.decode(
            data: try Data(contentsOf: defaultFeedsURL),
            at: instant
        )

        try await repository.seedDefaults(curated)

        let enabled = try await repository.enabledSources()
        XCTAssertTrue(enabled.contains(where: { $0.name == "Custom" }))
        XCTAssertFalse(enabled.contains(where: { $0.name == "MDN Blog" }))
        XCTAssertFalse(
            enabled.contains(where: { $0.name == "Frontend Focus" })
        )
        XCTAssertEqual(
            Set(enabled.map(\.name)).intersection(
                ["GeekNews", "Korean FE Article"]
            ),
            ["GeekNews", "Korean FE Article"]
        )
    }

    private var fixtureData: Data {
        Data(
            """
            [
              {
                "id": "4f1188e7-d0be-458b-aebe-85c4a8c6946c",
                "name": "Fixture",
                "feedURL": "https://fixture.invalid/feed.xml",
                "isOfficial": true,
                "selectionWeight": 30
              }
            ]
            """.utf8
        )
    }
}
