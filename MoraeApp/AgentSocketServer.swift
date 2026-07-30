import Darwin
import Foundation

enum AgentSocketServerError: Error, Equatable {
    case alreadyRunning
    case endpointPreparationFailed
    case socketCreationFailed
    case bindFailed
    case listenFailed
}

final class AgentSocketServer: @unchecked Sendable {
    static let maximumConcurrentConnections = 8

    let endpointURL: URL

    private let queue: DispatchQueue
    private let workerQueue: DispatchQueue
    private let lock = NSLock()
    private var listeningFileDescriptor: Int32 = -1
    private var source: DispatchSourceRead?
    private var activeConnectionCount = 0

    init(
        endpointURL: URL,
        queue: DispatchQueue = DispatchQueue(
            label: "io.github.heejung-29cm.morae.agent-socket"
        )
    ) {
        self.endpointURL = endpointURL
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
        try prepareEndpoint()

        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw AgentSocketServerError.socketCreationFailed
        }
        do {
            try bindAndListen(fileDescriptor)
        } catch {
            close(fileDescriptor)
            try? FileManager.default.removeItem(at: endpointURL)
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
        }
        readSource.resume()
    }

    func stop() {
        let state: (Int32, DispatchSourceRead?) = lock.withLock {
            let current = (listeningFileDescriptor, source)
            listeningFileDescriptor = -1
            source = nil
            return current
        }
        state.1?.cancel()
        if state.0 >= 0 {
            shutdown(state.0, SHUT_RDWR)
            close(state.0)
        }
        try? FileManager.default.removeItem(at: endpointURL)
    }

    private func prepareEndpoint() throws {
        let parent = endpointURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: endpointURL.path) {
                try FileManager.default.removeItem(at: endpointURL)
            }
        } catch {
            throw AgentSocketServerError.endpointPreparationFailed
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
                // Frame processing is added by S4-07.
                close(connection)
                self?.lock.withLock {
                    self?.activeConnectionCount -= 1
                }
            }
        }
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
