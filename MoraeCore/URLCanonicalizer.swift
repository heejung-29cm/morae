import Foundation

public enum URLCanonicalizationError: Error, Equatable, Sendable {
    case missingSchemeOrHost
    case invalidURL
}

public struct URLCanonicalizer: Sendable {
    public init() {}

    public func canonicalize(_ url: URL) throws -> URL {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ),
        let scheme = components.scheme?.lowercased(),
        let host = components.host?.lowercased(),
        !scheme.isEmpty,
        !host.isEmpty else {
            throw URLCanonicalizationError.missingSchemeOrHost
        }

        components.scheme = scheme
        components.host = host
        components.fragment = nil
        if (scheme == "http" && components.port == 80)
            || (scheme == "https" && components.port == 443) {
            components.port = nil
        }
        if components.path.isEmpty {
            components.path = "/"
        }

        let retainedQueryItems = (components.queryItems ?? [])
            .filter { !isTrackingQuery(name: $0.name) }
            .sorted {
                if $0.name != $1.name {
                    return $0.name < $1.name
                }
                return ($0.value ?? "") < ($1.value ?? "")
            }
        components.queryItems = retainedQueryItems.isEmpty
            ? nil
            : retainedQueryItems

        guard let canonicalURL = components.url else {
            throw URLCanonicalizationError.invalidURL
        }
        return canonicalURL
    }

    private func isTrackingQuery(name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized.hasPrefix("utm_")
            || ["fbclid", "gclid", "ref"].contains(normalized)
    }
}
