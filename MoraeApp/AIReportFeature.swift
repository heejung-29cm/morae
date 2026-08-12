import Foundation
import GRDB
import MoraeCore

// MARK: - Domain

struct AIReportID: Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    var storageValue: String {
        rawValue.uuidString
    }
}

enum AIReportStatus: String, Sendable, Equatable {
    case running
    case succeeded
    case failed
}

enum AIReportErrorCode: String, Sendable, Equatable {
    case scriptMissing = "script_missing"
    case scriptFailed = "script_failed"
    case invalidOutput = "invalid_output"
    case noData = "no_data"

    var title: String {
        switch self {
        case .scriptMissing: "리포트 스크립트를 찾지 못했습니다."
        case .scriptFailed: "리포트를 만들지 못했습니다."
        case .invalidOutput: "리포트 형식을 읽지 못했습니다."
        case .noData: "어제 기록이 없습니다."
        }
    }

    var message: String {
        switch self {
        case .scriptMissing:
            "~/.claude/ai-report/morae-report.sh 가 필요합니다."
        case .scriptFailed:
            "스크립트가 오류로 종료했습니다."
        case .invalidOutput:
            "스크립트 출력이 예상한 JSON이 아닙니다."
        case .noData:
            "어제는 기록된 AI 사용이 없습니다."
        }
    }

    var recovery: String {
        switch self {
        case .scriptMissing:
            "스크립트를 설치한 뒤 다시 눌러 주세요."
        case .scriptFailed, .invalidOutput:
            "잠시 후 다시 눌러 주세요. 반복되면 스크립트 로그를 확인하세요."
        case .noData:
            "AI 작업을 한 다음 날 다시 확인해 주세요."
        }
    }
}

/// 하루치 AI 활용 리포트. 본문은 스크립트가 생성한 사람이 읽는 텍스트이고,
/// 숫자 필드는 한눈에 보여 주기 위해 별도로 저장한다.
/// 리포트 본문 한 줄. 마커(•, 🎯)는 렌더러가 그리므로 텍스트에서 떼어 둔다.
struct AIReportBodyLine: Equatable, Sendable {
    let text: String
    /// 🎯 로 시작하던 줄 — 그날 시도할 행동. 나머지와 구분해 그린다.
    let isAction: Bool
}

extension AIReport {
    /// 본문을 줄 단위로 쪼개고 선행 마커를 떼어낸다.
    ///
    /// 생성 스크립트가 "• " / "🎯 " 를 문자열에 직접 박아 보내므로, 렌더러가 매달린 들여쓰기로
    /// 그리려면 마커와 본문을 분리해야 한다. 빈 줄과 마커만 있는 줄은 버린다.
    var bodyLines: [AIReportBodyLine] {
        guard let body, !body.isEmpty else { return [] }

        return body.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }

            let isAction = line.hasPrefix("🎯")
            let text = Self.strippingLeadingMarker(line)
            guard !text.isEmpty else { return nil }

            return AIReportBodyLine(text: text, isAction: isAction)
        }
    }

    private static func strippingLeadingMarker(_ line: String) -> String {
        for marker in ["🎯", "•", "-", "*"] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return line
    }
}

struct AIReport: Equatable, Sendable {
    let id: AIReportID
    let day: LocalDay
    var status: AIReportStatus
    var headline: String?
    var body: String?
    var tokenCount: Int64?
    var tokenPercentile: Int?
    var costUSD: Double?
    let triggeredAt: Date
    var finishedAt: Date?
    var errorCode: AIReportErrorCode?
}

// MARK: - Repository

protocol AIReportRepository: Sendable {
    func createRunning(day: LocalDay, at: Date) async throws -> AIReport
    func finish(report: AIReport) async throws -> AIReport
    func latest() async throws -> AIReport?
}

enum AIReportRepositoryError: Error, Equatable, Sendable {
    case invalidTransition
    case reportNotFound(AIReportID)
}

enum AIReportMappingError: Error, Equatable, Sendable {
    case invalidID(String)
    case invalidDay(String)
    case invalidStatus(String)
    case invalidErrorCode(String)
}

struct AIReportRecord:
    Codable,
    FetchableRecord,
    PersistableRecord,
    TableRecord,
    Sendable
{
    static let databaseTableName = "ai_reports"

    let id: String
    let reportDay: String
    var status: String
    var headline: String?
    var body: String?
    var tokenCount: Int64?
    var tokenPercentile: Int?
    var costUSD: Double?
    let triggeredAtMs: Int64
    var finishedAtMs: Int64?
    var errorCode: String?

    enum CodingKeys: String, CodingKey {
        case id
        case reportDay = "report_day"
        case status
        case headline
        case body
        case tokenCount = "token_count"
        case tokenPercentile = "token_percentile"
        case costUSD = "cost_usd"
        case triggeredAtMs = "triggered_at_ms"
        case finishedAtMs = "finished_at_ms"
        case errorCode = "error_code"
    }

    init(report: AIReport) {
        id = report.id.storageValue
        reportDay = report.day.rawValue
        status = report.status.rawValue
        headline = report.headline
        body = report.body
        tokenCount = report.tokenCount
        tokenPercentile = report.tokenPercentile
        costUSD = report.costUSD
        triggeredAtMs = report.triggeredAt.unixMilliseconds
        finishedAtMs = report.finishedAt?.unixMilliseconds
        errorCode = report.errorCode?.rawValue
    }

    func domain() throws -> AIReport {
        guard let uuid = UUID(uuidString: id) else {
            throw AIReportMappingError.invalidID(id)
        }
        let day: LocalDay
        do {
            day = try LocalDay(rawValue: reportDay)
        } catch {
            throw AIReportMappingError.invalidDay(reportDay)
        }
        guard let status = AIReportStatus(rawValue: status) else {
            throw AIReportMappingError.invalidStatus(self.status)
        }
        let errorCode: AIReportErrorCode?
        if let value = self.errorCode {
            guard let code = AIReportErrorCode(rawValue: value) else {
                throw AIReportMappingError.invalidErrorCode(value)
            }
            errorCode = code
        } else {
            errorCode = nil
        }
        return AIReport(
            id: AIReportID(rawValue: uuid),
            day: day,
            status: status,
            headline: headline,
            body: body,
            tokenCount: tokenCount,
            tokenPercentile: tokenPercentile,
            costUSD: costUSD,
            triggeredAt: Date(unixMilliseconds: triggeredAtMs),
            finishedAt: finishedAtMs.map(Date.init(unixMilliseconds:)),
            errorCode: errorCode
        )
    }
}

struct DatabaseAIReportRepository: AIReportRepository {
    private let writer: any DatabaseWriter
    private let uuidGenerator: any UUIDGenerating

    init(
        database: AppDatabase,
        uuidGenerator: any UUIDGenerating = SystemUUIDGenerator()
    ) {
        writer = database.writer
        self.uuidGenerator = uuidGenerator
    }

    /// 같은 날짜의 이전 리포트는 덮어쓴다. 하루에 한 행만 유지해
    /// "어제의 리포트"가 항상 하나로 결정되게 한다.
    func createRunning(day: LocalDay, at date: Date) async throws -> AIReport {
        let report = AIReport(
            id: AIReportID(rawValue: uuidGenerator.next()),
            day: day,
            status: .running,
            triggeredAt: date
        )
        try await writer.write { database in
            try database.execute(
                sql: "DELETE FROM ai_reports WHERE report_day = ?",
                arguments: [day.rawValue]
            )
            try AIReportRecord(report: report).insert(database)
        }
        return report
    }

    func finish(report: AIReport) async throws -> AIReport {
        guard report.status != .running,
              report.finishedAt != nil,
              (report.status == .succeeded)
                == (report.headline != nil && report.body != nil),
              (report.status == .failed) == (report.errorCode != nil) else {
            throw AIReportRepositoryError.invalidTransition
        }
        return try await writer.write { database in
            try database.execute(
                sql: """
                    UPDATE ai_reports
                    SET status = ?,
                        headline = ?,
                        body = ?,
                        token_count = ?,
                        token_percentile = ?,
                        cost_usd = ?,
                        finished_at_ms = ?,
                        error_code = ?
                    WHERE id = ? AND status = 'running'
                    """,
                arguments: [
                    report.status.rawValue,
                    report.headline,
                    report.body,
                    report.tokenCount,
                    report.tokenPercentile,
                    report.costUSD,
                    report.finishedAt?.unixMilliseconds,
                    report.errorCode?.rawValue,
                    report.id.storageValue,
                ]
            )
            guard database.changesCount == 1,
                  let stored = try AIReportRecord.fetchOne(
                    database,
                    key: report.id.storageValue
                  )?.domain() else {
                throw AIReportRepositoryError.reportNotFound(report.id)
            }
            return stored
        }
    }

    func latest() async throws -> AIReport? {
        try await writer.read { database in
            try AIReportRecord.fetchOne(
                database,
                sql: """
                    SELECT *
                    FROM ai_reports
                    WHERE status != 'running'
                    ORDER BY report_day DESC
                    LIMIT 1
                    """
            )?.domain()
        }
    }
}

// MARK: - Script runner

/// 스크립트가 stdout 으로 내보내는 리포트 페이로드.
struct AIReportPayload: Decodable, Equatable, Sendable {
    let headline: String
    let body: String
    let tokenCount: Int64?
    let tokenPercentile: Int?
    let costUSD: Double?

    enum CodingKeys: String, CodingKey {
        case headline
        case body
        case tokenCount = "token_count"
        case tokenPercentile = "token_percentile"
        case costUSD = "cost_usd"
    }
}

enum AIReportScriptError: Error, Equatable, Sendable {
    case missing
    case failed(code: Int32, stderr: String)
    case noData
}

protocol AIReportScriptRunning: Sendable {
    func run(day: LocalDay) async throws -> AIReportPayload
}

/// `~/.claude/ai-report/morae-report.sh <day>` 를 실행하고 stdout JSON 을 읽는다.
/// 스크립트가 Claude Code 를 거쳐 Weave MCP 와 로컬 transcript 를 모두 수집하므로
/// 앱은 OAuth 토큰을 직접 다루지 않는다.
struct LiveAIReportScriptRunner: AIReportScriptRunning {
    private let scriptURL: URL

    init(scriptURL: URL? = nil) {
        self.scriptURL = scriptURL
            ?? FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/ai-report/morae-report.sh")
    }

    func run(day: LocalDay) async throws -> AIReportPayload {
        guard FileManager.default.isExecutableFile(atPath: scriptURL.path) else {
            throw AIReportScriptError.missing
        }
        let path = scriptURL.path
        let dayValue = day.rawValue

        let output: (status: Int32, stdout: Data, stderr: String) =
            try await Task.detached(priority: .userInitiated) {
                let process = Process()
                // 로그인 셸로 실행해야 스크립트가 쓰는 claude CLI 가 PATH 에 잡힌다.
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-lc", "\"$0\" \"$1\"", path, dayValue]

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                try process.run()
                // 파이프 버퍼가 가득 차 교착되지 않도록 종료 대기 전에 읽는다.
                let outData = stdoutPipe.fileHandleForReading
                    .readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading
                    .readDataToEndOfFile()
                process.waitUntilExit()

                return (
                    process.terminationStatus,
                    outData,
                    String(decoding: errData, as: UTF8.self)
                )
            }.value

        guard output.status == 0 else {
            throw AIReportScriptError.failed(
                code: output.status,
                stderr: output.stderr
            )
        }
        if let marker = try? JSONDecoder().decode(
            [String: String].self,
            from: output.stdout
        ), marker["error"] == "no_data" {
            throw AIReportScriptError.noData
        }
        return try JSONDecoder().decode(
            AIReportPayload.self,
            from: output.stdout
        )
    }
}

// MARK: - Use case

enum AIReportResult: Equatable, Sendable {
    case generated(AIReport)
    case failed(AIReport?, code: AIReportErrorCode)
    case alreadyRunning
}

protocol AIReportGenerating: Sendable {
    func execute(day: LocalDay) async -> AIReportResult
}

actor GenerateAIReport: AIReportGenerating {
    private let repository: any AIReportRepository
    private let scriptRunner: any AIReportScriptRunning
    private let clock: any Clock
    private var isRunning = false

    init(
        repository: any AIReportRepository,
        scriptRunner: any AIReportScriptRunning,
        clock: any Clock
    ) {
        self.repository = repository
        self.scriptRunner = scriptRunner
        self.clock = clock
    }

    func execute(day: LocalDay) async -> AIReportResult {
        guard !isRunning else {
            return .alreadyRunning
        }
        isRunning = true
        defer { isRunning = false }

        var report: AIReport
        do {
            report = try await repository.createRunning(
                day: day,
                at: clock.now()
            )
        } catch {
            return .failed(nil, code: .scriptFailed)
        }

        do {
            let payload = try await scriptRunner.run(day: day)
            report.status = .succeeded
            report.headline = payload.headline
            report.body = payload.body
            report.tokenCount = payload.tokenCount
            report.tokenPercentile = payload.tokenPercentile
            report.costUSD = payload.costUSD
            report.finishedAt = clock.now()
            let stored = try await repository.finish(report: report)
            return .generated(stored)
        } catch {
            let code = Self.errorCode(for: error)
            report.status = .failed
            report.errorCode = code
            report.finishedAt = clock.now()
            let stored = try? await repository.finish(report: report)
            return .failed(stored, code: code)
        }
    }

    private static func errorCode(for error: any Error) -> AIReportErrorCode {
        switch error {
        case AIReportScriptError.missing: .scriptMissing
        case AIReportScriptError.noData: .noData
        case AIReportScriptError.failed: .scriptFailed
        case is DecodingError: .invalidOutput
        default: .scriptFailed
        }
    }
}
