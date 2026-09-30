import Foundation

/// "Later" snoozes a habit (DESIGN.md §4.4): its card stays hidden for `duration` after the dismissal, then
/// comes back and a notification asks again (§8). Read from the dismissals logged in `Truth.questions`, so
/// a snooze outlives a relaunch and reaches the other device.
public enum Snooze {
    public static let duration: TimeInterval = 15 * 60

    /// When each habit's snooze ends, for habits still snoozed at `now` (the latest dismissal wins).
    public static func ends(_ questions: [Question], after now: Date) -> [UUID: Date] {
        questions.reduce(into: [:]) { ends, question in
            guard let dismissedAt = question.dismissedAt else { return }
            let end = dismissedAt.addingTimeInterval(duration)
            if end > now, end > ends[question.habitID] ?? .distantPast {
                ends[question.habitID] = end
            }
        }
    }

    /// The habits in `ends` still snoozed at `date`.
    public static func snoozed(_ ends: [UUID: Date], at date: Date) -> Set<UUID> {
        Set(ends.filter { $0.value > date }.keys)
    }
}
