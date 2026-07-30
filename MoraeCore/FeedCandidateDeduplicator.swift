import Foundation

public struct FeedCandidateDeduplicator: Sendable {
    private let canonicalizer: URLCanonicalizer

    public init(canonicalizer: URLCanonicalizer = URLCanonicalizer()) {
        self.canonicalizer = canonicalizer
    }

    public func deduplicate(
        _ candidates: [FeedCandidate]
    ) throws -> [FeedCandidate] {
        var selectedByURL: [URL: FeedCandidate] = [:]

        for candidate in candidates {
            let canonicalURL = try canonicalizer.canonicalize(
                candidate.articleURL
            )
            let normalized = FeedCandidate(
                sourceID: candidate.sourceID,
                sourceName: candidate.sourceName,
                sourceURL: candidate.sourceURL,
                articleURL: canonicalURL,
                title: candidate.title,
                publishedAt: candidate.publishedAt,
                isOfficialSource: candidate.isOfficialSource,
                selectionWeight: candidate.selectionWeight
            )
            if let existing = selectedByURL[canonicalURL] {
                selectedByURL[canonicalURL] = preferred(existing, normalized)
            } else {
                selectedByURL[canonicalURL] = normalized
            }
        }

        return selectedByURL
            .sorted { $0.key.absoluteString < $1.key.absoluteString }
            .map(\.value)
    }

    private func preferred(
        _ lhs: FeedCandidate,
        _ rhs: FeedCandidate
    ) -> FeedCandidate {
        if lhs.selectionWeight != rhs.selectionWeight {
            return lhs.selectionWeight > rhs.selectionWeight ? lhs : rhs
        }
        if lhs.isOfficialSource != rhs.isOfficialSource {
            return lhs.isOfficialSource ? lhs : rhs
        }
        if lhs.publishedAt != rhs.publishedAt {
            return (lhs.publishedAt ?? .distantPast)
                > (rhs.publishedAt ?? .distantPast) ? lhs : rhs
        }
        let lhsKey = [
            lhs.sourceName,
            lhs.title,
            lhs.sourceID.uuidString.lowercased(),
        ]
        let rhsKey = [
            rhs.sourceName,
            rhs.title,
            rhs.sourceID.uuidString.lowercased(),
        ]
        return lhsKey.lexicographicallyPrecedes(rhsKey) ? lhs : rhs
    }
}
