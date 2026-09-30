import Foundation
import HabitCore

/// Why an answer given outside the app (notification, widget, Siri) was not recorded.
public enum AnswerRefusal: LocalizedError, Equatable {
    /// The habit was deleted or archived since the question was shown.
    case habitGone(UUID)
    /// The days it asked about were answered (or paused) since, e.g. in the app or on the watch.
    case alreadyCovered(through: DayKey)
    /// Only single-day questions have Yes / No outside the app.
    case notSingleDay
    /// The habit is paused, or blocked by a paused parent, on the day asked about.
    case unavailable(UUID, DayKey)

    public var errorDescription: String? {
        switch self {
        case .habitGone: String(localized: "That habit no longer exists.", bundle: .module)
        case let .alreadyCovered(day): String(
                localized: "Already answered through \(day.description).",
                bundle: .module
            )
        case .notSingleDay: String(localized: "This question needs the app to answer.", bundle: .module)
        case .unavailable: String(localized: "That habit is paused on that day.", bundle: .module)
        }
    }
}

/// Answers and delays from outside the app: notifications (DESIGN.md §8), widgets and Siri (§6). They can
/// arrive long after the question was shown, and answers are latest-wins (§4.7), so each is checked
/// against current truth first: a stale one would silently override a newer answer.
public extension AppModel {
    /// "Log Gym" in Siri or Shortcuts: Yes / No about the habit's ask day, like its card (§4.2), so before the
    /// due time it answers yesterday. Returns the day answered.
    @discardableResult
    func log(_ habitID: UUID, done: Bool, channel: Channel) throws -> DayKey {
        guard let habit = habit(habitID), !habit.isArchived else { throw AnswerRefusal.habitGone(habitID) }
        let day = askDay(of: habit)
        try answer(habitID, day: day, done: done, channel: channel)
        return day
    }

    /// Yes / No about `day` from a widget button (its question's ask day, §4.2). The question is logged as
    /// presented now, since widgets plan without logging.
    func answer(_ habitID: UUID, day: DayKey, done: Bool, channel: Channel) throws {
        let question = Question(
            habitID: habitID, covers: day ... day, shape: .singleDay, createdAt: clock.now(),
            presentedAt: clock.now()
        )
        try checkAnswerable(question)
        try log(question)
        try record(question, done ? .done : .notDone, delayReason: .manual, channel: channel)
    }

    /// "Done today" on habit detail or a habit's long-press menu (DESIGN.md §5.1): Yes for today even when the
    /// habit isn't due or its due time hasn't come, so a habit finished early can be logged. Replaces a "No"
    /// for today (answers are latest-wins, §4.7); Undo on Today takes it back.
    func logDoneToday(_ habitID: UUID) throws {
        try checkAvailable(habitID, on: today)
        guard canLogDoneToday(habitID) else { throw AnswerRefusal.alreadyCovered(through: today) }
        let question = Question(
            habitID: habitID, covers: today ... today, shape: .singleDay, createdAt: clock.now(),
            presentedAt: clock.now()
        )
        try log(question)
        lastAnswered = try record(question, .done, delayReason: .manual, channel: channel)
    }

    /// Whether "Done today" is offered: the habit is active and available today, and today isn't done yet.
    func canLogDoneToday(_ habitID: UUID) -> Bool {
        guard let habit = habit(habitID), !habit.isArchived else { return false }
        switch todayStatus(of: habitID) {
        case .done, .health, .paused, .blocked: return false
        case .notDone, .aggregated, .inferred, .unknown, .due, .notDue: return true
        }
    }

    /// Pauses a habit for `days` days from its ask day, like a card delay ("Delay Gym 3 days" in Shortcuts).
    /// Returns the day it resumes.
    @discardableResult
    func delay(_ habitID: UUID, days: Int) throws -> DayKey {
        guard let habit = habit(habitID), !habit.isArchived else { throw AnswerRefusal.habitGone(habitID) }
        let start = askDay(of: habit)
        try pause(habitID, from: start, through: start.adding(days: days - 1), reason: .manual)
        return start.adding(days: days)
    }

    /// Throws `AnswerRefusal` unless `question` can still be answered with Yes / No.
    internal func checkAnswerable(_ question: Question) throws {
        try question.validate()
        guard question.shape == .singleDay else { throw AnswerRefusal.notSingleDay }
        // Before the coverage check: a paused day counts as covered, but "paused" says why.
        try checkAvailable(question.habitID, on: question.covers.lowerBound)
        if let covered = state(of: question.habitID).lastCoveredDay, covered >= question.covers.lowerBound {
            throw AnswerRefusal.alreadyCovered(through: covered)
        }
    }

    /// Throws `AnswerRefusal` if the habit is archived or deleted, or paused or blocked on `day`.
    internal func checkAvailable(_ habitID: UUID, on day: DayKey) throws {
        guard let habit = habit(habitID), !habit.isArchived else { throw AnswerRefusal.habitGone(habitID) }
        if try Pauses.unavailable(on: day, habits: truth.habits, pauses: truth.pauses)[habit.id] != nil {
            throw AnswerRefusal.unavailable(habit.id, day)
        }
    }

    /// Saves a question unless one with its ID is already logged with the same content; a dismissal
    /// updates the logged entry.
    internal func log(_ question: Question) throws {
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
