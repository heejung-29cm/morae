import Foundation
import GRDB
import MoraeCore
import XCTest
@testable import MoraeApp

struct FixedClock: Clock {
    let instant: Date

    func now() -> Date {
        instant
    }
}

final class AdjustableClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Date

    init(instant: Date) {
        self.instant = instant
    }

    func now() -> Date {
        lock.withLock { instant }
    }

    func set(_ instant: Date) {
        lock.withLock {
            self.instant = instant
        }
    }
}

struct FixedUUIDGenerator: UUIDGenerating {
    let uuid: UUID

    func next() -> UUID {
        uuid
    }
}

final class TemporaryDatabase {
    let rootURL: URL
    let database: AppDatabase

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        database = try AppDatabase.open(
            at: rootURL.appendingPathComponent("morae.sqlite")
        )
    }

    deinit {
        try? database.close()
        try? FileManager.default.removeItem(at: rootURL)
    }
}

enum FixtureLoader {
    static func data(named name: String, extension fileExtension: String) throws -> Data {
        guard let url = Bundle(for: FixtureBundleToken.self).url(
            forResource: name,
            withExtension: fileExtension
        ) else {
            throw FixtureError.notFound("\(name).\(fileExtension)")
        }
        return try Data(contentsOf: url)
    }
}

enum FixtureError: Error, Equatable {
    case notFound(String)
}

private final class FixtureBundleToken {}

func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let storage = StubURLProtocolStorage()

    static func register(handler: @escaping Handler) {
        storage.set(handler)
    }

    static func reset() {
        storage.set(nil)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let (response, data) = try Self.storage.response(for: request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class StubURLProtocolStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: StubURLProtocol.Handler?

    func set(_ handler: StubURLProtocol.Handler?) {
        lock.withLock {
            self.handler = handler
        }
    }

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let currentHandler = lock.withLock { handler }
        guard let currentHandler else {
            throw URLError(.resourceUnavailable)
        }
        return try currentHandler(request)
    }
}
