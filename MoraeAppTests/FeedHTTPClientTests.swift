import XCTest
@testable import MoraeApp

final class FeedHTTPClientTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testConfigurationDisablesCookiesAndCredentialStorage() {
        let configuration = RestrictedHTTPClient.makeConfiguration(
            userAgent: "Morae/Test"
        )

        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 10)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 30)
        XCTAssertEqual(configuration.urlCache?.memoryCapacity, 8 * 1_024 * 1_024)
        XCTAssertEqual(configuration.urlCache?.diskCapacity, 32 * 1_024 * 1_024)
        XCTAssertEqual(
            configuration.httpAdditionalHeaders?["User-Agent"] as? String,
            "Morae/Test"
        )
    }

    func testHTTPSRequestUsesRestrictedPolicy() async throws {
        StubURLProtocol.register { request in
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertEqual(request.timeoutInterval, 10)
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "User-Agent"),
                "Morae/Test"
            )
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!,
                Data("feed".utf8)
            )
        }
        let client = RestrictedHTTPClient(
            protocolClasses: [StubURLProtocol.self],
            userAgent: "Morae/Test"
        )

        let (data, response) = try await client.data(
            for: URLRequest(url: URL(string: "https://fixture.invalid/feed")!)
        )

        XCTAssertEqual(data, Data("feed".utf8))
        XCTAssertEqual(response.statusCode, 200)
    }

    func testRejectsInitialAndFinalInsecureURL() async throws {
        let client = RestrictedHTTPClient(
            protocolClasses: [StubURLProtocol.self]
        )

        await XCTAssertThrowsErrorAsync(
            try await client.data(
                for: URLRequest(url: URL(string: "http://fixture.invalid/feed")!)
            )
        ) { error in
            XCTAssertEqual(error as? HTTPClientError, .insecureURL)
        }

        StubURLProtocol.register { request in
            (
                HTTPURLResponse(
                    url: URL(string: "http://fixture.invalid/final")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }
        await XCTAssertThrowsErrorAsync(
            try await client.data(
                for: URLRequest(url: URL(string: "https://fixture.invalid/feed")!)
            )
        ) { error in
            XCTAssertEqual(error as? HTTPClientError, .insecureURL)
        }
    }

    func testRejectsOversizedAnd304Responses() async throws {
        let client = RestrictedHTTPClient(
            protocolClasses: [StubURLProtocol.self]
        )
        StubURLProtocol.register { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(count: RestrictedHTTPClient.maximumResponseBytes + 1)
            )
        }

        await XCTAssertThrowsErrorAsync(
            try await client.data(
                for: URLRequest(url: URL(string: "https://fixture.invalid/feed")!)
            )
        ) { error in
            XCTAssertEqual(error as? HTTPClientError, .responseTooLarge)
        }

        StubURLProtocol.register { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 304,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }
        await XCTAssertThrowsErrorAsync(
            try await client.data(
                for: URLRequest(url: URL(string: "https://fixture.invalid/feed")!)
            )
        ) { error in
            XCTAssertEqual(error as? HTTPClientError, .invalidStatus(304))
        }
    }
}
