import HabitCore
import SwiftUI

/// A clock and "18:00": a habit's due time in the phone's and the watch's habit lists (DESIGN.md §5.1, §7).
public struct DueTimeBadge: View {
    let time: TimeOfDay

    public init(_ time: TimeOfDay) {
        self.time = time
    }

    public var body: some View {
        Label(DayFormat.time(time), systemImage: "clock")
            .labelStyle(.titleAndIcon)
            .imageScale(.small)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityLabel(DayFormat.dueFrom(time))
    }
}

public extension DayFormat {
    /// "from 18:00": the due time for VoiceOver in habit lists.
    static func dueFrom(_ time: TimeOfDay) -> String {
        String(localized: "from \(DayFormat.time(time))", bundle: .module)
    }
}
