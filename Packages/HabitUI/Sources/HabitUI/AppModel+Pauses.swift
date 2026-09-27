import Foundation
import HabitCore

/// Pauses and vacation mode (DESIGN.md §4.6, §5.1 screens 4–5). Delays from a card are `AppModel.delay`.
public extension AppModel {
    // MARK: Pauses

    /// Pauses one habit over `start...end`. `start` may be in the past (backdated) or the future.
    func pause(_ habitID: UUID, from start: DayKey, through end: DayKey, reason: PauseReason) throws {
        try save(PauseEvent(habitIDs: [habitID], start: start, end: end, reason: reason, createdAt: clock.now()))
    }

    /// Stores a new or edited pause (extend: a later `end`).
    func save(_ pause: PauseEvent) throws {
        try store.save(pause, at: clock.now())
        if let index = truth.pauses.firstIndex(where: { $0.id == pause.id }) {
            truth.pauses[index] = pause
        } else {
            truth.pauses.append(pause)
        }
        try refresh()
    }

    /// "End now": today is active again (a pause that hasn't started yet is cancelled).
    func end(_ pause: PauseEvent) throws {
        try save(pause.endedEarly(today: today, at: clock.now()))
    }

    /// The first day the habit is asked again, if it is paused today.
    func resumeDay(of habitID: UUID) -> DayKey? {
        Pauses.resumeDay(of: habitID, today: today, pauses: truth.pauses)
    }

    /// The habit's running and scheduled pauses, soonest first.
    func pauses(of habitID: UUID) -> [PauseEvent] {
        Pauses.current(of: habitID, today: today, pauses: truth.pauses)
    }

    // MARK: Vacation

    /// The running vacation or, failing that, the next scheduled one.
    var currentVacation: PauseEvent? {
        Vacation.current(pauses: truth.pauses, today: today)
    }

    /// Starts or schedules a vacation pausing every active habit not in `plan.kept`. With `rememberChoices`,
    /// each habit's `vacationBehavior` is updated to match, so the next vacation starts from this checklist.
    func startVacation(_ plan: Vacation.Plan, rememberChoices: Bool) throws {
        let vacation = try Vacation.event(for: plan, habits: truth.habits, createdAt: clock.now())
        if rememberChoices {
            try save(Vacation.rememberingChoices(habits: truth.habits, kept: plan.kept))
        }
        try save(vacation)
    }

    /// The vacation sheet's starting point: today for a week, kept habits from `vacationBehavior`. From the
    /// silence nudge (§4.6), retroactive instead: the day after `lastActiveDay` (at most 30 days back, the
    /// sheet's limit) through today.
    func vacationDraft(after lastActiveDay: DayKey? = nil) -> Vacation.Plan {
        let kept = Vacation.defaultKept(truth.habits)
        guard let lastActiveDay else {
            return Vacation.Plan(start: today, end: today.adding(days: 6), kept: kept)
        }
        let start = min(today, max(lastActiveDay.adding(days: 1), today.adding(days: -30)))
        return Vacation.Plan(start: start, end: today, kept: kept)
    }
}
