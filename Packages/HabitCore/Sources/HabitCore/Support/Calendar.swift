import Foundation

/// The single place that maps instants to habit days (DESIGN.md §3.1). Nothing else may compute day
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
