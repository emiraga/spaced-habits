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

#if DEBUG
    /// Debug launch arguments, shared by the iOS and watch apps (§13 M9/M10 checkpoints, UI tests, screenshots).
    public extension AppModel {
        func applyDebugLaunchArguments(_ arguments: [String]) throws {
            // UI tests start from an empty store and today's real date.
            if arguments.contains("-resetData") {
                try eraseAll()
            }
            // Simulator checks of the watch bridge (§7): something for the watch to receive.
            if arguments.contains("-sampleHabits"), truth.habits.isEmpty {
                try addSampleHabits()
            }
            // Import an export (`simulate <scenario> --json` makes one), and export into a folder as
            // Settings → Your data would (export.json, export-csv.zip).
            if let flag = arguments.firstIndex(of: "-importFixture"), flag + 1 < arguments.count {
                try importJSON(Data(contentsOf: URL(filePath: arguments[flag + 1])))
            }
            if let flag = arguments.firstIndex(of: "-exportData"), flag + 1 < arguments.count {
                let folder = URL(filePath: arguments[flag + 1])
                let export = dataExport()
                try export.json().write(to: folder.appending(path: "export.json"))
                try export.csvArchive().write(to: folder.appending(path: "export-csv.zip"))
            }
        }
    }
#endif
