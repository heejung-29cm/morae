import Foundation
import MoraeCore

protocol FeedClient: Sendable {
    func candidates(from source: FeedSource) async throws -> [FeedCandidate]
}

struct LiveFeedClient: FeedClient, Sendable {
    let httpClient: any HTTPClient
    let parser: FeedMetadataParser

    init(
        httpClient: any HTTPClient = RestrictedHTTPClient(),
        parser: FeedMetadataParser = FeedMetadataParser()
    ) {
        self.httpClient = httpClient
        self.parser = parser
    }

    func candidates(
        from source: FeedSource
    ) async throws -> [FeedCandidate] {
        var request = URLRequest(url: source.feedURL)
        request.httpMethod = "GET"
        request.setValue(
            "application/atom+xml, application/rss+xml, application/xml, text/xml",
            forHTTPHeaderField: "Accept"
        )
        let (data, _) = try await httpClient.data(for: request)
        return try parser.parse(data: data, source: source)
    }
}

protocol BriefingPreferences: Sendable {
    func interests() -> [String]
}

final class UserDefaultsBriefingPreferences:
    BriefingPreferences,
    @unchecked Sendable
{
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func interests() -> [String] {
        defaults.stringArray(forKey: "settings.interests") ?? []
    }
}

struct GeneratedBriefing: Equatable, Sendable {
    let stored: StoredBriefing
    let localTasks: LocalTaskSummary
    let failedFeedCount: Int
}

struct FailedBriefing: Equatable, Sendable {
    let run: BriefingRun?
    let localTasks: LocalTaskSummary?
    let code: BriefingErrorCode
    let failedFeedCount: Int
}

enum BriefingResult: Equatable, Sendable {
    case generated(GeneratedBriefing)
    case failed(FailedBriefing)
    case alreadyRunning
}

actor GenerateBriefing {
    private let todoSummary: BuildLocalTaskSummary
    private let feedSourceRepository: any FeedSourceRepository
    private let feedClient: any FeedClient
    private let articleRepository: any ArticleRepository
    private let briefingRepository: any BriefingRepository
    private let preferences: any BriefingPreferences
    private let selector: ArticleSelector
    private let canonicalizer: URLCanonicalizer
    private let clock: any Clock
    private let uuidGenerator: any UUIDGenerating
    private let calendar: Calendar
    private var activeRunID: BriefingRunID?

    init(
        todoRepository: any TodoRepository,
        feedSourceRepository: any FeedSourceRepository,
        feedClient: any FeedClient,
        articleRepository: any ArticleRepository,
        briefingRepository: any BriefingRepository,
        preferences: any BriefingPreferences,
        selector: ArticleSelector = ArticleSelector(),
        canonicalizer: URLCanonicalizer = URLCanonicalizer(),
        clock: any Clock,
        uuidGenerator: any UUIDGenerating,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        todoSummary = BuildLocalTaskSummary(repository: todoRepository)
        self.feedSourceRepository = feedSourceRepository
        self.feedClient = feedClient
        self.articleRepository = articleRepository
        self.briefingRepository = briefingRepository
        self.preferences = preferences
        self.selector = selector
        self.canonicalizer = canonicalizer
        self.clock = clock
        self.uuidGenerator = uuidGenerator
        self.calendar = calendar
    }

    func execute(day: LocalDay) async -> BriefingResult {
        guard activeRunID == nil else {
            return .alreadyRunning
        }

        let startedAt = clock.now()
        let run: BriefingRun
        do {
            run = try await briefingRepository.createRunning(
                day: day,
                at: startedAt
            )
        } catch {
            return .failed(
                FailedBriefing(
                    run: nil,
                    localTasks: nil,
                    code: .persistenceFailed,
                    failedFeedCount: 0
                )
            )
        }
        activeRunID = run.id
        defer { activeRunID = nil }

        let localTasks: LocalTaskSummary
        do {
            localTasks = try await todoSummary.execute(
                today: day,
                calendar: calendar
            )
        } catch {
            return await finishFailure(
                run: run,
                localTasks: nil,
                code: .persistenceFailed,
                failedFeedCount: 0
            )
        }

        let sources: [FeedSource]
        do {
            sources = Array(
                try await feedSourceRepository.enabledSources().prefix(4)
            )
        } catch {
            return await finishFailure(
                run: run,
                localTasks: localTasks,
                code: .persistenceFailed,
                failedFeedCount: 0
            )
        }
        guard !sources.isEmpty else {
            return await finishFailure(
                run: run,
                localTasks: localTasks,
                code: .noEnabledFeeds,
                failedFeedCount: 0
            )
        }

        let feedResult = await fetchCandidates(from: sources)
        guard !feedResult.candidates.isEmpty else {
            return await finishFailure(
                run: run,
                localTasks: localTasks,
                code: feedResult.failedCount == sources.count
                    ? .feedUnavailable
                    : .noCandidates,
                failedFeedCount: feedResult.failedCount
            )
        }

        do {
            async let readURLs = articleRepository.readURLs()
            async let recentURLs = articleRepository
                .previouslyRecommendedURLs()
            guard let selected = try await selector.select(
                from: feedResult.candidates,
                interests: preferences.interests(),
                readURLs: readURLs,
                recentlyRecommendedURLs: recentURLs,
                now: startedAt
            ) else {
                return await finishFailure(
                    run: run,
                    localTasks: localTasks,
                    code: .noCandidates,
                    failedFeedCount: feedResult.failedCount
                )
            }
            let now = clock.now()
            let article = Article(
                id: ArticleID(rawValue: uuidGenerator.next()),
                canonicalURL: try canonicalizer.canonicalize(
                    selected.articleURL
                ),
                title: selected.title,
                sourceName: selected.sourceName,
                sourceURL: selected.sourceURL,
                publishedAt: selected.publishedAt,
                isRead: false,
                isLiked: false,
                createdAt: now,
                updatedAt: now
            )
            var succeeded = run
            succeeded.status = .succeeded
            succeeded.finishedAt = now
            let stored = try await briefingRepository.finish(
                run: succeeded,
                article: article
            )
            return .generated(
                GeneratedBriefing(
                    stored: stored,
                    localTasks: localTasks,
                    failedFeedCount: feedResult.failedCount
                )
            )
        } catch {
            return await finishFailure(
                run: run,
                localTasks: localTasks,
                code: .persistenceFailed,
                failedFeedCount: feedResult.failedCount
            )
        }
    }

    private func fetchCandidates(
        from sources: [FeedSource]
    ) async -> (candidates: [FeedCandidate], failedCount: Int) {
        let feedClient = self.feedClient
        return await withTaskGroup(
            of: FeedAttempt.self,
            returning: ([FeedCandidate], Int).self
        ) { group in
            for source in sources {
                group.addTask {
                    do {
                        let candidates = try await feedClient.candidates(
                            from: source
                        )
                        return FeedAttempt(
                            candidates: candidates,
                            failed: false
                        )
                    } catch {
                        return FeedAttempt(candidates: [], failed: true)
                    }
                }
            }

            var candidates: [FeedCandidate] = []
            var failedCount = 0
            for await attempt in group {
                candidates.append(contentsOf: attempt.candidates)
                if attempt.failed {
                    failedCount += 1
                }
            }
            return (candidates, failedCount)
        }
    }

    private func finishFailure(
        run: BriefingRun,
        localTasks: LocalTaskSummary?,
        code: BriefingErrorCode,
        failedFeedCount: Int
    ) async -> BriefingResult {
        var failed = run
        failed.status = .failed
        failed.finishedAt = clock.now()
        failed.errorCode = code
        do {
            let stored = try await briefingRepository.finish(
                run: failed,
                article: nil
            )
            return .failed(
                FailedBriefing(
                    run: stored.run,
                    localTasks: localTasks,
                    code: code,
                    failedFeedCount: failedFeedCount
                )
            )
        } catch {
            return .failed(
                FailedBriefing(
                    run: run,
                    localTasks: localTasks,
                    code: .persistenceFailed,
                    failedFeedCount: failedFeedCount
                )
            )
        }
    }
}

private struct FeedAttempt: Sendable {
    let candidates: [FeedCandidate]
    let failed: Bool
}
