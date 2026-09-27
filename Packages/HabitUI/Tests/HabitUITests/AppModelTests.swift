import Foundation
import HabitCore
import HabitStore
@testable import HabitUI
import Testing

/// 2026-09-27, noon UTC.
private let start = DayKey(dayNumber: 20723)
private let noon = Date(timeIntervalSince1970: TimeInterval(start.dayNumber) * 86400 + 12 * 3600)

@MainActor
private struct Harness {
    let store: TruthStore
    let defaults: UserDefaults

    init(location: StoreLocation = .inMemory) throws {
        store = try TruthStore(container: StoreContainer.make(location))
        defaults = try #require(UserDefaults(suiteName: "AppModelTests-\(UUID().uuidString)"))
    }

    func model() throws -> AppModel {
        try AppModel(store: store, timeZone: .gmt, defaults: defaults) { FixedClock(date: noon, calendar: $0) }
    }
}

@MainActor
private func addHabit(_ model: AppModel, _ name: String) throws -> Habit {
    var habit = model.newHabitDraft()
    habit.name = name
    try model.save(habit)
    return habit
}

/// "Yes" to every day the question asks about.
private func allDone(_ question: Question) -> AnswerValue {
    switch question.shape {
    case .singleDay: .done
    case let .perDay(days): .perDay(Dictionary(uniqueKeysWithValues: days.map { ($0, true) }))
    case let .count(total): .count(done: total, total: total)
    }
}

@MainActor
struct AppModelTests {
    /// The §13 M2 checkpoint, driven through the debug "advance day" control: "yes" every time is asked
    /// less by day 7 (days 1–5, then a per-day card on day 8 covering 6–8); "no" every time is asked
    /// daily; a four-day gap produces a `count` card.
    @Test func checkpointEightDays() throws {
        let model = try Harness().model()
        let gym = try addHabit(model, "Gym")
        let read = try addHabit(model, "Read")
        let meditate = try addHabit(model, "Meditate")
        var gymCards: [Int: Question] = [:]
        var readDays: [Int] = []
        var meditateCards: [Int: Question] = [:]

        for day in 1 ... 8 {
            if day > 1 {
                try model.advanceDay()
            }
            #expect(model.dayOffset == day - 1)
            for question in model.questions {
                switch question.habitID {
                case gym.id:
                    gymCards[day] = question
                    try model.answer(question, with: allDone(question))
                case read.id:
                    readDays.append(day)
                    try model.answer(question, with: .notDone)
                case meditate.id:
                    meditateCards[day] = question
                    // Answered on day 1, then not opened for days 2–4.
                    if day == 1 || day >= 5 {
                        try model.answer(question, with: .done)
                    } else {
                        try model.later(question)
                    }
                default:
                    Issue.record("Unexpected habit \(question.habitID)")
                }
            }
        }

        #expect(gymCards.keys.sorted() == [1, 2, 3, 4, 5, 8])
        let dayEight = try #require(gymCards[8])
        #expect(dayEight.covers == start.adding(days: 5) ... start.adding(days: 7))
        #expect(dayEight.shape == .perDay(days: Array(dayEight.covers)))
        #expect(readDays == Array(1 ... 8))
        #expect(meditateCards[5]?.shape == .count(total: 4))
        #expect(meditateCards[5]?.covers == start.adding(days: 1) ... start.adding(days: 4))
    }

    @Test func laterHidesAHabitUntilTheNextSessionAndIsLogged() throws {
        let model = try Harness().model()
        let gym = try addHabit(model, "Gym")
        let question = try #require(model.questions.first)
        try model.later(question)
        #expect(model.questions.isEmpty)
        #expect(model.dueHabitIDs == [gym.id])
        #expect(model.todayStatus(of: gym.id) == .due)
        #expect(model.truth.questions.first { $0.id == question.id }?.dismissedAt == noon)
        try model.startSession()
        #expect(model.questions.map(\.habitID) == [gym.id])
        #expect(model.questions.first?.id != question.id)
    }

    @Test func shownQuestionKeepsItsIDAndIsLoggedOnce() throws {
        let model = try Harness().model()
        _ = try addHabit(model, "Gym")
        let first = try #require(model.questions.first)
        _ = try addHabit(model, "Read")
        try model.startSession()
        #expect(model.questions.contains(first))
        #expect(model.truth.questions.count { $0.habitID == first.habitID } == 1)
        #expect(first.presentedAt == noon)
    }

    @Test func moreShowsQueuedQuestions() throws {
        let model = try Harness().model()
        var settings = model.truth.settings
        settings.sessionBudget = 1
        try model.save(settings)
        for name in ["A", "B", "C"] {
            _ = try addHabit(model, name)
        }
        #expect(model.questions.count == 1)
        #expect(model.queuedCount == 2)
        try model.showMore()
        #expect(model.questions.count == 2)
        #expect(model.queuedCount == 1)
        try model.startSession()
        #expect(model.questions.count == 1)
    }

    @Test func answeringUpdatesTodayStatusAndHistory() throws {
        let model = try Harness().model()
        let gym = try addHabit(model, "Gym")
        try model.answer(#require(model.questions.first), with: .done)
        #expect(model.questions.isEmpty)
        #expect(model.todayStatus(of: gym.id) == .done)
        #expect(model.history(of: gym.id).map(\.source) == [.observed])
        #expect(model.adherence(of: gym.id)?.days == 1)
        try model.advanceDay()
        try model.answer(#require(model.questions.first), with: .notDone)
        #expect(model.history(of: gym.id).map(\.value) == [0, 1])
        #expect(model.adherence(of: gym.id)?.mean == 0.5)
    }

    @Test func notDueHabitShowsNextCheckIn() throws {
        let model = try Harness().model()
        let gym = try addHabit(model, "Gym")
        #expect(try model.nextCheckIn() == nil)
        try model.answer(#require(model.questions.first), with: .done)
        #expect(model.todayStatus(of: gym.id) == .done)
        let next = try #require(try model.nextCheckIn())
        #expect(next.habit.id == gym.id)
        #expect(next.day == start.adding(days: 1))
    }

    @Test func stateSurvivesRelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let harness = try Harness(location: .file(url))
        let first = try harness.model()
        let gym = try addHabit(first, "Gym")
        try first.answer(#require(first.questions.first), with: .done)
        try first.advanceDay()

        let relaunched = try AppModel(
            store: TruthStore(container: StoreContainer.make(.file(url))), timeZone: .gmt,
            defaults: harness.defaults
        ) { FixedClock(date: noon, calendar: $0) }
        #expect(relaunched.dayOffset == 1)
        #expect(relaunched.activeHabits.map(\.id) == [gym.id])
        #expect(relaunched.history(of: gym.id).last?.source == .observed)
        #expect(relaunched.truth.answers == first.truth.answers)
    }

    @Test func dayStartHourMovesToday() throws {
        let model = try Harness().model()
        var settings = model.truth.settings
        settings.dayStartHour = 13
        try model.save(settings)
        // Noon is before a 13:00 day start, so it still belongs to the previous day.
        #expect(model.today == start.adding(days: -1))
    }

    @Test func invalidEditsThrowAndChangeNothing() throws {
        let model = try Harness().model()
        var settings = model.truth.settings
        settings.sessionBudget = 0
        #expect(throws: Settings.ValidationError.sessionBudgetOutOfRange(0)) { try model.save(settings) }
        #expect(model.truth.settings == .default)
        #expect(throws: Habit.ValidationError.emptyName) { try model.save(model.newHabitDraft()) }
        #expect(model.truth.habits.isEmpty)
    }

    @Test func eraseAllResetsDataAndClock() throws {
        let model = try Harness().model()
        try model.addSampleHabits()
        #expect(model.activeHabits.map(\.name) == ["Gym", "Meditate", "Read"])
        #expect(model.questions.count == 3)
        try model.advanceDay()
        try model.eraseAll()
        #expect(model.truth == Truth(habits: []))
        #expect(model.dayOffset == 0)
        #expect(model.questions.isEmpty)
    }
}
