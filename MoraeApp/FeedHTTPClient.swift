import Foundation

protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

enum HTTPClientError: Error, Equatable, Sendable {
    case invalidURL
    case insecureURL
    case nonHTTPResponse
    case invalidStatus(Int)
    case responseTooLarge
}

final class RestrictedHTTPClient: HTTPClient, @unchecked Sendable {
    static let maximumResponseBytes = 2 * 1_024 * 1_024
    static let requestTimeout: TimeInterval = 10
    static let resourceTimeout: TimeInterval = 30

    let session: URLSession

    init(
        protocolClasses: [AnyClass]? = nil,
        userAgent: String = RestrictedHTTPClient.defaultUserAgent
    ) {
        let configuration = Self.makeConfiguration(
            protocolClasses: protocolClasses,
            userAgent: userAgent
        )
        session = URLSession(
            configuration: configuration,
            delegate: HTTPSRedirectDelegate(),
            delegateQueue: nil
        )
    }

    deinit {
        session.invalidateAndCancel()
    }

    func data(
        for originalRequest: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = originalRequest.url else {
            throw HTTPClientError.invalidURL
        }
        guard url.scheme?.lowercased() == "https" else {
            throw HTTPClientError.insecureURL
        }

        var request = originalRequest
        request.timeoutInterval = Self.requestTimeout
        request.httpShouldHandleCookies = false
        request.cachePolicy = .useProtocolCachePolicy

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPClientError.nonHTTPResponse
        }
        guard httpResponse.url?.scheme?.lowercased() == "https" else {
            throw HTTPClientError.insecureURL
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HTTPClientError.invalidStatus(httpResponse.statusCode)
        }
        guard httpResponse.expectedContentLength <= Int64(Self.maximumResponseBytes),
              data.count <= Self.maximumResponseBytes else {
            throw HTTPClientError.responseTooLarge
        }
        return (data, httpResponse)
    }

    static func makeConfiguration(
        protocolClasses: [AnyClass]? = nil,
        userAgent: String = defaultUserAgent
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.urlCache = URLCache(
            memoryCapacity: 8 * 1_024 * 1_024,
            diskCapacity: 32 * 1_024 * 1_024
        )
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }
        return configuration
    }

    static var defaultUserAgent: String {
        let appVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0"
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "Morae/\(appVersion) macOS/\(version.majorVersion).\(version.minorVersion)"
    }
}

private final class HTTPSRedirectDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable
{
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard request.url?.scheme?.lowercased() == "https" else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
