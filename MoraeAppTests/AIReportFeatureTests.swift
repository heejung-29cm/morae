import MoraeCore
import XCTest
@testable import MoraeApp

private struct StubScriptRunner: AIReportScriptRunning {
    var payload: AIReportPayload?
    var scriptError: AIReportScriptError?
    var throwsDecodingError = false

    func run(day: LocalDay) async throws -> AIReportPayload {
        if let scriptError {
            throw scriptError
        }
        if throwsDecodingError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "stub")
            )
        }
        guard let payload else {
            throw AIReportScriptError.noData
        }
        return payload
    }
}

private func makePayload(
    headline: String = "조용한 하루",
    tokens: Int64? = 121_181_444,
    percentile: Int? = 95
) -> AIReportPayload {
    AIReportPayload(
        headline: headline,
        body: "• 별다른 신호 없음",
        tokenCount: tokens,
        tokenPercentile: percentile,
        costUSD: 86.72
    )
}

final class AIReportRepositoryTests: XCTestCase {
    func testStoresSucceededReportAndReadsItBack() async throws {
        let database = try AppDatabase.inMemory()
        let id = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!
        let repository = DatabaseAIReportRepository(
            database: database,
            uuidGenerator: FixedUUIDGenerator(uuid: id)
        )
        let day = try LocalDay(rawValue: "2026-08-11")
        let startedAt = Date(unixMilliseconds: 2_000_000_000_000)

        var report = try await repository.createRunning(day: day, at: startedAt)
        XCTAssertEqual(report.status, .running)
        XCTAssertNil(report.finishedAt)

        report.status = .succeeded
        report.headline = "조용한 하루"
        report.body = "• 별다른 신호 없음"
        report.tokenCount = 121_181_444
        report.tokenPercentile = 95
        report.costUSD = 86.72
        report.finishedAt = startedAt.addingTimeInterval(60)

        let stored = try await repository.finish(report: report)
        XCTAssertEqual(stored.status, .succeeded)
        XCTAssertEqual(stored.tokenCount, 121_181_444)
        XCTAssertEqual(stored.tokenPercentile, 95)

        let latest = try await repository.latest()
        XCTAssertEqual(latest?.id, report.id)
        XCTAssertEqual(latest?.headline, "조용한 하루")
    }

    /// 같은 날짜를 다시 요청하면 이전 행을 지우고 새로 만든다.
    /// UNIQUE(report_day) 때문에 덮어쓰지 않으면 두 번째 요청이 실패한다.
    func testRegeneratingSameDayReplacesPreviousRow() async throws {
        let database = try AppDatabase.inMemory()
        let day = try LocalDay(rawValue: "2026-08-11")
        let startedAt = Date(unixMilliseconds: 2_000_000_000_000)

        let first = DatabaseAIReportRepository(
            database: database,
            uuidGenerator: FixedUUIDGenerator(
                uuid: UUID(uuidString: "50000000-0000-0000-0000-000000000002")!
            )
        )
        var report = try await first.createRunning(day: day, at: startedAt)
        report.status = .succeeded
        report.headline = "첫 번째"
        report.body = "• 첫 번째"
        report.finishedAt = startedAt
        _ = try await first.finish(report: report)

        let second = DatabaseAIReportRepository(
            database: database,
            uuidGenerator: FixedUUIDGenerator(
                uuid: UUID(uuidString: "50000000-0000-0000-0000-000000000003")!
            )
        )
        var rerun = try await second.createRunning(day: day, at: startedAt)
        rerun.status = .succeeded
        rerun.headline = "두 번째"
        rerun.body = "• 두 번째"
        rerun.finishedAt = startedAt
        _ = try await second.finish(report: rerun)

        let latest = try await second.latest()
        XCTAssertEqual(latest?.headline, "두 번째")
    }

    /// succeeded 인데 본문이 없으면 저장 전에 막아야 한다.
    /// 그대로 통과하면 DB CHECK 제약에 걸려 예외 종류가 달라진다.
    func testRejectsSucceededWithoutBody() async throws {
        let database = try AppDatabase.inMemory()
        let repository = DatabaseAIReportRepository(
            database: database,
            uuidGenerator: FixedUUIDGenerator(
                uuid: UUID(uuidString: "50000000-0000-0000-0000-000000000004")!
            )
        )
        let day = try LocalDay(rawValue: "2026-08-11")
        var report = try await repository.createRunning(
            day: day,
            at: Date(unixMilliseconds: 2_000_000_000_000)
        )
        report.status = .succeeded
        report.finishedAt = Date(unixMilliseconds: 2_000_000_060_000)

        await XCTAssertThrowsErrorAsync(
            try await repository.finish(report: report)
        ) { error in
            XCTAssertEqual(
                error as? AIReportRepositoryError,
                .invalidTransition
            )
        }
    }
}

final class GenerateAIReportTests: XCTestCase {
    private func makeUseCase(
        runner: StubScriptRunner,
        database: AppDatabase
    ) -> GenerateAIReport {
        GenerateAIReport(
            repository: DatabaseAIReportRepository(
                database: database,
                uuidGenerator: FixedUUIDGenerator(
                    uuid: UUID(
                        uuidString: "50000000-0000-0000-0000-00000000000A"
                    )!
                )
            ),
            scriptRunner: runner,
            clock: FixedClock(instant: Date(unixMilliseconds: 2_000_000_000_000))
        )
    }

    func testGeneratesReportFromScriptPayload() async throws {
        let database = try AppDatabase.inMemory()
        let useCase = makeUseCase(
            runner: StubScriptRunner(payload: makePayload()),
            database: database
        )

        let result = await useCase.execute(
            day: try LocalDay(rawValue: "2026-08-11")
        )

        guard case let .generated(report) = result else {
            return XCTFail("생성 성공을 기대했지만 \(result) 였다")
        }
        XCTAssertEqual(report.status, .succeeded)
        XCTAssertEqual(report.headline, "조용한 하루")
        XCTAssertEqual(report.tokenCount, 121_181_444)
        XCTAssertEqual(report.tokenPercentile, 95)
    }

    /// 스크립트 실패 종류가 사용자에게 보이는 안내 문구를 가른다.
    func testMapsScriptFailuresToErrorCodes() async throws {
        let cases: [(StubScriptRunner, AIReportErrorCode)] = [
            (StubScriptRunner(scriptError: .missing), .scriptMissing),
            (StubScriptRunner(scriptError: .noData), .noData),
            (
                StubScriptRunner(scriptError: .failed(code: 5, stderr: "boom")),
                .scriptFailed
            ),
            (StubScriptRunner(throwsDecodingError: true), .invalidOutput),
        ]

        for (runner, expected) in cases {
            let database = try AppDatabase.inMemory()
            let useCase = makeUseCase(runner: runner, database: database)

            let result = await useCase.execute(
                day: try LocalDay(rawValue: "2026-08-11")
            )

            guard case let .failed(_, code) = result else {
                return XCTFail("실패를 기대했지만 \(result) 였다")
            }
            XCTAssertEqual(code, expected)
        }
    }

    /// 실패해도 그 사실이 저장돼야 앱을 다시 열었을 때 상태가 남는다.
    func testPersistsFailureSoItSurvivesRelaunch() async throws {
        let database = try AppDatabase.inMemory()
        let repository = DatabaseAIReportRepository(
            database: database,
            uuidGenerator: FixedUUIDGenerator(
                uuid: UUID(uuidString: "50000000-0000-0000-0000-00000000000B")!
            )
        )
        let useCase = GenerateAIReport(
            repository: repository,
            scriptRunner: StubScriptRunner(scriptError: .missing),
            clock: FixedClock(
                instant: Date(unixMilliseconds: 2_000_000_000_000)
            )
        )

        _ = await useCase.execute(day: try LocalDay(rawValue: "2026-08-11"))

        let latest = try await repository.latest()
        XCTAssertEqual(latest?.status, .failed)
        XCTAssertEqual(latest?.errorCode, .scriptMissing)
    }

    // MARK: - bodyLines

    private func makeReport(body: String?) throws -> AIReport {
        AIReport(
            id: AIReportID(rawValue: UUID()),
            day: try LocalDay(rawValue: "2026-08-11"),
            status: .succeeded,
            headline: "테스트",
            body: body,
            tokenCount: nil,
            tokenPercentile: nil,
            costUSD: nil,
            triggeredAt: Date(),
            finishedAt: nil,
            errorCode: nil
        )
    }

    func testBodyLinesStripsMarkersAndFlagsAction() throws {
        let report = try makeReport(body: "• 프롬프트 17개 중 파일 경로 0개\n• 계획 도구 0번\n🎯 파일 경로 하나 붙이기")

        let lines = report.bodyLines

        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].text, "프롬프트 17개 중 파일 경로 0개")
        XCTAssertFalse(lines[0].isAction)
        XCTAssertEqual(lines[2].text, "파일 경로 하나 붙이기")
        XCTAssertTrue(lines[2].isAction)
    }

    func testBodyLinesDropsEmptyAndMarkerOnlyLines() throws {
        let report = try makeReport(body: "• 첫 줄\n\n   \n•\n• 둘째 줄")

        XCTAssertEqual(report.bodyLines.map(\.text), ["첫 줄", "둘째 줄"])
    }

    func testBodyLinesHandlesMissingOrEmptyBody() throws {
        XCTAssertTrue(try makeReport(body: nil).bodyLines.isEmpty)
        XCTAssertTrue(try makeReport(body: "").bodyLines.isEmpty)
    }

    func testBodyLinesKeepsTextWithoutMarker() throws {
        let report = try makeReport(body: "마커 없는 줄\n- 하이픈 줄")

        XCTAssertEqual(report.bodyLines.map(\.text), ["마커 없는 줄", "하이픈 줄"])
    }

}
