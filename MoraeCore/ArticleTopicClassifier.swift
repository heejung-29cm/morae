import Foundation

enum ArticleTopic: Int, Sendable {
    case other = 0
    case infrastructureAndData = 20
    case collaboration = 45
    case aiAndFrontend = 120

    var selectionScore: Int {
        rawValue
    }
}

struct ArticleTopicClassifier: Sendable {
    private static let aiAndFrontendTokens: Set<String> = [
        "agent", "agentic", "agents", "ai", "angular", "browser", "chrome",
        "claude", "css", "fe", "frontend", "gemini", "gpt", "html",
        "javascript", "llm", "mcp", "ml", "rag", "react", "safari",
        "svelte", "transformer", "typescript", "vue", "wasm", "web",
        "webassembly",
    ]
    private static let aiAndFrontendPhrases = [
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
    private static let aiAndFrontendFragments = [
        "딥러닝", "디자인 시스템", "리액트", "머신러닝", "브라우저",
        "생성형", "에이전트", "웹", "인공지능", "자바스크립트",
        "타입스크립트", "프론트", "프론트엔드",
    ]
    private static let collaborationTokens: Set<String> = [
        "collaboration", "collaborative", "communication", "culture", "docs",
        "documentation", "github", "gitlab", "leadership", "maintainer",
        "maintainers", "mentoring", "productivity", "remote", "review",
        "reviews", "team", "teams", "teamwork", "workflow",
    ]
    private static let collaborationPhrases = [
        "code review",
        "developer experience",
        "engineering culture",
        "pair programming",
        "pull request",
    ]
    private static let collaborationFragments = [
        "개발자 경험", "리더십", "멘토링", "문서화", "생산성", "조직 문화",
        "코드 리뷰", "코드리뷰", "커뮤니케이션", "팀", "팀워크", "협업",
        "워크플로", "풀 리퀘스트",
    ]
    private static let infrastructureAndDataTokens: Set<String> = [
        "analytics", "aws", "azure", "backend", "cloud", "data", "database",
        "databases", "deploy", "deployment", "devops", "docker", "gcp",
        "infra", "infrastructure", "k8s", "kafka", "kubernetes", "monitoring",
        "mysql", "observability", "pipeline", "postgres", "postgresql",
        "redis", "serverless", "spark", "sql", "sre", "warehouse",
    ]
    private static let infrastructureAndDataPhrases = [
        "continuous delivery",
        "continuous integration",
        "data engineering",
        "data platform",
        "platform engineering",
    ]
    private static let infrastructureAndDataFragments = [
        "관측성", "데이터", "데이터베이스", "데브옵스", "도커", "모니터링",
        "백엔드", "배포", "분석", "인프라", "클라우드", "쿠버네티스",
        "파이프라인",
    ]

    func classify(_ title: String) -> ArticleTopic {
        if matches(
            title,
            tokens: Self.aiAndFrontendTokens,
            phrases: Self.aiAndFrontendPhrases,
            fragments: Self.aiAndFrontendFragments
        ) {
            return .aiAndFrontend
        }
        if matches(
            title,
            tokens: Self.collaborationTokens,
            phrases: Self.collaborationPhrases,
            fragments: Self.collaborationFragments
        ) {
            return .collaboration
        }
        if matches(
            title,
            tokens: Self.infrastructureAndDataTokens,
            phrases: Self.infrastructureAndDataPhrases,
            fragments: Self.infrastructureAndDataFragments
        ) {
            return .infrastructureAndData
        }
        return .other
    }

    private func matches(
        _ title: String,
        tokens expectedTokens: Set<String>,
        phrases: [String],
        fragments: [String]
    ) -> Bool {
        let normalizedTitle = title.lowercased()
        let titleTokens = asciiTokens(in: normalizedTitle)
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
}
