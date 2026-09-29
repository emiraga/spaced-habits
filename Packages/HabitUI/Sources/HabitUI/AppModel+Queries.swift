import Foundation
import HabitCore

/// Read-only views of the model for the screens.
public extension AppModel {
    /// Unarchived habits in Today order: by group (`habitsByCluster`), then as the user ordered them
    /// (`listOrder`), then by creation.
    var activeHabits: [Habit] {
        habitsByCluster.flatMap(\.habits)
    }

    func habit(_ id: UUID) -> Habit? {
        truth.habits.first { $0.id == id }
    }

    func state(of habitID: UUID) -> SchedulerState {
        projected.states[habitID] ?? .initial(habitID: habitID)
    }

    /// The habit's projected days, newest first.
    func history(of habitID: UUID) -> [DayRecord] {
        (projected.records[habitID] ?? [:]).values.sorted { $0.day > $1.day }
    }

    /// Today's glyph in the habit list (§5.1).
    func todayStatus(of habitID: UUID) -> DayStatus {
        DayStatus.today(record: projected.records[habitID]?[today], isDue: dueHabitIDs.contains(habitID))
    }

    /// Mean value over the last `days` days that carry evidence (observed, aggregated, Health), and how
    /// many such days there were (`AdherenceFilter`). Nil without evidence: inferred days are the model's
    /// guess, not adherence. For a gated habit this is P(habit | parents) (§4.5); `includingParentMisses`
    /// adds the days its parents were not done, giving P(habit).
    func adherence(
        of habitID: UUID,
        days: Int = 30,
        includingParentMisses: Bool = false
    ) -> (mean: Double, days: Int)? {
        let since = today.adding(days: 1 - days)
        return AdherenceFilter(includingParentMisses: includingParentMisses)
            .mean(of: (projected.records[habitID] ?? [:]).values.filter { $0.day >= since })
    }

    /// The day a habit that isn't due will next be asked about (§5.1 empty state); with a due time, from that
    /// time on that day. Nil if due or archived. A habit paused on its ask day is asked on the day it resumes
    /// (the re-entry check, §4.6).
    func nextCheckIn(of habit: Habit) -> DayKey? {
        guard !habit.isArchived, !dueHabitIDs.contains(habit.id) else { return nil }
        let askDay = askDay(of: habit)
        if let resume = Pauses.resumeDay(of: habit.id, today: askDay, pauses: truth.pauses) {
            return resume
        }
        return planner.nextCheckIn(habit: habit, state: state(of: habit.id), askDay: askDay)
    }

    /// The soonest upcoming check-in across habits that aren't due; ties by name.
    func nextCheckIn() -> (habit: Habit, day: DayKey)? {
        activeHabits
            .compactMap { habit in nextCheckIn(of: habit).map { (habit: habit, day: $0) } }
            .min { ($0.day, $0.habit.name) < ($1.day, $1.habit.name) }
    }
}

public extension AppModel {
    /// The glyphs of the last `days` days, oldest first, from the habit's first day at the earliest: the
    /// watch's 7-day strip (§7). Today shows as in the habit list (due / not due unless answered).
    func recentStatuses(of habit: Habit, days: Int = 7) -> [(day: DayKey, status: DayStatus)] {
        let first = max(habit.createdDay, today.adding(days: 1 - days))
        guard first <= today else { return [] }
        return (first ... today).map { day in
            if day == today {
                return (day, todayStatus(of: habit.id))
            }
            return (day, projected.records[habit.id]?[day].map(DayStatus.init(record:)) ?? .unknown)
        }
    }
}
