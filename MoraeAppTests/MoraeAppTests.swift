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
}

private struct StubMenuBarContentLoader: MenuBarContentLoading {
    let message: String

    func execute() async -> MenuBarContent {
        MenuBarContent(message: message)
    }
}
