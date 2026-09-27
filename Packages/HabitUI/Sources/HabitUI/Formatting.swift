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
    /// "Today", "Yesterday", else e.g. "Mon 21 Sep".
    public static func short(_ day: DayKey, today: DayKey) -> String {
        switch day.days(to: today) {
        case 0: "Today"
        case 1: "Yesterday"
        default: noonUTC(day).formatted(style)
        }
    }

    /// "Asking daily" / "Asking every ~9 days" (§5.1 habit detail).
    public static func askInterval(_ days: Int) -> String {
        days <= 1 ? "Asking daily" : "Asking every ~\(days) days"
    }

    public static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    /// Noon UTC on the day's civil date, formatted in UTC, so the label is the same in every time zone.
    private static func noonUTC(_ day: DayKey) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day.dayNumber) * 86400 + 12 * 3600)
    }

    private static let style = Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated).day().month(.abbreviated)
}
