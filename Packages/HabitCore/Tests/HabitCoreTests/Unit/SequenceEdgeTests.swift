import Foundation
import HabitCore
import Testing

/// 2026-09-27.
private let today = DayKey(dayNumber: 20723)
private let noon = Date(timeIntervalSince1970: TimeInterval(today.dayNumber * 86400 + 12 * 3600))

private func day(_ offset: Int) -> DayKey {
    today.adding(days: offset)
}

/// §13 M4: a `.sequence` edge Gym → Stretch is inert. Gym fails for a week and is paused today; Stretch is
/// planned and projected exactly as if the edge did not exist, and the mode survives JSON.
struct SequenceEdgeTests {
    private let gym = Habit(name: "Gym", colorHex: "#00AA00", createdAt: noon, createdDay: day(-9))
    private let stretch = Habit(name: "Stretch", colorHex: "#0000AA", createdAt: noon, createdDay: day(-9))

    /// The fixture without any edge. Built once: answer IDs end up in the projected records.
    private let base: Truth

    init() {
        let gym = gym
        let gymNo = (-9 ... -1).map { offset in
            Answer(
                questionID: UUID(), habitID: gym.id, covers: day(offset) ... day(offset), value: .notDone,
                answeredAt: noon.addingTimeInterval(TimeInterval(offset * 86400)), timezone: "UTC", channel: .app
            )
        }
        let stretch = stretch
        let stretchCount = Answer(
            questionID: UUID(), habitID: stretch.id, covers: day(-6) ... day(-3), value: .count(done: 3, total: 4),
            answeredAt: noon.addingTimeInterval(-3 * 86400), timezone: "UTC", channel: .app
        )
        base = Truth(
            habits: [gym, stretch],
            answers: gymNo + [stretchCount],
            pauses: [PauseEvent(habitIDs: [gym.id], start: today, end: today, reason: .manual, createdAt: noon)]
        )
    }

    private func truth(stretchDependencies: [Dependency]) -> Truth {
        var truth = base
        truth.habits[1].dependencies = stretchDependencies
        return truth
    }

    private func plan(_ truth: Truth) throws -> (projected: Projected, questions: [Question]) {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let clock = try FixedClock(date: noon, calendar: DayCalendar(timeZone: utc))
        let projected = try Projection.rebuild(truth, clock: clock)
        let unavailable = try Pauses.unavailable(on: today, habits: truth.habits, pauses: truth.pauses)
        let questions = try QuestionPlanner(settings: truth.settings).session(
            habits: truth.habits, states: projected.states, records: projected.records,
            unavailable: Set(unavailable.keys), clock: clock
        ).questions
        return (projected, questions)
    }

    @Test func sequenceEdgeBehavesLikeNoEdge() throws {
        let sequenced = try plan(truth(stretchDependencies: [Dependency(parentID: gym.id, mode: .sequence)]))
        let unlinked = try plan(truth(stretchDependencies: []))

        #expect(sequenced.projected == unlinked.projected)
        let records = try #require(sequenced.projected.records[stretch.id]).values
        #expect(!records.contains { $0.source == .blocked || $0.conditionalDenominatorExcluded })

        let question = try #require(sequenced.questions.first { $0.habitID == stretch.id })
        let unlinkedQuestion = try #require(unlinked.questions.first { $0.habitID == stretch.id })
        #expect(question.parentContext == nil)
        #expect(question.covers == unlinkedQuestion.covers)
        #expect(question.shape == unlinkedQuestion.shape)
        #expect(!sequenced.questions.contains { $0.habitID == gym.id })
    }

    @Test func sameFixtureWithGateEdgeIsGatedAndBlocked() throws {
        let gated = try plan(truth(stretchDependencies: [Dependency(parentID: gym.id)]))
        #expect(gated.questions.isEmpty)
        #expect(gated.projected.records[stretch.id]?[today]?.source == .blocked)
    }

    @Test func jsonRoundTripPreservesMode() throws {
        let truth = truth(stretchDependencies: [Dependency(parentID: gym.id, mode: .sequence)])
        let decoded = try JSONDecoder().decode(Truth.self, from: JSONEncoder().encode(truth))
        #expect(decoded == truth)
        #expect(decoded.habits.first { $0.id == stretch.id }?.dependencies.map(\.mode) == [.sequence])
    }

    @Test func sequenceEdgeClosingCycleIsRejected() {
        var gym = gym
        gym.dependencies = [Dependency(parentID: stretch.id, mode: .sequence)]
        var stretch = stretch
        stretch.dependencies = [Dependency(parentID: gym.id)]
        #expect(throws: Dependencies.ValidationError.cycle([gym.id, stretch.id])) {
            try Dependencies.validate([gym, stretch])
        }
    }
}
