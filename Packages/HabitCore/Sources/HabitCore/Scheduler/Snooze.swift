import Foundation

/// "Later" snoozes a habit (DESIGN.md §4.4): its card stays hidden for `duration` after the dismissal, then
/// comes back; after a notification's Later, a notification asks again then (§8). Read from the dismissals
/// logged in `Truth.questions`, so a snooze outlives a relaunch and reaches the other device.
public enum Snooze {
    public static let duration: TimeInterval = 15 * 60

    public struct End: Sendable, Hashable {
        public let date: Date
        /// The snooze came from a notification, so a notification asks again at `date`.
        public let notifies: Bool
    }

    /// When each habit's snooze ends, for habits still snoozed at `now` (the latest dismissal wins).
    public static func ends(_ questions: [Question], after now: Date) -> [UUID: End] {
        questions.reduce(into: [:]) { ends, question in
            guard let dismissedAt = question.dismissedAt else { return }
            let end = dismissedAt.addingTimeInterval(duration)
            if end > now, end > ends[question.habitID]?.date ?? .distantPast {
                ends[question.habitID] = End(date: end, notifies: question.dismissedVia == .notification)
            }
        }
    }

    /// The habits in `ends` still snoozed at `date`.
    public static func snoozed(_ ends: [UUID: End], at date: Date) -> Set<UUID> {
        Set(ends.filter { $0.value.date > date }.keys)
    }
}
