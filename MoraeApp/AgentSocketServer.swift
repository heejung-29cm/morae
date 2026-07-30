import AppKit
import Darwin
import Foundation
import MoraeCore

enum AgentSocketServerError: Error, Equatable {
    case alreadyRunning
    case endpointPreparationFailed
    case unsafeParentDirectory
    case unsafeEndpoint
    case socketCreationFailed
    case bindFailed
    case listenFailed
}

final class AgentSocketServer: @unchecked Sendable {
    static let maximumConcurrentConnections = 8

    let endpointURL: URL
    private let endpoint: AgentSocketEndpoint
    private let expectedUserID: uid_t
    private let handler: any AgentEnvelopeHandling

    private let queue: DispatchQueue
    private let workerQueue: DispatchQueue
    private let lock = NSLock()
    private var listeningFileDescriptor: Int32 = -1
    private var source: DispatchSourceRead?
    private var terminationObserver: NSObjectProtocol?
    private var activeConnectionCount = 0

    init(
        endpointURL: URL,
        expectedUserID: uid_t = getuid(),
        handler: any AgentEnvelopeHandling = RejectingAgentEnvelopeHandler(),
        queue: DispatchQueue = DispatchQueue(
            label: "io.github.heejung-29cm.morae.agent-socket"
        )
    ) {
        self.endpointURL = endpointURL
        self.expectedUserID = expectedUserID
        self.handler = handler
        endpoint = AgentSocketEndpoint(
            url: endpointURL,
            expectedUserID: expectedUserID
        )
        self.queue = queue
        workerQueue = DispatchQueue(
            label: "io.github.heejung-29cm.morae.agent-socket.worker",
            qos: .utility,
            attributes: .concurrent
        )
    }

    deinit {
        stop()
    }

    var isRunning: Bool {
        lock.withLock { listeningFileDescriptor >= 0 }
    }

    func start() throws {
        guard !isRunning else {
            throw AgentSocketServerError.alreadyRunning
        }
        try endpoint.prepare()

        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw AgentSocketServerError.socketCreationFailed
        }
        let flags = fcntl(fileDescriptor, F_GETFL)
        guard flags >= 0,
              fcntl(
                  fileDescriptor,
                  F_SETFL,
                  flags | O_NONBLOCK
              ) == 0
        else {
            close(fileDescriptor)
            throw AgentSocketServerError.socketCreationFailed
        }
        do {
            try bindAndListen(fileDescriptor)
        } catch {
            close(fileDescriptor)
            endpoint.removeIfOwnedSocket()
            throw error
        }

        let readSource = DispatchSource.makeReadSource(
            fileDescriptor: fileDescriptor,
            queue: queue
        )
        readSource.setEventHandler { [weak self] in
            self?.acceptPendingConnections(from: fileDescriptor)
        }
        lock.withLock {
            listeningFileDescriptor = fileDescriptor
            source = readSource
            terminationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.stop()
            }
        }
        readSource.resume()
    }

    func stop() {
        let state: (Int32, DispatchSourceRead?, NSObjectProtocol?)
            = lock.withLock {
            let current = (
                listeningFileDescriptor,
                source,
                terminationObserver
            )
            listeningFileDescriptor = -1
            source = nil
            terminationObserver = nil
            return current
        }
        state.1?.cancel()
        if let observer = state.2 {
            NotificationCenter.default.removeObserver(observer)
        }
        if state.0 >= 0 {
            shutdown(state.0, SHUT_RDWR)
            close(state.0)
            endpoint.removeIfOwnedSocket()
        }
    }

    private func bindAndListen(_ fileDescriptor: Int32) throws {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(endpointURL.path.utf8) + [0]
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path)
        else {
            throw AgentSocketServerError.bindFailed
        }
        withUnsafeMutableBytes(of: &address.sun_path) {
            $0.copyBytes(from: pathBytes)
        }
        let addressLength = socklen_t(
            MemoryLayout<sockaddr_un>.offset(of: \.sun_path)!
                + pathBytes.count
        )
        address.sun_len = UInt8(addressLength)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fileDescriptor, $0, addressLength)
            }
        }
        guard result == 0 else {
            throw AgentSocketServerError.bindFailed
        }
        guard chmod(endpointURL.path, 0o600) == 0 else {
            throw AgentSocketServerError.endpointPreparationFailed
        }
        guard listen(fileDescriptor, SOMAXCONN) == 0 else {
            throw AgentSocketServerError.listenFailed
        }
    }

    private func acceptPendingConnections(from listener: Int32) {
        while true {
            let connection = accept(listener, nil, nil)
            guard connection >= 0 else {
                if errno == EINTR {
                    continue
                }
                return
            }
            let accepted = lock.withLock {
                guard activeConnectionCount
                    < Self.maximumConcurrentConnections
                else {
                    return false
                }
                activeConnectionCount += 1
                return true
            }
            guard accepted else {
                close(connection)
                continue
            }
            workerQueue.async { [weak self] in
                if let self {
                    AgentSocketConnectionProcessor(
                        expectedUserID: self.expectedUserID,
                        handler: self.handler
                    ).process(connection)
                }
                close(connection)
                self?.lock.withLock {
                    self?.activeConnectionCount -= 1
                }
            }
        }
    }
}

protocol AgentEnvelopeHandling: Sendable {
    func handle(_ envelope: AgentTransportEnvelope) -> AgentIngressAck
}

struct RejectingAgentEnvelopeHandler: AgentEnvelopeHandling {
    func handle(_ envelope: AgentTransportEnvelope) -> AgentIngressAck {
        .failure(.unsupportedEvent)
    }
}

struct AgentSocketConnectionProcessor {
    let expectedUserID: uid_t
    let handler: any AgentEnvelopeHandling

    func process(_ fileDescriptor: Int32) {
        var receiveTimeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(
            fileDescriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &receiveTimeout,
            socklen_t(MemoryLayout.size(ofValue: receiveTimeout))
        )
        let ack: AgentIngressAck
        do {
            let envelope = try AgentSocketFrameReader(
                expectedUserID: expectedUserID
            ).read(from: fileDescriptor)
            ack = handler.handle(envelope)
        } catch let error as AgentSocketFrameValidationError {
            ack = .failure(error.code)
        } catch {
            ack = .failure(.invalidPayload)
        }
        AgentSocketAckWriter().write(ack, to: fileDescriptor)
        shutdown(fileDescriptor, SHUT_WR)
    }
}

struct AgentSocketAckWriter {
    func write(_ ack: AgentIngressAck, to fileDescriptor: Int32) {
        guard let data = try? JSONEncoder().encode(ack),
              data.count <= AgentIPCContract.maximumAckByteCount
        else {
            return
        }
        var noSignal: Int32 = 1
        setsockopt(
            fileDescriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSignal,
            socklen_t(MemoryLayout.size(ofValue: noSignal))
        )
        data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let written = Darwin.send(
                    fileDescriptor,
                    baseAddress.advanced(by: offset),
                    data.count - offset,
                    MSG_NOSIGNAL
                )
                if written > 0 {
                    offset += written
                } else if written < 0 && errno == EINTR {
                    continue
                } else {
                    return
                }
            }
        }
    }
}

struct AgentSocketFrameValidationError: Error, Equatable {
    let code: AgentIngressErrorCode
}

struct AgentSocketFrameReader {
    let expectedUserID: uid_t

    func read(from fileDescriptor: Int32) throws -> AgentTransportEnvelope {
        var peerUserID: uid_t = 0
        var peerGroupID: gid_t = 0
        guard getpeereid(
            fileDescriptor,
            &peerUserID,
            &peerGroupID
        ) == 0, peerUserID == expectedUserID else {
            throw AgentSocketFrameValidationError(code: .peerRejected)
        }

        let header = try readExactly(
            AgentIPCContract.headerByteCount,
            from: fileDescriptor
        )
        let bodyLength: Int
        do {
            bodyLength = try AgentFrameCodec.decodeBodyLength(from: header)
        } catch let AgentFrameError.invalidBodyLength(length)
            where length > AgentIPCContract.maximumFrameBodyByteCount {
            throw AgentSocketFrameValidationError(code: .payloadTooLarge)
        } catch {
            throw AgentSocketFrameValidationError(code: .invalidPayload)
        }
        let body = try readExactly(bodyLength, from: fileDescriptor)
        let envelope: AgentTransportEnvelope
        do {
            envelope = try AgentFrameCodec.decodeEnvelope(from: body)
        } catch {
            throw AgentSocketFrameValidationError(code: .invalidPayload)
        }
        guard envelope.transportVersion == AgentIPCContract.transportVersion
        else {
            throw AgentSocketFrameValidationError(
                code: .unsupportedTransport
            )
        }
        guard envelope.rawPayload.count
            <= AgentIPCContract.maximumRawPayloadByteCount
        else {
            throw AgentSocketFrameValidationError(code: .payloadTooLarge)
        }
        return envelope
    }

    private func readExactly(
        _ count: Int,
        from fileDescriptor: Int32
    ) throws -> Data {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: min(count, 8_192))
        while result.count < count {
            let requested = min(buffer.count, count - result.count)
            let bytesRead = Darwin.read(
                fileDescriptor,
                &buffer,
                requested
            )
            if bytesRead > 0 {
                result.append(contentsOf: buffer.prefix(bytesRead))
            } else if bytesRead < 0 && errno == EINTR {
                continue
            } else {
                throw AgentSocketFrameValidationError(
                    code: .invalidPayload
                )
            }
        }
        return result
    }
}

struct AgentSocketEndpoint {
    let url: URL
    let expectedUserID: uid_t

    static func defaultURL(
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        userID: uid_t = getuid()
    ) -> URL {
        temporaryDirectory
            .appendingPathComponent("morae-\(userID)", isDirectory: true)
            .appendingPathComponent("event.sock")
    }

    func prepare() throws {
        let parentPath = url.deletingLastPathComponent().path
        var parentStatus = stat()
        if lstat(parentPath, &parentStatus) == 0 {
            guard fileType(parentStatus.st_mode) == S_IFDIR,
                  parentStatus.st_uid == expectedUserID
            else {
                throw AgentSocketServerError.unsafeParentDirectory
            }
        } else if errno == ENOENT {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            } catch {
                throw AgentSocketServerError.endpointPreparationFailed
            }
        } else {
            throw AgentSocketServerError.endpointPreparationFailed
        }
        guard chmod(parentPath, 0o700) == 0 else {
            throw AgentSocketServerError.endpointPreparationFailed
        }

        var endpointStatus = stat()
        if lstat(url.path, &endpointStatus) == 0 {
            guard fileType(endpointStatus.st_mode) == S_IFSOCK,
                  endpointStatus.st_uid == expectedUserID
            else {
                throw AgentSocketServerError.unsafeEndpoint
            }
            guard try !isActiveSocket() else {
                throw AgentSocketServerError.unsafeEndpoint
            }
            guard unlink(url.path) == 0 else {
                throw AgentSocketServerError.endpointPreparationFailed
            }
        } else if errno != ENOENT {
            throw AgentSocketServerError.endpointPreparationFailed
        }
    }

    func removeIfOwnedSocket() {
        var status = stat()
        guard lstat(url.path, &status) == 0,
              fileType(status.st_mode) == S_IFSOCK,
              status.st_uid == expectedUserID
        else {
            return
        }
        unlink(url.path)
    }

    private func fileType(_ mode: mode_t) -> mode_t {
        mode & S_IFMT
    }

    private func isActiveSocket() throws -> Bool {
        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw AgentSocketServerError.socketCreationFailed
        }
        defer { close(fileDescriptor) }
        let flags = fcntl(fileDescriptor, F_GETFL)
        guard flags >= 0,
              fcntl(
                  fileDescriptor,
                  F_SETFL,
                  flags | O_NONBLOCK
              ) == 0
        else {
            throw AgentSocketServerError.socketCreationFailed
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(url.path.utf8) + [0]
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path)
        else {
            throw AgentSocketServerError.unsafeEndpoint
        }
        withUnsafeMutableBytes(of: &address.sun_path) {
            $0.copyBytes(from: pathBytes)
        }
        let addressLength = socklen_t(
            MemoryLayout<sockaddr_un>.offset(of: \.sun_path)!
                + pathBytes.count
        )
        address.sun_len = UInt8(addressLength)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fileDescriptor, $0, addressLength)
            }
        }
        if result == 0 {
            return true
        }
        if errno == EINPROGRESS {
            var descriptor = pollfd(
                fd: fileDescriptor,
                events: Int16(POLLOUT),
                revents: 0
            )
            guard poll(&descriptor, 1, 100) > 0 else {
                throw AgentSocketServerError.endpointPreparationFailed
            }
            var socketError: Int32 = 0
            var socketErrorLength = socklen_t(
                MemoryLayout.size(ofValue: socketError)
            )
            guard getsockopt(
                fileDescriptor,
                SOL_SOCKET,
                SO_ERROR,
                &socketError,
                &socketErrorLength
            ) == 0 else {
                throw AgentSocketServerError.endpointPreparationFailed
            }
            if socketError == 0 {
                return true
            }
            if socketError == ECONNREFUSED || socketError == ENOENT {
                return false
            }
            throw AgentSocketServerError.endpointPreparationFailed
        }
        if errno == ECONNREFUSED || errno == ENOENT {
            return false
        }
        throw AgentSocketServerError.endpointPreparationFailed
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
