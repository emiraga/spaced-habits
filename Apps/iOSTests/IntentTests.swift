import AppIntents
import Foundation
import HabitCore
import HabitStore
import HabitUI
@testable import SpacedHabits
import Testing

/// The intents' `perform()` as Siri, Shortcuts and the widget run it in the app (DESIGN.md §6), against an
/// in-memory model standing in for the app's.
@MainActor
@Suite(.serialized)
struct IntentTests {
    private let model: AppModel
    private let gym: Habit

    init() throws {
        let defaults = try #require(UserDefaults(suiteName: "IntentTests-\(UUID().uuidString)"))
        model = try AppModel(
            store: TruthStore(container: StoreContainer.make(.inMemory)), timeZone: .current, defaults: defaults
        ) { SystemClock(calendar: $0) }
        var gym = model.newHabitDraft()
        gym.name = "Gym"
        try model.save(gym)
        self.gym = gym
    }

    private func withLiveModel<T>(_ body: () async throws -> T) async rethrows -> T {
        let previous = IntentModel.live
        IntentModel.live = model
        defer { IntentModel.live = previous }
        return try await body()
    }

    @Test func logHabitAnswersTodayFromShortcuts() async throws {
        let intent = LogHabitIntent()
        intent.habit = HabitEntity(gym)
        intent.done = true
        _ = try await withLiveModel { try await intent.perform() }
        let answer = try #require(model.truth.answers.last)
        #expect(answer.channel == .shortcut)
        #expect(answer.value == .done)
        #expect(model.todayStatus(of: gym.id) == .done)
    }

    @Test func answerHabitAnswersTodayFromTheWidget() async throws {
        let intent = AnswerHabitIntent(habitID: gym.id, day: model.today, done: false)
        _ = try await withLiveModel { try await intent.perform() }
        #expect(model.truth.answers.map(\.channel) == [.widget])
        #expect(model.todayStatus(of: gym.id) == .notDone)
        // A second tap on a stale widget is refused, not recorded over the first.
        await #expect(throws: AnswerRefusal.alreadyCovered(through: model.today)) {
            _ = try await withLiveModel {
                try await AnswerHabitIntent(habitID: gym.id, day: model.today, done: true).perform()
            }
        }
    }

    /// A button from a timeline written before due times carries no day: it answers today, as it used to.
    @Test func answerHabitWithoutADayAnswersToday() async throws {
        let intent = AnswerHabitIntent()
        intent.habitID = gym.id.uuidString
        intent.done = true
        _ = try await withLiveModel { try await intent.perform() }
        #expect(model.truth.answers.last?.covers == model.today ... model.today)
    }

    @Test func delayHabitPausesFromToday() async throws {
        let intent = DelayHabitIntent()
        intent.habit = HabitEntity(gym)
        intent.days = 3
        _ = try await withLiveModel { try await intent.perform() }
        #expect(model.resumeDay(of: gym.id) == model.today.adding(days: 3))
    }

    @Test func queryMatchesHabitsByName() async throws {
        let matches = try await withLiveModel { try await HabitQuery().entities(matching: "gy") }
        #expect(matches.map(\.id) == [gym.id])
    }
}
