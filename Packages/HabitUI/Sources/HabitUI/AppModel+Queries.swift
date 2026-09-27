import Foundation
import HabitCore

/// Read-only views of the model for the screens.
public extension AppModel {
    /// Unarchived habits in creation order.
    var activeHabits: [Habit] {
        truth.habits.filter { !$0.isArchived }.sorted { ($0.createdAt, $0.name) < ($1.createdAt, $1.name) }
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
    /// many such days there were. Nil without evidence: inferred days are the model's guess, not adherence.
    func adherence(of habitID: UUID, days: Int = 30) -> (mean: Double, days: Int)? {
        let since = today.adding(days: 1 - days)
        let evidence = (projected.records[habitID] ?? [:]).values.filter {
            $0.day >= since && $0.source.feedsModel && !$0.conditionalDenominatorExcluded
        }
        guard !evidence.isEmpty else { return nil }
        return (evidence.map(\.value).reduce(0, +) / Double(evidence.count), evidence.count)
    }

    /// When a habit that isn't due today will next be asked (§5.1 empty state). Nil if due or archived.
    /// A paused habit is asked on the day it resumes (the re-entry check, §4.6).
    func nextCheckIn(of habit: Habit) -> DayKey? {
        guard !habit.isArchived, !dueHabitIDs.contains(habit.id) else { return nil }
        if let resume = resumeDay(of: habit.id) {
            return resume
        }
        return planner.nextCheckIn(habit: habit, state: state(of: habit.id), today: today)
    }

    /// The soonest upcoming check-in across habits that aren't due; ties by name.
    func nextCheckIn() -> (habit: Habit, day: DayKey)? {
        activeHabits
            .compactMap { habit in nextCheckIn(of: habit).map { (habit: habit, day: $0) } }
            .min { ($0.day, $0.habit.name) < ($1.day, $1.habit.name) }
    }
}
