import Foundation

/// Injected into every scheduler entry point so tests control time (DESIGN.md §3.1).
public protocol Clock: Sendable {
    func now() -> Date
    func today() -> DayKey
    /// The day a habit with `dueTime` asks about now (§4.2): `today()` without a due time or from it on,
    /// the day before until then.
    func askDay(dueTime: TimeOfDay?) -> DayKey
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

    public func askDay(dueTime: TimeOfDay?) -> DayKey {
        calendar.askDay(for: now(), at: dueTime)
    }
}

/// `base` moved `days` whole days ahead, for the debug "advance day" control.
/// `today()` and `askDay` shift the base's day keys, so it stays exact across DST; `now()` shifts by 24-hour days and
/// is
/// only used for timestamps.
public struct ShiftedClock: Clock {
    public let base: any Clock
    public let days: Int

    public init(base: any Clock, days: Int) {
        self.base = base
        self.days = days
    }

    public func now() -> Date {
        base.now().addingTimeInterval(TimeInterval(days) * 86400)
    }

    public func today() -> DayKey {
        base.today().adding(days: days)
    }

    public func askDay(dueTime: TimeOfDay?) -> DayKey {
        base.askDay(dueTime: dueTime).adding(days: days)
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

    public func askDay(dueTime: TimeOfDay?) -> DayKey {
        calendar.askDay(for: date, at: dueTime)
    }
}
