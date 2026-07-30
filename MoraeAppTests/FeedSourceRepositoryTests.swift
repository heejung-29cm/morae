import GRDB
import MoraeCore
import XCTest
@testable import MoraeApp

final class FeedSourceRepositoryTests: XCTestCase {
    func testDefaultFeedFixtureContainsVerifiedOfficialSources() throws {
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
            ["MDN Blog", "web.dev", "Chrome for Developers", "React Blog"]
        )
        XCTAssertTrue(sources.allSatisfy(\.isOfficial))
        XCTAssertTrue(sources.allSatisfy { $0.feedURL.scheme == "https" })
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

    private var fixtureData: Data {
        Data(
            """
            [
              {
                "id": "4f1188e7-d0be-458b-aebe-85c4a8c6946c",
                "name": "Fixture",
                "feedURL": "https://fixture.invalid/feed.xml",
                "isOfficial": true
              }
            ]
            """.utf8
        )
    }
}
