import Foundation
import HabitCore
import HabitStore
@testable import HabitUI
import Testing

/// The widget extension and Siri: their own `AppModel` on the shared store file (DESIGN.md §6).
@MainActor
private struct TwoProcesses {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).store")
    let harness: Harness
    let app: AppModel

    init() throws {
        harness = try Harness(location: .file(url))
        app = try harness.model()
        var settings = app.truth.settings
        settings.spotCheckRate = 0
        try app.save(settings)
    }

    func store() throws -> TruthStore {
        try TruthStore(container: StoreContainer.make(.file(url)))
    }

    func timeline() throws -> [(date: Date, snapshot: WidgetSnapshot)] {
        try WidgetTimeline.entries(store: store(), timeZone: .gmt, defaults: harness.defaults, now: noon)
    }

    /// What an intent opens: a model that plans without logging.
    func intentModel() throws -> AppModel {
        try AppModel(store: store(), timeZone: .gmt, defaults: harness.defaults, logsPresentedQuestions: false) {
            FixedClock(date: noon, calendar: $0)
        }
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: url)
    }
}

@MainActor
struct WidgetTests {
    /// §13 M6 checkpoint, minus SpringBoard: answer from the widget without opening the app, the widget
    /// advances to the next question, and the app shows the answer.
    @Test func checkpointAnswerFromWidgetAdvancesToNextQuestion() throws {
        let processes = try TwoProcesses()
        defer { processes.cleanUp() }
        let gym = try addHabit(processes.app, "Gym")
        let read = try addHabit(processes.app, "Read")

        let before = try processes.timeline()[0].snapshot
        #expect(before.cards.map(\.id) == processes.app.questions.map(\.habitID))
        #expect(before.dueCount == 2)
        let top = try #require(before.cards.first)
        #expect(top.isYesNo)
        #expect(top.body == "Done today?")

        try processes.intentModel().answerToday(top.id, done: true, channel: .widget)

        let after = try processes.timeline()[0].snapshot
        let other = top.id == gym.id ? read.id : gym.id
        #expect(after.cards.map(\.id) == [other])
        #expect(after.habits.first { $0.id == top.id }?.status == .done)

        try processes.app.reload()
        #expect(processes.app.todayStatus(of: top.id) == .done)
        #expect(processes.app.questions.map(\.habitID) == [other])
        let answer = try #require(processes.app.truth.answers.last)
        #expect(answer.channel == .widget)
        #expect(answer.covers == start ... start)
        #expect(processes.app.truth.questions.contains { $0.id == answer.questionID })
    }

    @Test func widgetPlanningLogsNoQuestions() throws {
        let processes = try TwoProcesses()
        defer { processes.cleanUp() }
        _ = try addHabit(processes.app, "Gym")
        let logged = try processes.store().load().questions
        _ = try processes.timeline()
        #expect(try processes.store().load().questions == logged)
    }

    /// A CloudKit merge mid-session (§10) drops cards answered elsewhere but keeps "Later" cards hidden;
    /// returning to the app starts a new session, which brings them back.
    @Test func syncReloadKeepsTheSession() throws {
        let processes = try TwoProcesses()
        defer { processes.cleanUp() }
        _ = try addHabit(processes.app, "Gym")
        _ = try addHabit(processes.app, "Read")
        let (first, second) = try (#require(processes.app.questions.first), #require(processes.app.questions.last))
        try processes.app.later(first)

        try processes.intentModel().answerToday(second.habitID, done: true, channel: .watch)
        try processes.app.reload(newSession: false)
        #expect(processes.app.questions.isEmpty)
        #expect(processes.app.todayStatus(of: second.habitID) == .done)

        try processes.app.reload()
        #expect(processes.app.questions.map(\.habitID) == [first.habitID])
    }

    @Test func timelineHasAnEntryAtTheNextDayBoundary() throws {
        let processes = try TwoProcesses()
        defer { processes.cleanUp() }
        let gym = try addHabit(processes.app, "Gym")
        try processes.app.answer(#require(processes.app.questions.first), with: .notDone)

        let entries = try processes.timeline()
        #expect(entries.map(\.date) == [noon, noon.addingTimeInterval(16 * 3600)])
        #expect(entries[0].snapshot.cards.isEmpty)
        #expect(entries[0].snapshot.nextCheckIn == "Gym, Tomorrow")
        #expect(entries[1].snapshot.today == start.adding(days: 1))
        #expect(entries[1].snapshot.cards.map(\.id) == [gym.id])
    }

    @Test func multiDayQuestionsOpenTheApp() throws {
        let processes = try TwoProcesses()
        defer { processes.cleanUp() }
        _ = try addHabit(processes.app, "Gym")
        for _ in 0 ..< 5 {
            try processes.app.advanceDay()
        }
        let card = try #require(processes.timeline()[0].snapshot.cards.first)
        #expect(!card.isYesNo)
    }

    @Test func staleWidgetTapIsRefused() throws {
        let processes = try TwoProcesses()
        defer { processes.cleanUp() }
        let gym = try addHabit(processes.app, "Gym")
        try processes.app.answer(#require(processes.app.questions.first), with: .notDone)

        #expect(throws: AnswerRefusal.alreadyCovered(through: start)) {
            try processes.intentModel().answerToday(gym.id, done: true, channel: .widget)
        }
        #expect(try processes.store().load().answers.map(\.value) == [.notDone])
    }

    @Test func pausedAndArchivedHabitsAreRefused() throws {
        let model = try Harness().model()
        var gym = try addHabit(model, "Gym")
        try model.delay(gym.id, days: 3)
        #expect(throws: AnswerRefusal.unavailable(gym.id, start)) {
            try model.answerToday(gym.id, done: true, channel: .shortcut)
        }
        gym.archivedAt = noon
        try model.save(gym)
        #expect(throws: AnswerRefusal.habitGone(gym.id)) {
            try model.answerToday(gym.id, done: true, channel: .shortcut)
        }
        #expect(throws: AnswerRefusal.habitGone(gym.id)) {
            try model.delay(gym.id, days: 3)
        }
        #expect(model.truth.answers.isEmpty)
    }

    /// "Delay Gym 3 days" from Shortcuts pauses today through two days out.
    @Test func delayPausesFromToday() throws {
        let model = try Harness().model()
        let gym = try addHabit(model, "Gym")
        try model.delay(gym.id, days: 3)
        #expect(model.resumeDay(of: gym.id) == start.adding(days: 3))
        #expect(model.questions.isEmpty)
    }
}

struct DeepLinkTests {
    @Test func roundTripsThroughURL() {
        let habit = UUID()
        for link in [DeepLink.today, .habit(habit), .insights] {
            #expect(DeepLink(url: link.url) == link)
        }
        #expect(DeepLink.habit(habit).url.absoluteString == "spacedhabits://habit/\(habit.uuidString)")
    }

    @Test func rejectsOtherURLs() throws {
        for string in [
            "https://today",
            "spacedhabits://habit/not-a-uuid",
            "spacedhabits://habit",
            "spacedhabits://settings",
            "spacedhabits://insights/extra",
        ] {
            #expect(try DeepLink(url: #require(URL(string: string))) == nil, "\(string)")
        }
    }
}
