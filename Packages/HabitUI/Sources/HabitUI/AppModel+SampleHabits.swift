import Foundation
import HabitCore

/// Debug seed data (Settings → Debug → Add sample habits; the UI tests and the watch bridge checks use it).
public extension AppModel {
    private struct SampleHabit {
        let name: String
        let emoji: String
        let importance: Importance
    }

    private static let sampleHabits = [
        SampleHabit(name: "Gym", emoji: "🏋️", importance: .high),
        SampleHabit(name: "Read", emoji: "📚", importance: .normal),
        SampleHabit(name: "Meditate", emoji: "🧘", importance: .low),
    ]

    /// Three sample habits, created today.
    func addSampleHabits() throws {
        for sample in Self.sampleHabits {
            var habit = newHabitDraft()
            habit.name = sample.name
            habit.emoji = sample.emoji
            habit.importance = sample.importance
            try save(habit)
        }
    }
}
