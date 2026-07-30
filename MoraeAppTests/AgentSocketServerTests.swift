import Foundation
@testable import MoraeApp
import XCTest

final class AgentSocketServerTests: XCTestCase {
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
}
