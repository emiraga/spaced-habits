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
    static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = .gmt
        return calendar
    }
}

/// A `DatePicker` over a wall-clock `TimeOfDay` (notification times, habit due times). Like `DayPicker` it runs
/// in UTC, over `TimeOfDay.pickerDate`: a time of day, not an instant.
public struct TimePicker: View {
    let title: LocalizedStringKey
    @Binding var time: TimeOfDay

    public init(_ title: LocalizedStringKey, time: Binding<TimeOfDay>) {
        self.title = title
        _time = time
    }

    public var body: some View {
        DatePicker(
            title,
            selection: Binding(get: { time.pickerDate }, set: { time = TimeOfDay(pickerDate: $0) }),
            displayedComponents: .hourAndMinute
        )
        .environment(\.timeZone, .gmt)
        .environment(\.calendar, DayPicker.calendar)
    }
}
