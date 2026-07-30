import Darwin
import Foundation
@testable import MoraeApp
import XCTest

final class AgentSocketServerTests: XCTestCase {
    func testEndpointUsesPrivateDirectoryAndSocketPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let endpoint = directory.appendingPathComponent("event.sock")
        let server = AgentSocketServer(endpointURL: endpoint)
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        try server.start()

        XCTAssertEqual(mode(at: directory), 0o700)
        XCTAssertEqual(mode(at: endpoint), 0o600)
    }

    func testEndpointRejectsSymlinkWithoutRemovingTarget() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = root.appendingPathComponent("morae", isDirectory: true)
        let target = root.appendingPathComponent("target")
        let endpoint = directory.appendingPathComponent("event.sock")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data("keep".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: endpoint,
            withDestinationURL: target
        )
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(
            try AgentSocketServer(endpointURL: endpoint).start()
        ) { error in
            XCTAssertEqual(
                error as? AgentSocketServerError,
                .unsafeEndpoint
            )
        }
        XCTAssertEqual(try Data(contentsOf: target), Data("keep".utf8))
    }

    func testEndpointRejectsRegularFileAsStaleSocket() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let endpoint = directory.appendingPathComponent("event.sock")
        try Data("not-a-socket".utf8).write(to: endpoint)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(
            try AgentSocketServer(endpointURL: endpoint).start()
        ) { error in
            XCTAssertEqual(
                error as? AgentSocketServerError,
                .unsafeEndpoint
            )
        }
        XCTAssertEqual(
            try Data(contentsOf: endpoint),
            Data("not-a-socket".utf8)
        )
    }

    func testStartBindsEndpointAndStopRemovesIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let endpoint = directory.appendingPathComponent("event.sock")
        let server = AgentSocketServer(endpointURL: endpoint)
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        try server.start()

        XCTAssertTrue(server.isRunning)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: endpoint.path)
        )

        server.stop()
        XCTAssertFalse(server.isRunning)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: endpoint.path)
        )
    }

    func testStartRejectsSecondLifecycleStart() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let endpoint = directory.appendingPathComponent("event.sock")
        let server = AgentSocketServer(endpointURL: endpoint)
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        try server.start()

        XCTAssertThrowsError(try server.start()) { error in
            XCTAssertEqual(
                error as? AgentSocketServerError,
                .alreadyRunning
            )
        }
        XCTAssertEqual(
            AgentSocketServer.maximumConcurrentConnections,
            8
        )
    }

    private func mode(at url: URL) -> mode_t {
        var status = stat()
        XCTAssertEqual(lstat(url.path, &status), 0)
        return status.st_mode & 0o777
    }
}
