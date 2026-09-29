import AppIntents
import Foundation
import HabitCore
import HabitUI

/// A habit as Siri and Shortcuts see it (DESIGN.md §6).
struct HabitEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Habit"
    static let defaultQuery = HabitQuery()

    let id: UUID
    let name: String
    let emoji: String?

    init(_ habit: Habit) {
        id = habit.id
        name = habit.name
        emoji = habit.emoji
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: emoji.map { "\($0)" })
    }
}

/// Active habits, matched by name.
struct HabitQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [HabitEntity] {
        try IntentModel.open().activeHabits.filter { identifiers.contains($0.id) }.map(HabitEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [HabitEntity] {
        try IntentModel.open().activeHabits
            .filter { $0.name.localizedStandardContains(string) }
            .map(HabitEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [HabitEntity] {
        try IntentModel.open().activeHabits.map(HabitEntity.init)
    }
}

/// "Log Gym in Spaced Habits": Yes (or No) for the day its card asks about: yesterday before its due time,
/// else today (§4.2, §6).
struct LogHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Habit"
    static let description = IntentDescription(
        "Records whether you did a habit today, or yesterday if it's before the habit's due time."
    )

    @Parameter(title: "Habit") var habit: HabitEntity
    @Parameter(title: "Done", default: true) var done: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$habit) as done: \(\.$done)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try IntentModel.open()
        let day = try model.log(habit.id, done: done, channel: .shortcut)
        let dialog: IntentDialog = switch (day == model.today, done) {
        case (true, true): "Logged \(habit.name) for today."
        case (true, false): "Logged \(habit.name) as not done today."
        case (false, true): "Logged \(habit.name) for yesterday."
        case (false, false): "Logged \(habit.name) as not done yesterday."
        }
        return .result(dialog: dialog)
    }
}

/// "Delay Gym 3 days": pauses a habit from the day it asks about, like "Delay…" in the app (§6).
struct DelayHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Delay Habit"
    static let description =
        IntentDescription("Pauses a habit, like Delay… in the app. Its progress is frozen, not lost.")

    @Parameter(title: "Habit") var habit: HabitEntity
    @Parameter(title: "Days", default: 1, inclusiveRange: (1, 60)) var days: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Delay \(\.$habit) for \(\.$days) days")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try IntentModel.open()
        let resume = try DayFormat.short(model.delay(habit.id, days: days), today: model.today)
        return .result(dialog: "\(habit.name) is paused. It resumes \(resume).")
    }
}

/// Opens the Today screen.
struct ReviewHabitsIntent: AppIntent {
    static let title: LocalizedStringResource = "Review Habits"
    static let description = IntentDescription("Opens today's check-in.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct SpacedHabitsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogHabitIntent(),
            phrases: [
                "Log \(\.$habit) in \(.applicationName)",
                "Mark \(\.$habit) done in \(.applicationName)",
            ],
            shortTitle: "Log Habit",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: DelayHabitIntent(),
            phrases: ["Delay \(\.$habit) in \(.applicationName)"],
            shortTitle: "Delay Habit",
            systemImageName: "pause.circle"
        )
        AppShortcut(
            intent: ReviewHabitsIntent(),
            phrases: ["Review habits in \(.applicationName)", "Check in with \(.applicationName)"],
            shortTitle: "Review Habits",
            systemImageName: "list.bullet"
        )
    }
}
