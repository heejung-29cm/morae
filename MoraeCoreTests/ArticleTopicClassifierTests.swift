@testable import MoraeCore
import XCTest

final class ArticleTopicClassifierTests: XCTestCase {
    func testClassifiesTitlesByConfiguredPriority() {
        let classifier = ArticleTopicClassifier()
        let cases: [(String, ArticleTopic)] = [
            ("AI로 브라우저 에이전트를 설계한 경험", .aiAndFrontend),
            ("React Server Components in production", .aiAndFrontend),
            ("코드 리뷰로 더 나은 팀 협업 만들기", .collaboration),
            ("Cloud observability patterns", .infrastructureAndData),
            ("A thoughtful engineering essay", .other),
            (
                "AI infrastructure for team collaboration",
                .aiAndFrontend
            ),
        ]

        for (title, expectedTopic) in cases {
            XCTAssertEqual(
                classifier.classify(title),
                expectedTopic,
                title
            )
        }
    }
}
