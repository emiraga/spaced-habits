import Foundation
import HabitCore
import SwiftUI

/// Habit colors offered by the editor, as `Habit.colorHex` values.
public enum HabitPalette {
    public static let colors = [
        "#3366CC", "#DC3912", "#FF9900", "#109618", "#990099", "#0099C6", "#DD4477", "#66AA00",
    ]
}

public extension Color {
    /// `#RRGGBB`; anything else is gray, so a bad value from sync or import is visible, not fatal.
    init(hex: String) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, let rgb = UInt32(digits, radix: 16) else {
            self = .gray
            return
        }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

/// Display strings for days and intervals. Presentation only: day boundaries come from `DayCalendar`.
public enum DayFormat {
    /// "Today", "Yesterday", "Tomorrow", else e.g. "Mon 21 Sep".
    public static func short(_ day: DayKey, today: DayKey) -> String {
        switch day.days(to: today) {
        case 0: String(localized: "Today", bundle: .module)
        case 1: String(localized: "Yesterday", bundle: .module)
        case -1: String(localized: "Tomorrow", bundle: .module)
        default: noonUTC(day).formatted(style)
        }
    }

    /// "Tomorrow", or "Today from 18:00" for a habit with a due time (§5.1 "Next check-in").
    public static func checkIn(_ day: DayKey, dueTime: TimeOfDay?, today: DayKey) -> String {
        guard let dueTime else { return short(day, today: today) }
        return String(localized: "\(short(day, today: today)) from \(time(dueTime))", bundle: .module)
    }

    /// "18:00" or "6:00 PM", as the user's locale writes times.
    public static func time(_ time: TimeOfDay) -> String {
        time.pickerDate.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: .gmt))
    }

    /// "Asking daily" / "Asking every ~9 days" (§5.1 habit detail).
    public static func askInterval(_ days: Int) -> String {
        days <= 1
            ? String(localized: "Asking daily", bundle: .module)
            : String(localized: "Asking every ~\(days) days", bundle: .module)
    }

    /// "1 day" / "3 days": pause lengths on the phone and the watch.
    public static func days(_ days: Int) -> String {
        days == 1 ? String(localized: "1 day", bundle: .module) : String(localized: "\(days) days", bundle: .module)
    }

    /// "Once a week", "3 days a week", "Every day": a habit's target (§5.1), rounded to days per week.
    public static func target(_ targetAdherence: Double) -> String {
        switch Habit.daysPerWeek(targetAdherence: targetAdherence) {
        case 1: String(localized: "Once a week", bundle: .module)
        case 7: String(localized: "Every day", bundle: .module)
        case let days: String(localized: "\(days) days a week", bundle: .module)
        }
    }

    /// "S" for Sunday: the watch's 7-day strip (§7).
    public static func weekdayInitial(_ day: DayKey) -> String {
        noonUTC(day).formatted(Date.FormatStyle(timeZone: .gmt).weekday(.narrow))
    }

    public static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    /// "Mon 21 Sep – Wed 23 Sep", or one day.
    public static func range(_ start: DayKey, _ end: DayKey, today: DayKey) -> String {
        start == end
            ? short(start, today: today)
            : String(localized: "\(short(start, today: today)) – \(short(end, today: today))", bundle: .module)
    }

    /// Noon UTC on the day's civil date, formatted in UTC, so the label is the same in every time zone.
    /// `DayPicker` round-trips through it: a picked civil date is not an instant, so this is not a day
    /// boundary computation (§3.1).
    static func noonUTC(_ day: DayKey) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day.dayNumber) * 86400 + 12 * 3600)
    }

    /// The civil date a UTC `DatePicker` selected.
    static func day(fromNoonUTC date: Date) -> DayKey {
        DayKey(dayNumber: Int((date.timeIntervalSince1970 / 86400).rounded(.down)))
    }

    private static let style = Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated).day().month(.abbreviated)
}

public extension TimeOfDay {
    /// The time on 1970-01-01 UTC, for a `DatePicker` in the UTC time zone and for formatting: a wall-clock
    /// time, not an instant.
    var pickerDate: Date {
        Date(timeIntervalSince1970: TimeInterval(hour * 3600 + minute * 60))
    }

    /// The wall-clock time a UTC `DatePicker` selected.
    init(pickerDate date: Date) {
        self.init(minutesSinceMidnight: Int((date.timeIntervalSince1970 / 60).rounded(.down)))
    }
}

public extension PauseReason {
    /// The reasons the pause sheet offers; `.other` takes free text.
    static let choices: [PauseReason] = [.manual, .sick, .other("")]

    var label: String {
        switch self {
        case .manual: String(localized: "Delay", bundle: .module)
        case .vacation: String(localized: "Vacation", bundle: .module)
        case .sick: String(localized: "Sick", bundle: .module)
        case let .other(text): text.isEmpty ? String(localized: "Other", bundle: .module) : text
        }
    }
}
