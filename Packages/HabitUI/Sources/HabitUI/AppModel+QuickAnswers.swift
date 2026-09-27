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
        case .unavailable: String(localized: "That habit is paused today.", bundle: .module)
        }
    }
}

/// Answers and delays from outside the app: notifications (DESIGN.md §8), widgets and Siri (§6). They can
/// arrive long after the question was shown, and answers are latest-wins (§4.7), so each is checked
/// against current truth first: a stale one would silently override a newer answer.
public extension AppModel {
    /// Yes / No about today from a widget button or "Log Gym" in Siri or Shortcuts. The question is logged
    /// as presented now, since widgets plan without logging.
    func answerToday(_ habitID: UUID, done: Bool, channel: Channel) throws {
        let question = Question(
            habitID: habitID, covers: today ... today, shape: .singleDay, createdAt: clock.now(),
            presentedAt: clock.now()
        )
        try checkAnswerable(question)
        try log(question)
        try record(question, done ? .done : .notDone, delayReason: .manual, channel: channel)
    }

    /// Pauses a habit for `days` days from today ("Delay Gym 3 days" in Shortcuts).
    func delay(_ habitID: UUID, days: Int) throws {
        guard let habit = habit(habitID), !habit.isArchived else { throw AnswerRefusal.habitGone(habitID) }
        try pause(habitID, from: today, through: today.adding(days: days - 1), reason: .manual)
    }

    /// Throws `AnswerRefusal` unless `question` can still be answered with Yes / No.
    internal func checkAnswerable(_ question: Question) throws {
        try question.validate()
        guard question.shape == .singleDay else { throw AnswerRefusal.notSingleDay }
        guard let habit = habit(question.habitID), !habit.isArchived else {
            throw AnswerRefusal.habitGone(question.habitID)
        }
        // Before the coverage check: a paused day counts as covered, but "paused" says why.
        let day = question.covers.lowerBound
        if try Pauses.unavailable(on: day, habits: truth.habits, pauses: truth.pauses)[habit.id] != nil {
            throw AnswerRefusal.unavailable(habit.id, day)
        }
        if let covered = state(of: habit.id).lastCoveredDay, covered >= question.covers.lowerBound {
            throw AnswerRefusal.alreadyCovered(through: covered)
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
