import Foundation
import HabitCore

/// Why an answer from a notification was not recorded.
public enum NotificationAnswerError: LocalizedError, Equatable {
    /// The habit was deleted or archived since the notification was planned.
    case habitGone(UUID)
    /// The days it asked about were answered (or paused) since, e.g. in the app or on the watch.
    case alreadyCovered(through: DayKey)
    /// Only single-day questions have Yes / No actions.
    case notSingleDay

    public var errorDescription: String? {
        switch self {
        case .habitGone: "That habit no longer exists."
        case let .alreadyCovered(day): "Already answered through \(day)."
        case .notSingleDay: "This question needs the app to answer."
        }
    }
}

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
    /// logged as presented then. Throws `NotificationAnswerError` if the answer no longer fits: the
    /// notification may be answered long after it was planned, and a stale answer would override a
    /// newer one (the latest answer wins, §4.7).
    func respond(to question: Question, deliveredAt: Date, with action: NotificationAction) throws {
        try question.validate()
        guard question.shape == .singleDay else { throw NotificationAnswerError.notSingleDay }
        guard let habit = habit(question.habitID), !habit.isArchived else {
            throw NotificationAnswerError.habitGone(question.habitID)
        }
        if let covered = state(of: habit.id).lastCoveredDay, covered >= question.covers.lowerBound {
            throw NotificationAnswerError.alreadyCovered(through: covered)
        }
        var presented = question
        presented.presentedAt = deliveredAt
        switch action {
        case .done, .notDone:
            try log(presented)
            try record(presented, action == .done ? .done : .notDone, delayReason: .manual, channel: .notification)
        case .later:
            presented.dismissedAt = clock.now()
            try log(presented)
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

    /// Saves a question unless one with its ID is already logged with the same content; a dismissal
    /// updates the logged entry.
    private func log(_ question: Question) throws {
        let index = truth.questions.firstIndex { $0.id == question.id }
        if let index, truth.questions[index].dismissedAt != nil || question.dismissedAt == nil {
            return
        }
        try store.save(question, at: clock.now())
        if let index {
            truth.questions[index] = question
        } else {
            truth.questions.append(question)
        }
    }
}
