import Foundation
import HabitCore
import HabitStore

/// Archiving and deleting habits (DESIGN.md §5.1, §10).
public extension AppModel {
    /// Archived habits, most recently archived first (Settings → Archived habits).
    var archivedHabits: [Habit] {
        truth.habits.filter(\.isArchived).sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
    }

    /// Hides the habit from Today, the planner and the watch; its history is kept.
    func archive(_ habitID: UUID) throws {
        guard var habit = habit(habitID) else { return }
        habit.archivedAt = clock.now()
        try save(habit)
    }

    func restore(_ habitID: UUID) throws {
        guard var habit = habit(habitID) else { return }
        habit.archivedAt = nil
        try save(habit)
    }

    /// Deletes the habit and its history on every device (`Truth.removing`).
    func delete(_ habitID: UUID) throws {
        try store.delete([.habit(habitID)], at: clock.now())
        truth = truth.removing(habits: [habitID], clusters: [])
        try refresh()
    }
}
