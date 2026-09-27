import Foundation

/// Injected into every scheduler entry point so tests control time (DESIGN.md §3.1).
public protocol Clock: Sendable {
    func now() -> Date
    func today() -> DayKey
}

/// Production clock: the real current instant, mapped to a day through `calendar`.
public struct SystemClock: Clock {
    public let calendar: DayCalendar

    public init(calendar: DayCalendar) {
        self.calendar = calendar
    }

    public func now() -> Date {
        Date()
    }

    public func today() -> DayKey {
        calendar.dayKey(for: now())
    }
}

/// Deterministic clock for tests and simulations.
public struct FixedClock: Clock {
    public var date: Date
    public let calendar: DayCalendar

    public init(date: Date, calendar: DayCalendar) {
        self.date = date
        self.calendar = calendar
    }

    public func now() -> Date {
        date
    }

    public func today() -> DayKey {
        calendar.dayKey(for: date)
    }
}
