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
    }

    private func model(hour: Int) throws -> AppModel {
        try harness.model(at: noon.addingTimeInterval(TimeInterval(hour - 12) * 3600))
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
}
