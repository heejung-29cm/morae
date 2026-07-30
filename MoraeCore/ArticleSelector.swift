import Foundation

public struct ArticleSelector: Sendable {
    private static let maximumArticleAge: TimeInterval = 30 * 86_400
    private static let futureDateTolerance: TimeInterval = 86_400
    private static let preferredTopicTokens: Set<String> = [
        "agent", "agentic", "agents", "ai", "angular", "browser", "chrome",
        "claude", "css", "fe", "frontend", "gemini", "gpt", "html",
        "javascript", "llm", "mcp", "ml", "rag", "react", "safari",
        "svelte", "transformer", "typescript", "vue", "wasm", "web",
        "webassembly",
    ]
    private static let preferredTopicPhrases = [
        "artificial intelligence",
        "deep learning",
        "design system",
        "front end",
        "front-end",
        "generative ai",
        "machine learning",
        "next.js",
        "node.js",
        "server components",
        "web performance",
    ]
    private static let preferredTopicFragments = [
        "딥러닝", "디자인 시스템", "리액트", "머신러닝", "브라우저",
        "생성형", "에이전트", "웹", "인공지능", "자바스크립트",
        "타입스크립트", "프론트", "프론트엔드",
    ]
    private static let collaborationTopicTokens: Set<String> = [
        "collaboration", "collaborative", "communication", "culture", "docs",
        "documentation", "github", "gitlab", "leadership", "maintainer",
        "maintainers", "mentoring", "productivity", "remote", "review",
        "reviews", "team", "teams", "teamwork", "workflow",
    ]
    private static let collaborationTopicPhrases = [
        "code review",
        "developer experience",
        "engineering culture",
        "pair programming",
        "pull request",
    ]
    private static let collaborationTopicFragments = [
        "개발자 경험", "리더십", "멘토링", "문서화", "생산성", "조직 문화",
        "코드 리뷰", "코드리뷰", "커뮤니케이션", "팀", "팀워크", "협업",
        "워크플로", "풀 리퀘스트",
    ]
    private static let infrastructureAndDataTopicTokens: Set<String> = [
        "analytics", "aws", "azure", "backend", "cloud", "data", "database",
        "databases", "deploy", "deployment", "devops", "docker", "gcp",
        "infra", "infrastructure", "k8s", "kafka", "kubernetes", "monitoring",
        "mysql", "observability", "pipeline", "postgres", "postgresql",
        "redis", "serverless", "spark", "sql", "sre", "warehouse",
    ]
    private static let infrastructureAndDataTopicPhrases = [
        "continuous delivery",
        "continuous integration",
        "data engineering",
        "data platform",
        "platform engineering",
    ]
    private static let infrastructureAndDataTopicFragments = [
        "관측성", "데이터", "데이터베이스", "데브옵스", "도커", "모니터링",
        "백엔드", "배포", "분석", "인프라", "클라우드", "쿠버네티스",
        "파이프라인",
    ]

    private let deduplicator: FeedCandidateDeduplicator
    private let canonicalizer: URLCanonicalizer

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
        now: Date
    ) throws -> FeedCandidate? {
        let candidates = try deduplicator.deduplicate(
            candidates.filter { isEligible($0, now: now) }
        )
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
                suppressRecentPenalty: allRecentlyRecommended,
                now: now
            )
            let rhsScore = score(
                rhs,
                interests: interests,
                readURLs: readURLs,
                recentURLs: recentURLs,
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
        suppressRecentPenalty: Bool,
        now: Date
    ) -> Int {
        return freshnessScore(candidate.publishedAt, now: now)
            + topicPriorityScore(candidate.title)
            + interestScore(candidate.title, interests: interests)
            + (candidate.isOfficialSource ? 15 : 0)
            + min(max(candidate.selectionWeight, 0), 100)
            + (readURLs.contains(candidate.articleURL) ? 0 : 10)
            - (
                !suppressRecentPenalty
                    && recentURLs.contains(candidate.articleURL) ? 60 : 0
            )
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

    private func topicPriorityScore(_ title: String) -> Int {
        if matchesTopic(
            title,
            tokens: Self.preferredTopicTokens,
            phrases: Self.preferredTopicPhrases,
            fragments: Self.preferredTopicFragments
        ) {
            return 120
        }
        if matchesTopic(
            title,
            tokens: Self.collaborationTopicTokens,
            phrases: Self.collaborationTopicPhrases,
            fragments: Self.collaborationTopicFragments
        ) {
            return 45
        }
        if matchesTopic(
            title,
            tokens: Self.infrastructureAndDataTopicTokens,
            phrases: Self.infrastructureAndDataTopicPhrases,
            fragments: Self.infrastructureAndDataTopicFragments
        ) {
            return 20
        }
        return 0
    }

    private func matchesTopic(
        _ title: String,
        tokens expectedTokens: Set<String>,
        phrases: [String],
        fragments: [String]
    ) -> Bool {
        let normalizedTitle = title.lowercased()
        let titleTokens = Set(tokens(in: normalizedTitle))
            .union(asciiTokens(in: normalizedTitle))
        return !titleTokens.isDisjoint(with: expectedTokens)
            || phrases.contains { normalizedTitle.contains($0) }
            || fragments.contains { normalizedTitle.contains($0) }
    }

    private func asciiTokens(in value: String) -> Set<String> {
        let separated = String(value.unicodeScalars.map { scalar in
            let value = scalar.value
            let isASCIILetter = (65...90).contains(value)
                || (97...122).contains(value)
            let isASCIIDigit = (48...57).contains(value)
            return isASCIILetter || isASCIIDigit
                ? Character(String(scalar))
                : Character(" ")
        })
        return Set(separated.split(separator: " ").map(String.init))
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
