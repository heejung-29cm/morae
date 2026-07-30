import Darwin
import Foundation
@testable import MoraeApp
import MoraeCore
import XCTest

final class AgentSocketServerTests: XCTestCase {
    private struct StubHandler: AgentEnvelopeHandling {
        let ack: AgentIngressAck

        func handle(
            _ envelope: AgentTransportEnvelope
        ) -> AgentIngressAck {
            ack
        }
    }

    func testRealClientServerRoundTripWithPartialWrites() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let endpoint = directory.appendingPathComponent("event.sock")
        let eventID = UUID()
        let server = AgentSocketServer(
            endpointURL: endpoint,
            handler: StubHandler(ack: .success(eventID: eventID))
        )
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: directory)
        }
        try server.start()
        let envelope = AgentTransportEnvelope(
            source: .claude,
            eventHint: "TaskCompleted",
            receivedAtMs: 123,
            rawPayload: Data(#"{"session_id":"session"}"#.utf8)
        )

        let ack = try AgentSocketClient(
            maximumWriteChunkByteCount: 3
        ).send(
            frame: AgentFrameCodec.encode(envelope),
            to: endpoint,
            deadline: AgentDeadline(duration: 0.9)
        )

        XCTAssertEqual(ack, .success(eventID: eventID))
    }

    func testConnectionWritesSuccessOnlyAfterHandlerReturns() throws {
        let descriptors = try socketPair()
        defer {
            close(descriptors.0)
            close(descriptors.1)
        }
        let eventID = UUID()
        let frame = try AgentFrameCodec.encode(
            AgentTransportEnvelope(
                source: .codex,
                eventHint: "agent-turn-complete",
                receivedAtMs: 123,
                rawPayload: Data("{}".utf8)
            )
        )
        _ = frame.withUnsafeBytes {
            Darwin.write(descriptors.0, $0.baseAddress, frame.count)
        }

        AgentSocketConnectionProcessor(
            expectedUserID: getuid(),
            handler: StubHandler(ack: .success(eventID: eventID))
        ).process(descriptors.1)

        XCTAssertEqual(
            try readAck(from: descriptors.0),
            .success(eventID: eventID)
        )
    }

    func testConnectionWritesSafeValidationFailureAck() throws {
        let descriptors = try socketPair()
        defer {
            close(descriptors.0)
            close(descriptors.1)
        }
        var emptyLength: [UInt8] = [0, 0, 0, 0]
        XCTAssertEqual(
            Darwin.write(descriptors.0, &emptyLength, emptyLength.count),
            emptyLength.count
        )

        AgentSocketConnectionProcessor(
            expectedUserID: getuid(),
            handler: StubHandler(ack: .success(eventID: UUID()))
        ).process(descriptors.1)

        let data = try readUntilEOF(from: descriptors.0)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("raw"))
        XCTAssertEqual(
            try JSONDecoder().decode(AgentIngressAck.self, from: data),
            .failure(.invalidPayload)
        )
    }

    func testFrameReaderAcceptsPartialReads() throws {
        let descriptors = try socketPair()
        defer {
            close(descriptors.0)
            close(descriptors.1)
        }
        let envelope = AgentTransportEnvelope(
            source: .codex,
            eventHint: "agent-turn-complete",
            receivedAtMs: 123,
            rawPayload: Data("{}".utf8)
        )
        let frame = try AgentFrameCodec.encode(envelope)
        for byte in frame {
            var byte = byte
            XCTAssertEqual(Darwin.write(descriptors.0, &byte, 1), 1)
        }

        let received = try AgentSocketFrameReader(
            expectedUserID: getuid()
        ).read(from: descriptors.1)

        XCTAssertEqual(received, envelope)
    }

    func testFrameReaderRejectsWrongPeerAndInvalidLengths() throws {
        let wrongPeerDescriptors = try socketPair()
        defer {
            close(wrongPeerDescriptors.0)
            close(wrongPeerDescriptors.1)
        }
        XCTAssertThrowsError(
            try AgentSocketFrameReader(
                expectedUserID: getuid() + 1
            ).read(from: wrongPeerDescriptors.1)
        ) { error in
            XCTAssertEqual(
                error as? AgentSocketFrameValidationError,
                AgentSocketFrameValidationError(code: .peerRejected)
            )
        }

        try assertRejectedHeader(
            [0, 0, 0, 0],
            expectedCode: .invalidPayload
        )
        try assertRejectedHeader(
            [0, 16, 0, 1],
            expectedCode: .payloadTooLarge
        )
    }

    func testFrameReaderRejectsUnsupportedTransportVersion() throws {
        let descriptors = try socketPair()
        defer {
            close(descriptors.0)
            close(descriptors.1)
        }
        let frame = try AgentFrameCodec.encode(
            AgentTransportEnvelope(
                transportVersion: 2,
                source: .claude,
                eventHint: "Stop",
                receivedAtMs: 123,
                rawPayload: Data("{}".utf8)
            )
        )
        _ = frame.withUnsafeBytes {
            Darwin.write(descriptors.0, $0.baseAddress, frame.count)
        }

        XCTAssertThrowsError(
            try AgentSocketFrameReader(
                expectedUserID: getuid()
            ).read(from: descriptors.1)
        ) { error in
            XCTAssertEqual(
                error as? AgentSocketFrameValidationError,
                AgentSocketFrameValidationError(
                    code: .unsupportedTransport
                )
            )
        }
    }

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

    func testSecondServerCannotUnlinkActiveSocket() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let endpoint = directory.appendingPathComponent("event.sock")
        let firstServer = AgentSocketServer(endpointURL: endpoint)
        let secondServer = AgentSocketServer(endpointURL: endpoint)
        defer {
            secondServer.stop()
            firstServer.stop()
            try? FileManager.default.removeItem(at: directory)
        }
        try firstServer.start()

        XCTAssertThrowsError(try secondServer.start()) { error in
            XCTAssertEqual(
                error as? AgentSocketServerError,
                .unsafeEndpoint
            )
        }
        XCTAssertTrue(firstServer.isRunning)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: endpoint.path)
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

    private func socketPair() throws -> (Int32, Int32) {
        var descriptors: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0
        else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return (descriptors[0], descriptors[1])
    }

    private func assertRejectedHeader(
        _ bytes: [UInt8],
        expectedCode: AgentIngressErrorCode
    ) throws {
        let descriptors = try socketPair()
        defer {
            close(descriptors.0)
            close(descriptors.1)
        }
        var bytes = bytes
        XCTAssertEqual(
            Darwin.write(descriptors.0, &bytes, bytes.count),
            bytes.count
        )
        XCTAssertThrowsError(
            try AgentSocketFrameReader(
                expectedUserID: getuid()
            ).read(from: descriptors.1)
        ) { error in
            XCTAssertEqual(
                error as? AgentSocketFrameValidationError,
                AgentSocketFrameValidationError(code: expectedCode)
            )
        }
    }

    private func readAck(from fileDescriptor: Int32) throws
        -> AgentIngressAck {
        let data = try readUntilEOF(from: fileDescriptor)
        return try JSONDecoder().decode(AgentIngressAck.self, from: data)
    }

    private func readUntilEOF(from fileDescriptor: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 512)
        while true {
            let count = Darwin.read(
                fileDescriptor,
                &buffer,
                buffer.count
            )
            if count > 0 {
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                return data
            } else if errno != EINTR {
                throw NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(errno)
                )
            }
        }
    }
}
