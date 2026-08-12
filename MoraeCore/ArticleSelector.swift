import Foundation

public struct ArticleSelector: Sendable {
    private static let maximumArticleAge: TimeInterval = 30 * 86_400
    private static let futureDateTolerance: TimeInterval = 86_400

    private let deduplicator: FeedCandidateDeduplicator
    private let canonicalizer: URLCanonicalizer
    private let topicClassifier = ArticleTopicClassifier()

    public init(
        deduplicator: FeedCandidateDeduplicator = FeedCandidateDeduplicator(),
        canonicalizer: URLCanonicalizer = URLCanonicalizer()
    ) {
        self.deduplicator = deduplicator
        self.canonicalizer = canonicalizer
    }

    public func select(
        from candidates: [FeedCandidate],
        interests: [String],
        readURLs: Set<URL>,
        recentlyRecommendedURLs: Set<URL>,
        feedback: ArticleSelectionFeedback = .empty,
        now: Date
    ) throws -> FeedCandidate? {
        let excludedURLs = try canonicalURLs(feedback.excludedURLs)
        let candidates = try deduplicator.deduplicate(
            candidates.filter { isEligible($0, now: now) }
        ).filter { !excludedURLs.contains($0.articleURL) }
        guard !candidates.isEmpty else {
            return nil
        }
        let readURLs = try canonicalURLs(readURLs)
        let recentURLs = try canonicalURLs(recentlyRecommendedURLs)
        let allRecentlyRecommended = candidates.allSatisfy {
            recentURLs.contains($0.articleURL)
        }

        return candidates.sorted { lhs, rhs in
            let lhsScore = score(
                lhs,
                interests: interests,
                readURLs: readURLs,
                recentURLs: recentURLs,
                feedback: feedback,
                suppressRecentPenalty: allRecentlyRecommended,
                now: now
            )
            let rhsScore = score(
                rhs,
                interests: interests,
                readURLs: readURLs,
                recentURLs: recentURLs,
                feedback: feedback,
                suppressRecentPenalty: allRecentlyRecommended,
                now: now
            )
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            if lhs.publishedAt != rhs.publishedAt {
                return (lhs.publishedAt ?? .distantPast)
                    > (rhs.publishedAt ?? .distantPast)
            }
            return lhs.articleURL.absoluteString < rhs.articleURL.absoluteString
        }
        .first
    }

    private func score(
        _ candidate: FeedCandidate,
        interests: [String],
        readURLs: Set<URL>,
        recentURLs: Set<URL>,
        feedback: ArticleSelectionFeedback,
        suppressRecentPenalty: Bool,
        now: Date
    ) -> Int {
        return freshnessScore(candidate.publishedAt, now: now)
            + topicClassifier.classify(candidate.title).selectionScore
            + feedbackScore(candidate, feedback: feedback)
            + interestScore(candidate.title, interests: interests)
            + (candidate.isOfficialSource ? 15 : 0)
            + min(max(candidate.selectionWeight, 0), 100)
            + (readURLs.contains(candidate.articleURL) ? 0 : 10)
            - (
                !suppressRecentPenalty
                    && recentURLs.contains(candidate.articleURL) ? 60 : 0
            )
    }

    private func feedbackScore(
        _ candidate: FeedCandidate,
        feedback: ArticleSelectionFeedback
    ) -> Int {
        let topic = topicClassifier.classify(candidate.title)
        let topicScore = min(
            max(feedback.preferredTopicCounts[topic, default: 0], 0) * 20,
            60
        )
        let normalizedSource = candidate.sourceName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let sourceScore = min(
            max(feedback.preferredSourceCounts[normalizedSource, default: 0], 0) * 10,
            30
        )
        return topicScore + sourceScore
    }

    private func freshnessScore(_ publishedAt: Date?, now: Date) -> Int {
        guard let publishedAt else {
            return 0
        }
        let elapsedDays = max(
            0,
            Int(now.timeIntervalSince(publishedAt) / 86_400)
        )
        return switch elapsedDays {
        case 0...1: 50
        case 2...3: 40
        case 4...7: 30
        case 8...14: 15
        default: 0
        }
    }

    private func isEligible(_ candidate: FeedCandidate, now: Date) -> Bool {
        guard let publishedAt = candidate.publishedAt else {
            return false
        }
        let age = now.timeIntervalSince(publishedAt)
        return age >= -Self.futureDateTolerance
            && age <= Self.maximumArticleAge
    }

    private func interestScore(_ title: String, interests: [String]) -> Int {
        let interestTokens = Set(interests.flatMap(tokens(in:)))
        guard !interestTokens.isEmpty else {
            return 0
        }
        let titleTokens = Set(tokens(in: title))
        let matches = interestTokens.intersection(titleTokens).count
        return Int(
            (Double(matches) / Double(interestTokens.count) * 25).rounded(
                .down
            )
        )
    }

    private func tokens(in value: String) -> [String] {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private func canonicalURLs(_ urls: Set<URL>) throws -> Set<URL> {
        try Set(urls.map(canonicalizer.canonicalize))
    }
}
