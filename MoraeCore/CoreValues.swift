import Foundation

public enum CoreValueError: Error, Equatable, Sendable {
    case invalidLocalDay(String)
}

public struct LocalDay: Hashable, Codable, Sendable, Comparable {
    public let rawValue: String

    public init(rawValue: String) throws {
        let components = rawValue.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0].count == 4,
              components[1].count == 2,
              components[2].count == 2,
              components.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2]),
              (1...12).contains(month),
              (1...31).contains(day) else {
            throw CoreValueError.invalidLocalDay(rawValue)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let requestedComponents = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: requestedComponents) else {
            throw CoreValueError.invalidLocalDay(rawValue)
        }
        let normalizedComponents = calendar.dateComponents([.year, .month, .day], from: date)
        guard normalizedComponents.year == year,
              normalizedComponents.month == month,
              normalizedComponents.day == day else {
            throw CoreValueError.invalidLocalDay(rawValue)
        }

        self.rawValue = rawValue
    }

    public init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        precondition(
            components.year != nil && components.month != nil && components.day != nil,
            "Calendar must provide year, month, and day components."
        )
        rawValue = String(
            format: "%04d-%02d-%02d",
            components.year!,
            components.month!,
            components.day!
        )
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public protocol Clock: Sendable {
    func now() -> Date
    func localDay(for date: Date, calendar: Calendar) -> LocalDay
}

public extension Clock {
    func localDay(for date: Date, calendar: Calendar) -> LocalDay {
        LocalDay(date: date, calendar: calendar)
    }
}

public struct SystemClock: Clock {
    public init() {}

    public func now() -> Date {
        Date()
    }
}

public extension Date {
    var unixMilliseconds: Int64 {
        Int64((timeIntervalSince1970 * 1_000).rounded(.towardZero))
    }

    init(unixMilliseconds: Int64) {
        self.init(timeIntervalSince1970: TimeInterval(unixMilliseconds) / 1_000)
    }
}

public protocol UUIDBackedID:
    Hashable,
    Codable,
    Sendable,
    CustomStringConvertible
{
    var rawValue: UUID { get }
    init(rawValue: UUID)
}

public extension UUIDBackedID {
    var storageValue: String {
        rawValue.uuidString.lowercased()
    }

    var description: String {
        storageValue
    }
}

public struct TodoID: UUIDBackedID {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct ArticleID: UUIDBackedID {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct BriefingRunID: UUIDBackedID {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct AgentRunID: UUIDBackedID {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct AgentEventID: UUIDBackedID {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}
