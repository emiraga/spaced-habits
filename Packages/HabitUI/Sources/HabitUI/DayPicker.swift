import HabitCore
import SwiftUI

/// A `DatePicker` over `DayKey`s. Pickers work in `Date`, so this one runs in UTC over noon-UTC dates:
/// the picked civil date maps back to the same `DayKey` in every time zone.
public struct DayPicker: View {
    let title: String
    @Binding var day: DayKey
    let range: ClosedRange<DayKey>

    public init(_ title: String, day: Binding<DayKey>, in range: ClosedRange<DayKey>) {
        self.title = title
        _day = day
        self.range = range
    }

    public var body: some View {
        DatePicker(
            title,
            selection: Binding(
                get: { DayFormat.noonUTC(day) },
                set: { day = DayFormat.day(fromNoonUTC: $0) }
            ),
            in: DayFormat.noonUTC(range.lowerBound) ... DayFormat.noonUTC(range.upperBound),
            displayedComponents: .date
        )
        .environment(\.timeZone, .gmt)
        .environment(\.calendar, Self.calendar)
    }

    /// The user's calendar (it may not be Gregorian), in UTC.
    private static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = .gmt
        return calendar
    }
}
