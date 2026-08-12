import Foundation
import OSLog

enum MoraeLogCategory: String, CaseIterable, Sendable {
    case appLifecycle = "app-lifecycle"
    case database
    case briefing
    case feed
    case agentIPC = "agent-ipc"
    case agentNormalization = "agent-normalization"
    case notification
    case jira
}

struct PublicLogToken: Equatable, Sendable, CustomStringConvertible {
    static let redacted = PublicLogToken(validated: "redacted")

    let description: String

    init(_ candidate: String) {
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_.-"
        )
        if !candidate.isEmpty,
           candidate.utf8.count <= 64,
           candidate.unicodeScalars.allSatisfy(allowed.contains) {
            description = candidate
        } else {
            self = .redacted
        }
    }

    private init(validated: String) {
        description = validated
    }
}

struct PublicLogMetadata: Equatable, Sendable, CustomStringConvertible {
    var result: PublicLogToken?
    var durationMilliseconds: Int?
    var byteCount: Int?
    var httpStatus: Int?
    var migrationVersion: Int?
    var count: Int?
    var errorCode: PublicLogToken?

    var description: String {
        [
            result.map { "result=\($0)" },
            durationMilliseconds.map { "duration_ms=\($0)" },
            byteCount.map { "byte_count=\($0)" },
            httpStatus.map { "http_status=\($0)" },
            migrationVersion.map { "migration_version=\($0)" },
            count.map { "count=\($0)" },
            errorCode.map { "error_code=\($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }
}

struct MoraeLogger: Sendable {
    static let subsystem = "io.github.heejung-29cm.morae"

    private let logger: Logger

    init(category: MoraeLogCategory) {
        logger = Logger(subsystem: Self.subsystem, category: category.rawValue)
    }

    func notice(
        event: PublicLogToken,
        metadata: PublicLogMetadata = PublicLogMetadata()
    ) {
        logger.notice(
            "event=\(event.description, privacy: .public) \(metadata.description, privacy: .public)"
        )
    }

    func error(
        event: PublicLogToken,
        metadata: PublicLogMetadata = PublicLogMetadata()
    ) {
        logger.error(
            "event=\(event.description, privacy: .public) \(metadata.description, privacy: .public)"
        )
    }
}
