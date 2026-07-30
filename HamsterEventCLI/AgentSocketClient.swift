import Darwin
import Foundation
import MoraeCore

enum AgentSocketClientError: Error, Equatable {
    case invalidSocketPath
    case socketCreationFailed
    case connectionFailed
    case timedOut
    case writeFailed
    case ackTooLarge
    case invalidAck
}

struct AgentSocketLocation {
    static func url(
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        userID: uid_t = getuid()
    ) -> URL {
        temporaryDirectory
            .appendingPathComponent("morae-\(userID)", isDirectory: true)
            .appendingPathComponent("event.sock", isDirectory: false)
    }
}

struct AgentDeadline {
    let expiresAt: TimeInterval
    let now: () -> TimeInterval

    init(
        duration: TimeInterval,
        now: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.now = now
        expiresAt = now() + duration
    }

    func remainingMilliseconds(cap: Int32? = nil) throws -> Int32 {
        let remaining = expiresAt - now()
        guard remaining > 0 else {
            throw AgentSocketClientError.timedOut
        }
        let milliseconds = Int32(
            min(remaining * 1_000, Double(Int32.max)).rounded(.up)
        )
        return cap.map { min(milliseconds, $0) } ?? milliseconds
    }
}

enum AgentAckDecoder {
    static func decode(_ data: Data) throws -> AgentIngressAck {
        guard !data.isEmpty,
              data.count <= AgentIPCContract.maximumAckByteCount,
              let ack = try? JSONDecoder().decode(
                  AgentIngressAck.self,
                  from: data
              )
        else {
            throw AgentSocketClientError.invalidAck
        }

        let isValidSuccess = ack.ok && ack.eventID != nil && ack.code == nil
        let isValidFailure = !ack.ok && ack.eventID == nil && ack.code != nil
        guard isValidSuccess || isValidFailure else {
            throw AgentSocketClientError.invalidAck
        }
        return ack
    }
}

protocol AgentFrameSending {
    func send(
        frame: Data,
        to socketURL: URL,
        deadline: AgentDeadline
    ) throws -> AgentIngressAck
}

struct AgentSocketClient: AgentFrameSending {
    static let totalTimeout: TimeInterval = 0.9
    private static let connectTimeoutMilliseconds: Int32 = 250
    private let maximumWriteChunkByteCount: Int

    init(maximumWriteChunkByteCount: Int = .max) {
        self.maximumWriteChunkByteCount = maximumWriteChunkByteCount
    }

    func send(
        frame: Data,
        to socketURL: URL,
        deadline: AgentDeadline
    ) throws -> AgentIngressAck {
        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw AgentSocketClientError.socketCreationFailed
        }
        defer { close(fileDescriptor) }

        var noSignal: Int32 = 1
        setsockopt(
            fileDescriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSignal,
            socklen_t(MemoryLayout.size(ofValue: noSignal))
        )
        try setNonBlocking(fileDescriptor)
        var address = try socketAddress(for: socketURL.path)
        let addressLength = socklen_t(
            MemoryLayout<sockaddr_un>.offset(of: \.sun_path)!
                + socketURL.path.utf8.count + 1
        )
        address.sun_len = UInt8(addressLength)

        let connectResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fileDescriptor, $0, addressLength)
            }
        }
        if connectResult != 0 {
            guard errno == EINPROGRESS else {
                throw AgentSocketClientError.connectionFailed
            }
            try wait(
                for: Int16(POLLOUT),
                on: fileDescriptor,
                timeout: deadline.remainingMilliseconds(
                    cap: Self.connectTimeoutMilliseconds
                )
            )
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
            ) == 0, socketError == 0 else {
                throw AgentSocketClientError.connectionFailed
            }
        }

        try writeAll(frame, to: fileDescriptor, deadline: deadline)
        shutdown(fileDescriptor, SHUT_WR)
        return try readAck(from: fileDescriptor, deadline: deadline)
    }

    private func setNonBlocking(_ fileDescriptor: Int32) throws {
        let flags = fcntl(fileDescriptor, F_GETFL)
        guard flags >= 0,
              fcntl(fileDescriptor, F_SETFL, flags | O_NONBLOCK) == 0
        else {
            throw AgentSocketClientError.socketCreationFailed
        }
    }

    private func socketAddress(for path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8) + [0]
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path)
        else {
            throw AgentSocketClientError.invalidSocketPath
        }
        withUnsafeMutableBytes(of: &address.sun_path) {
            $0.copyBytes(from: pathBytes)
        }
        return address
    }

    private func wait(
        for event: Int16,
        on fileDescriptor: Int32,
        timeout: Int32
    ) throws {
        var descriptor = pollfd(
            fd: fileDescriptor,
            events: event,
            revents: 0
        )
        let result = poll(&descriptor, 1, timeout)
        guard result > 0 else {
            if result == 0 {
                throw AgentSocketClientError.timedOut
            }
            throw AgentSocketClientError.connectionFailed
        }
        let fatalEvents = Int16(POLLERR | POLLNVAL)
        let hasRequestedEvent = descriptor.revents & event != 0
        guard descriptor.revents & fatalEvents == 0,
              hasRequestedEvent
                || (event == Int16(POLLIN)
                    && descriptor.revents & Int16(POLLHUP) != 0)
        else {
            throw AgentSocketClientError.connectionFailed
        }
    }

    private func writeAll(
        _ data: Data,
        to fileDescriptor: Int32,
        deadline: AgentDeadline
    ) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                try wait(
                    for: Int16(POLLOUT),
                    on: fileDescriptor,
                    timeout: deadline.remainingMilliseconds()
                )
                let count = Darwin.write(
                    fileDescriptor,
                    baseAddress.advanced(by: offset),
                    min(
                        data.count - offset,
                        maximumWriteChunkByteCount
                    )
                )
                if count > 0 {
                    offset += count
                } else if count < 0 && (errno == EAGAIN || errno == EINTR) {
                    continue
                } else {
                    throw AgentSocketClientError.writeFailed
                }
            }
        }
    }

    private func readAck(
        from fileDescriptor: Int32,
        deadline: AgentDeadline
    ) throws -> AgentIngressAck {
        var ackData = Data()
        var buffer = [UInt8](repeating: 0, count: 512)
        while true {
            try wait(
                for: Int16(POLLIN),
                on: fileDescriptor,
                timeout: deadline.remainingMilliseconds()
            )
            let count = Darwin.read(
                fileDescriptor,
                &buffer,
                buffer.count
            )
            if count > 0 {
                ackData.append(contentsOf: buffer.prefix(count))
                guard ackData.count <= AgentIPCContract.maximumAckByteCount
                else {
                    throw AgentSocketClientError.ackTooLarge
                }
            } else if count == 0 {
                return try AgentAckDecoder.decode(ackData)
            } else if errno == EAGAIN || errno == EINTR {
                continue
            } else {
                throw AgentSocketClientError.invalidAck
            }
        }
    }
}
