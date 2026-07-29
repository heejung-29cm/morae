import XCTest
import MoraeCore
@testable import MoraeApp

final class MoraeAppTests: XCTestCase {
    func testAppDataDirectoryCreatesMoraeDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = try AppDataDirectory(applicationSupportURL: { root }).prepare()

        XCTAssertEqual(paths.directoryURL.lastPathComponent, "Morae")
        XCTAssertEqual(paths.databaseURL.lastPathComponent, "morae.sqlite")
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.directoryURL.path))
    }

    func testAppDataDirectoryFailureProvidesRecoveryGuidance() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("not-a-directory".utf8).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = AppDataDirectory(applicationSupportURL: { root })

        XCTAssertThrowsError(try directory.prepare()) { error in
            XCTAssertEqual(error as? AppDataDirectoryError, .directoryInaccessible)
            XCTAssertFalse((error as? LocalizedError)?.errorDescription?.isEmpty ?? true)
            XCTAssertFalse((error as? LocalizedError)?.recoverySuggestion?.isEmpty ?? true)
        }
    }

    @MainActor
    func testAppContainerInjectsSubstituteUseCase() async {
        let loader = StubMenuBarContentLoader(message: "Injected")
        let container = AppContainer(
            clock: SystemClock(),
            menuBarContentLoader: loader
        )

        let content = await container.menuBarContentLoader.execute()

        XCTAssertEqual(content, MenuBarContent(message: "Injected"))
    }

    func testLogCategoriesMatchLLDContract() {
        XCTAssertEqual(
            Set(MoraeLogCategory.allCases.map(\.rawValue)),
            Set([
                "app-lifecycle",
                "database",
                "briefing",
                "feed",
                "agent-ipc",
                "agent-normalization",
                "notification",
            ])
        )
        XCTAssertEqual(MoraeLogger.subsystem, "io.github.heejung-29cm.morae")
    }

    func testPublicLogTokenRedactsForbiddenFieldShapes() {
        let queryURL = PublicLogToken("https://example.com?prompt=secret")
        let projectPath = PublicLogToken("/Users/person/secret-project")
        let rawPayload = PublicLogToken("{\"prompt\":\"secret\"}")

        XCTAssertEqual(queryURL, .redacted)
        XCTAssertEqual(projectPath, .redacted)
        XCTAssertEqual(rawPayload, .redacted)
        XCTAssertEqual(PublicLogToken("feed_unavailable").description, "feed_unavailable")
    }

    func testPublicLogMetadataContainsOnlyWhitelistedValues() {
        let metadata = PublicLogMetadata(
            result: PublicLogToken("failed"),
            durationMilliseconds: 125,
            byteCount: 512,
            httpStatus: 503,
            migrationVersion: 1,
            count: 4,
            errorCode: PublicLogToken("feed_unavailable")
        )

        XCTAssertEqual(
            metadata.description,
            "result=failed duration_ms=125 byte_count=512 http_status=503 "
                + "migration_version=1 count=4 error_code=feed_unavailable"
        )
    }
}

private struct StubMenuBarContentLoader: MenuBarContentLoading {
    let message: String

    func execute() async -> MenuBarContent {
        MenuBarContent(message: message)
    }
}
