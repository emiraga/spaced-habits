import Foundation
import HabitCore
@testable import HabitUI
import Testing

/// Per-habit due time (DESIGN.md §4.2) through `AppModel`: noon is before Gym's 18:00 due time.
@MainActor
struct DueTimeTests {
    let harness: Harness
    let model: AppModel
    let gym: Habit

    /// Gym is created two days ago and answered that evening, so at noon today it asks "Done yesterday?".
    init() throws {
        harness = try Harness()
        model = try harness.model(at: noon.addingTimeInterval(-2 * 86400))
        var settings = model.truth.settings
        settings.spotCheckRate = 0
        try model.save(settings)
        var gym = model.newHabitDraft()
        gym.name = "Gym"
        gym.dueTime = try TimeOfDay(hour: 18, minute: 0)
        try model.save(gym)
        self.gym = gym
        let evening = try harness.model(at: noon.addingTimeInterval(-2 * 86400 + 7 * 3600))
        try evening.answer(#require(evening.questions.first), with: .done)
    }

    private func date(hour: Int, daysLater: Int = 0) -> Date {
        noon.addingTimeInterval(TimeInterval(daysLater * 24 + hour - 12) * 3600)
    }

    private func model(hour: Int) throws -> AppModel {
        try harness.model(at: date(hour: hour))
    }

    @Test func cardDelayBeforeTheDueTimePausesFromYesterday() throws {
        let app = try model(hour: 12)
        let question = try #require(app.questions.first)
        #expect(question.covers.upperBound == start.adding(days: -1))
        try app.delay(question, days: 2, reason: .manual)
        let pause = try #require(app.truth.pauses.first)
        #expect(pause.start == start.adding(days: -1))
        #expect(pause.end == start)
    }

    @Test func siriDelayBeforeTheDueTimePausesFromYesterday() throws {
        let app = try model(hour: 12)
        try app.delay(gym.id, days: 1)
        let pause = try #require(app.truth.pauses.first)
        #expect(pause.start == start.adding(days: -1) && pause.end == start.adding(days: -1))
        // Yesterday is paused, so nothing is asked until today at the due time.
        #expect(app.questions.isEmpty)
        #expect(app.nextCheckIn(of: gym) == start)
        #expect(try model(hour: 18).questions.first?.covers == start ... start)
    }

    @Test func answeringYesterdayLeavesTodayForTheDueTime() throws {
        let app = try model(hour: 12)
        let question = try #require(app.questions.first)
        try app.answer(question, with: allDone(question))
        #expect(app.questions.isEmpty)
        #expect(app.nextCheckIn(of: gym) == start)
        let evening = try model(hour: 18)
        #expect(evening.questions.first?.covers.upperBound == start)
    }

    @Test func widgetCardNamesAndAnswersYesterday() throws {
        let app = try model(hour: 12)
        let card = try #require(app.widgetSnapshot().cards.first)
        #expect(card.isYesNo && card.day == start.adding(days: -1))
        #expect(card.body == "Done yesterday?" && card.dayLabel == "Yesterday")
        try app.answer(card.id, day: card.day, done: true, channel: .widget)
        #expect(app.truth.answers.last?.covers == card.day ... card.day)
        #expect(app.questions.isEmpty)
        let evening = try #require(try model(hour: 18).widgetSnapshot().cards.first)
        #expect(evening.day == start && evening.dayLabel == nil && evening.body == "Done today?")
    }

    @Test func logAnswersTheAskDay() throws {
        let app = try model(hour: 12)
        #expect(try app.log(gym.id, done: true, channel: .shortcut) == start.adding(days: -1))
        #expect(app.truth.answers.last?.covers == start.adding(days: -1) ... start.adding(days: -1))
        // Yesterday is answered now; today waits for the due time.
        #expect(throws: AnswerRefusal.alreadyCovered(through: start.adding(days: -1))) {
            try app.log(gym.id, done: true, channel: .shortcut)
        }
        let evening = try model(hour: 18)
        #expect(try evening.log(gym.id, done: false, channel: .shortcut) == start)
    }

    @Test func timelineHasAnEntryAtTheDueTime() throws {
        let entries = try WidgetTimeline.entries(
            store: harness.store, timeZone: .gmt, defaults: harness.defaults, now: date(hour: 12)
        )
        #expect(entries.map(\.date) == [date(hour: 12), date(hour: 18), date(hour: 4, daysLater: 1)])
        #expect(entries[0].snapshot.cards.first?.day == start.adding(days: -1))
        // Yesterday was left unanswered, so the evening card asks about both days.
        let evening = try #require(entries[1].snapshot.cards.first)
        #expect(evening.day == start && evening.body == "Which of these days?")
    }

    @Test func todayReplansAtTheNextDueTime() throws {
        #expect(try model(hour: 12).nextReplan == date(hour: 18))
        #expect(try model(hour: 18).nextReplan == date(hour: 18, daysLater: 1))
        var archived = gym
        archived.archivedAt = noon
        let app = try model(hour: 12)
        try app.save(archived)
        #expect(app.nextReplan == nil)
    }

    @Test func notificationBeforeTheDueTimeAsksAboutYesterday() throws {
        let app = try model(hour: 12)
        let question = try #require(app.questions.first)
        let content = NotificationContent(
            PlannedNotification(fireAt: date(hour: 12), day: start, kind: .question(question, dueCount: 1)),
            habits: app.truth.habits
        )
        #expect(content.body == "Done yesterday?")
    }

    /// Before the due time the due marker sits on yesterday; from it on, on today (§4.2).
    @Test func dueGlyphMarksTheAskDay() throws {
        let noon = try model(hour: 12)
        #expect(noon.todayStatus(of: gym.id) == .notDue)
        #expect(noon.recentStatuses(of: gym).map(\.status) == [.done, .due, .notDue])
        #expect(noon.widgetSnapshot().habits.first?.status == .notDue)
        let evening = try model(hour: 18)
        #expect(evening.todayStatus(of: gym.id) == .due)
        #expect(evening.recentStatuses(of: gym).map(\.status).last == .due)
        #expect(evening.recentStatuses(of: gym).map(\.status)[1] != .due)
    }

    /// "Done today" logs today before the due time, while the card asks about yesterday (§5.1).
    @Test func doneTodayBeforeTheDueTime() throws {
        let app = try model(hour: 12)
        #expect(app.canLogDoneToday(gym.id))
        try app.logDoneToday(gym.id)
        #expect(app.truth.answers.last?.covers == start ... start)
        #expect(app.todayStatus(of: gym.id) == .done)
        #expect(app.questions.isEmpty)
        #expect(!app.canLogDoneToday(gym.id))
        #expect(throws: AnswerRefusal.alreadyCovered(through: start)) { try app.logDoneToday(gym.id) }
        // Undo on Today takes it back.
        try app.undoLastAnswer()
        #expect(app.todayStatus(of: gym.id) == .notDue)
        #expect(app.canLogDoneToday(gym.id))
    }

    @Test func doneTodayReplacesANo() throws {
        try model(hour: 18).log(gym.id, done: false, channel: .shortcut)
        let app = try model(hour: 19)
        #expect(app.todayStatus(of: gym.id) == .notDone)
        #expect(app.canLogDoneToday(gym.id))
        try app.logDoneToday(gym.id)
        #expect(app.todayStatus(of: gym.id) == .done)
    }

    @Test func doneTodayIsNotOfferedWhilePaused() throws {
        let app = try model(hour: 12)
        try app.pause(gym.id, from: start, through: start.adding(days: 2), reason: .manual)
        #expect(!app.canLogDoneToday(gym.id))
        #expect(throws: AnswerRefusal.unavailable(gym.id, start)) { try app.logDoneToday(gym.id) }
    }
}
