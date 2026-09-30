import Foundation

/// The single place that maps instants to habit days (DESIGN.md §3.1, and ask days, §4.2). Nothing else may compute day
/// boundaries.
///
/// A habit day starts at `dayStartHour` local time (default 04:00), so an answer given at 01:30
/// counts for the previous calendar day.
public struct DayCalendar: Sendable, Equatable {
    public static let defaultDayStartHour = 4

    public let timeZone: TimeZone
    /// 0...23. Instants before this local hour belong to the previous day.
    public let dayStartHour: Int

    public enum ValidationError: Error, Equatable {
        case dayStartHourOutOfRange(Int)
    }

    public init(timeZone: TimeZone, dayStartHour: Int = DayCalendar.defaultDayStartHour) throws {
        guard (0 ... 23).contains(dayStartHour) else {
            throw ValidationError.dayStartHourOutOfRange(dayStartHour)
        }
        self.timeZone = timeZone
        self.dayStartHour = dayStartHour
    }

    public func dayKey(for date: Date) -> DayKey {
        // Read local wall-clock components rather than subtracting hours from the instant, so a DST
        // transition between midnight and `dayStartHour` cannot shift the result.
        let parts = gregorian.dateComponents([.year, .month, .day, .hour], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day, let hour = parts.hour,
              let key = DayKey(year: year, month: month, day: day)
        else {
            preconditionFailure("Gregorian calendar returned incomplete components for \(date)")
        }
        return hour < dayStartHour ? key.adding(days: -1) : key
    }

    /// The day a habit with `dueTime` asks about at `date` (§4.2): the habit day of `date` from the due time
    /// on, the day before until then; always the habit day without a due time. A due time before
    /// `dayStartHour` falls at the end of its habit day (§3.1).
    ///
    /// Compares wall-clock times, so a due time skipped by a DST jump passes at the first time after it; once
    /// its first instant has passed, a due time repeated by a DST fall-back stays passed.
    public func askDay(for date: Date, at dueTime: TimeOfDay?) -> DayKey {
        let today = dayKey(for: date)
        guard let dueTime else { return today }
        let parts = gregorian.dateComponents([.hour, .minute], from: date)
        guard let hour = parts.hour, let minute = parts.minute else {
            preconditionFailure("Gregorian calendar returned incomplete components for \(date)")
        }
        let wallClockPassed = minutesIntoDay(hour: hour, minute: minute)
            >= minutesIntoDay(hour: dueTime.hour, minute: dueTime.minute)
        let passed = wallClockPassed || date >= self.date(dueTime, onHabitDay: today)
        return passed ? today : today.adding(days: -1)
    }

    /// The instant at `time` within habit day `day`: a time before `dayStartHour` is on the next civil date
    /// (§3.1). A time skipped by a DST jump resolves as in `date(_:at:)`.
    public func date(_ time: TimeOfDay, onHabitDay day: DayKey) -> Date {
        date(time.hour < dayStartHour ? day.adding(days: 1) : day, at: time)
    }

    /// The instants of `times` on every habit day, after `start` and before `end`, sorted and distinct: when
    /// ask days change (§4.2), for widget timelines and replanning an open Today screen.
    public func dueDates(_ times: [TimeOfDay], after start: Date, before end: Date) -> [Date] {
        guard start < end else { return [] }
        let days = dayKey(for: start) ... dayKey(for: end)
        return Set(days.flatMap { day in times.map { date($0, onHabitDay: day) } })
            .filter { $0 > start && $0 < end }
            .sorted()
    }

    /// The local wall-clock hour of `date` (quiet hours, §8).
    public func hour(of date: Date) -> Int {
        gregorian.component(.hour, from: date)
    }

    /// Minutes since the start of the habit day at a local wall-clock time.
    private func minutesIntoDay(hour: Int, minute: Int) -> Int {
        (hour - dayStartHour + 24) % 24 * 60 + minute
    }

    /// The instant at local wall-clock `time` on the civil date `date` (not a habit day: 01:00 on the 28th
    /// belongs to habit day 27 when the day starts at 04:00). A time skipped by a DST jump resolves to the
    /// same offset after the jump (02:30 → 03:30).
    public func date(_ date: DayKey, at time: TimeOfDay) -> Date {
        let civil = date.components
        let parts = DateComponents(
            year: civil.year, month: civil.month, day: civil.day, hour: time.hour, minute: time.minute
        )
        guard let instant = gregorian.date(from: parts) else {
            preconditionFailure("Gregorian calendar can't build \(date) \(time.hour):\(time.minute)")
        }
        return instant
    }

    private var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
