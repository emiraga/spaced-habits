import Foundation
import HabitCore

/// Everything `NotificationPlanner` needs, taken on the main actor so planning can run off it.
public struct NotificationSnapshot: Sendable {
    let truth: Truth
    let calendar: DayCalendar
    let now: Date
    let dayOffset: Int

    /// The notifications to schedule, in fire order. Slow for large histories (one projection per
    /// planned day), so call it off the main actor.
    public func contents() throws -> [NotificationContent] {
        let shift = -TimeInterval(dayOffset) * 86400
        return try NotificationPlanner.plan(truth: truth, calendar: calendar, now: now).map {
            NotificationContent($0, habits: truth.habits, shift: shift)
        }
    }
}

/// Notifications (DESIGN.md §8): what to schedule, and answers and dismissals coming back from them.
public extension AppModel {
    func notificationSnapshot() throws -> NotificationSnapshot {
        try NotificationSnapshot(
            truth: truth,
            calendar: DayCalendar(timeZone: timeZone, dayStartHour: truth.settings.dayStartHour),
            now: clock.now(),
            dayOffset: dayOffset
        )
    }

    /// Yes / No / Later on a single-day question notification delivered at `deliveredAt`. The question is
    /// logged as presented then; Later snoozes it for `Snooze.duration`. Throws `AnswerRefusal` if the answer no longer
    /// fits.
    func respond(to question: Question, deliveredAt: Date, with action: NotificationAction) throws {
        try checkAnswerable(question)
        var presented = question
        presented.presentedAt = deliveredAt
        switch action {
        case .done, .notDone:
            try log(presented)
            try record(presented, action == .done ? .done : .notDone, delayReason: .manual, channel: .notification)
        case .later:
            // Snoozes the habit (§4.4): its card hides, and a notification asks again when the snooze ends.
            presented.dismissedAt = clock.now()
            presented.dismissedVia = .notification
            try log(presented)
            try refresh()
        }
    }

    /// Logs questions from delivered notifications to `Truth.questions` (§4.4), once each.
    func logDelivered(_ delivered: [(question: Question, deliveredAt: Date)]) throws {
        for (question, deliveredAt) in delivered {
            var presented = question
            presented.presentedAt = deliveredAt
            try log(presented)
        }
    }
}
