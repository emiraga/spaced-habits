import Foundation
import HabitCore
import Testing

/// 2026-09-27.
private let today = DayKey(dayNumber: 20723)
private let noon = Date(timeIntervalSince1970: TimeInterval(today.dayNumber * 86400 + 12 * 3600))

private func clock() throws -> FixedClock {
    let utc = try #require(TimeZone(identifier: "UTC"))
    return try FixedClock(date: noon, calendar: DayCalendar(timeZone: utc))
}

private func day(_ offset: Int) -> DayKey {
    today.adding(days: offset)
}

private func habit(_ name: String, createdDaysAgo: Int = 20, parents: [UUID] = []) -> Habit {
    Habit(
        name: name,
        colorHex: "#00AA00",
        createdAt: noon,
        createdDay: day(-createdDaysAgo),
        dependencies: parents.map { Dependency(parentID: $0) }
    )
}

/// An answer about `first...last` (day offsets), given at noon on `last` plus `order` seconds.
private func answer(_ habit: Habit, _ first: Int, _ last: Int, _ value: AnswerValue, order: Int = 0) -> Answer {
    Answer(
        questionID: UUID(),
        habitID: habit.id,
        covers: day(first) ... day(last),
        value: value,
        answeredAt: noon.addingTimeInterval(TimeInterval(last * 86400 + order)),
        timezone: "UTC",
        channel: .app
    )
}

private func pause(_ habits: [Habit], _ first: Int, _ last: Int) -> PauseEvent {
    PauseEvent(habitIDs: habits.map(\.id), start: day(first), end: day(last), reason: .sick, createdAt: noon)
}

private func record(_ projected: Projected, _ habit: Habit, _ offset: Int) throws -> DayRecord {
    try #require(projected.records[habit.id]?[day(offset)])
}

struct ProjectionDeterminismTests {
    @Test func sameTruthProducesIdenticalOutput() throws {
        let gym = habit("Gym")
        let shake = habit("Shake", parents: [gym.id])
        let truth = Truth(
            habits: [shake, gym],
            answers: [
                answer(gym, -19, -13, .count(done: 5, total: 7)),
                answer(gym, -12, -10, .perDay([day(-12): true, day(-11): false, day(-10): true])),
                answer(shake, -12, -10, .perDay([day(-12): true, day(-10): false])),
                answer(gym, -1, -1, .dontRemember),
                answer(gym, 0, 0, .done),
            ],
            pauses: [pause([gym], -8, -5)],
            healthObservations: [HealthObservation(habitID: gym.id, day: day(-3), sampleID: "w1")]
        )
        let first = try Projection.rebuild(truth, clock: clock())
        let second = try Projection.rebuild(truth, clock: clock())
        #expect(first == second)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(try encoder.encode(first) == encoder.encode(second))
        #expect(first.records[gym.id]?.count == 21)
        #expect(first.series[gym.id]?.map(\.day) == Array(day(-20) ... today))
        #expect(try JSONDecoder().decode(Projected.self, from: encoder.encode(first)) == first)
    }

    @Test func rejectsReferencesToUnknownHabits() {
        let gym = habit("Gym")
        let stray = habit("Stray")
        #expect(throws: Truth.ValidationError.unknownHabit(stray.id)) {
            try Projection.rebuild(Truth(habits: [gym], answers: [answer(stray, 0, 0, .done)]), clock: clock())
        }
    }

    @Test func habitCreatedAfterTodayHasInitialState() throws {
        let future = habit("Future", createdDaysAgo: -2)
        let projected = try Projection.rebuild(Truth(habits: [future]), clock: clock())
        #expect(projected.records[future.id] == [:])
        #expect(projected.states[future.id] == .initial(habitID: future.id))
    }
}

struct ProjectionSourceTests {
    @Test func precedenceIsPauseHealthAnswerThenInference() throws {
        let gym = habit("Gym", createdDaysAgo: 3)
        let truth = Truth(
            habits: [gym],
            answers: [answer(gym, -3, -3, .notDone), answer(gym, -2, -2, .notDone), answer(gym, -1, -1, .done)],
            pauses: [pause([gym], -3, -3)],
            healthObservations: [
                HealthObservation(habitID: gym.id, day: day(-3), sampleID: "a"),
                HealthObservation(habitID: gym.id, day: day(-2), sampleID: "b"),
            ]
        )
        let projected = try Projection.rebuild(truth, clock: clock())
        #expect(try record(projected, gym, -3).source == .paused)
        #expect(try record(projected, gym, -2).source == .health)
        #expect(try record(projected, gym, -2).value == 1)
        #expect(try record(projected, gym, -1).source == .observed)
        #expect(try record(projected, gym, 0).source == .unknown)
    }

    @Test func laterAnswerOverridesAndCountSpreadsEvenly() throws {
        let gym = habit("Gym", createdDaysAgo: 3)
        let first = answer(gym, -3, 0, .count(done: 3, total: 4))
        // Answered a second after `first`, which is timestamped on day 0.
        let correction = answer(gym, -1, -1, .notDone, order: 86401)
        let projected = try Projection.rebuild(Truth(habits: [gym], answers: [correction, first]), clock: clock())
        for offset in [-3, -2, 0] {
            #expect(try record(projected, gym, offset).source == .aggregated)
            #expect(try record(projected, gym, offset).value == 0.75)
            #expect(try record(projected, gym, offset).questionID == first.questionID)
        }
        #expect(try record(projected, gym, -1).value == 0)
        #expect(try record(projected, gym, -1).source == .observed)
    }

    @Test func daysBeyondRecallCapAreInferredFromTheModel() throws {
        let gym = habit("Gym", createdDaysAgo: 40)
        let steady = (-40 ... -20).map { answer(gym, $0, $0, .done) }
        let catchUp = answer(gym, -6, 0, .count(done: 7, total: 7))
        let projected = try Projection.rebuild(Truth(habits: [gym], answers: steady + [catchUp]), clock: clock())
        let gap = try record(projected, gym, -10)
        let model = try #require(projected.series[gym.id]?[30])
        #expect(gap.source == .inferred)
        #expect(gap.value == model.mean)
        #expect(gap.value > 0.8)
        #expect(gap.confidence == 1 - 2 * model.standardDeviation)
        #expect(try record(projected, gym, -6).source == .aggregated)
        let state = try #require(projected.states[gym.id])
        #expect(state.lastCoveredDay == today)
        #expect(state.lastAskedDay == today)
        #expect(state.currentIntervalDays > 1)
    }

    @Test func delayAnswersDoNotCoverDays() throws {
        let gym = habit("Gym", createdDaysAgo: 3)
        let projected = try Projection.rebuild(
            Truth(habits: [gym], answers: [answer(gym, -2, -2, .done), answer(gym, -1, -1, .delayed(days: 1))]),
            clock: clock()
        )
        let state = try #require(projected.states[gym.id])
        #expect(state.lastCoveredDay == day(-2))
        #expect(state.lastAskedDay == day(-1))
    }
}

struct ProjectionPauseTests {
    private let gym = habit("Gym", createdDaysAgo: 30)

    private func daily(_ range: ClosedRange<Int>) -> [Answer] {
        range.map { answer(gym, $0, $0, .done) }
    }

    @Test func pauseFreezesModelAndForcesReentry() throws {
        let truth = Truth(habits: [gym], answers: daily(-30 ... -11), pauses: [pause([gym], -10, -1)])
        let projected = try Projection.rebuild(truth, clock: clock())
        let series = try #require(projected.series[gym.id])
        #expect(series[20].mean == series[29].mean)
        #expect(series[20].standardDeviation == series[29].standardDeviation)
        let state = try #require(projected.states[gym.id])
        #expect(state.forcedReentryCheck)
        #expect(state.lastCoveredDay == day(-1))
        let planner = try QuestionPlanner(settings: .default)
        #expect(try planner.dueReason(habit: gym, state: state, today: today) == .reentry)
        #expect(planner.covers(habit: gym, state: state, today: today) == today ... today)
    }

    @Test func answerAfterPauseClearsReentry() throws {
        let truth = Truth(habits: [gym], answers: daily(-30 ... -11) + daily(0 ... 0), pauses: [pause([gym], -10, -1)])
        #expect(try Projection.rebuild(truth, clock: clock()).states[gym.id]?.forcedReentryCheck == false)
    }

    @Test func backdatedPauseReplacesAnsweredDays() throws {
        let answers = daily(-30 ... -3) + [answer(gym, -2, -2, .notDone), answer(gym, -1, -1, .notDone)]
        let unpaused = try Projection.rebuild(Truth(habits: [gym], answers: answers), clock: clock())
        let backdated = try Projection.rebuild(
            Truth(habits: [gym], answers: answers, pauses: [pause([gym], -2, -1)]),
            clock: clock()
        )
        #expect(try record(backdated, gym, -2).source == .paused)
        let before = try #require(unpaused.states[gym.id]).adherence.mean
        let after = try #require(backdated.states[gym.id]).adherence.mean
        #expect(after > before)
    }

    @Test func cancelledPauseChangesNothing() throws {
        let answers = daily(-30 ... -1)
        var cancelled = pause([gym], -2, 3)
        cancelled.cancelledAt = noon
        let plain = try Projection.rebuild(Truth(habits: [gym], answers: answers), clock: clock())
        let withCancelled = try Projection.rebuild(
            Truth(habits: [gym], answers: answers, pauses: [cancelled]),
            clock: clock()
        )
        #expect(withCancelled == plain)
    }

    @Test func endingEarlyAsksTheReentryCheckToday() throws {
        let ended = pause([gym], -3, 5).endedEarly(today: today, at: noon)
        let projected = try Projection.rebuild(
            Truth(habits: [gym], answers: daily(-30 ... -4), pauses: [ended]),
            clock: clock()
        )
        #expect(try record(projected, gym, -1).source == .paused)
        #expect(try record(projected, gym, 0).source != .paused)
        #expect(projected.states[gym.id]?.forcedReentryCheck == true)
    }

    @Test func pausedParentBlocksAndFreezesChild() throws {
        let shake = habit("Shake", createdDaysAgo: 30, parents: [gym.id])
        let answers = daily(-30 ... -11) + (-30 ... -11).map { answer(shake, $0, $0, .done) }
        let projected = try Projection.rebuild(
            Truth(habits: [gym, shake], answers: answers, pauses: [pause([gym], -10, -1)]),
            clock: clock()
        )
        #expect(try record(projected, shake, -5).source == .blocked)
        let series = try #require(projected.series[shake.id])
        #expect(series[20] == ModelPoint(
            day: day(-10), mean: series[19].mean, standardDeviation: series[19].standardDeviation,
            intervalDays: series[19].intervalDays
        ))
        #expect(projected.states[shake.id]?.forcedReentryCheck == true)
    }
}

struct ProjectionConditionalTests {
    @Test func childIsExcludedOnDaysParentWasNotDone() throws {
        let gym = habit("Gym", createdDaysAgo: 2)
        let shake = habit("Shake", createdDaysAgo: 2, parents: [gym.id])
        let answers = [
            answer(gym, -2, 0, .perDay([day(-2): true, day(-1): false, day(0): true])),
            answer(shake, -2, 0, .perDay([day(-2): true, day(0): true])),
        ]
        let projected = try Projection.rebuild(Truth(habits: [gym, shake], answers: answers), clock: clock())
        let excluded = try record(projected, shake, -1)
        #expect(excluded.source == .observed && excluded.value == 0 && excluded.conditionalDenominatorExcluded)
        // Only the two parent-done days feed P(shake | gym).
        #expect(projected.states[shake.id]?.adherence.evidence ?? 0 < 4.01)
        #expect(projected.states[shake.id]?.adherence.mean ?? 0 > 0.7)
    }

    @Test func gatedCountSpreadsOverParentDoneDays() throws {
        let gym = habit("Gym", createdDaysAgo: 5)
        let shake = habit("Shake", createdDaysAgo: 5, parents: [gym.id])
        let gymDays = Dictionary(uniqueKeysWithValues: (-5 ... 0).map { (day($0), $0 % 2 == 0) })
        let answers = [
            answer(gym, -5, 0, .perDay(gymDays)),
            answer(shake, -5, 0, .count(done: 2, total: 3)),
        ]
        let projected = try Projection.rebuild(Truth(habits: [gym, shake], answers: answers), clock: clock())
        for offset in -5 ... 0 {
            let shakeDay = try record(projected, shake, offset)
            if offset % 2 == 0 {
                #expect(shakeDay.source == .aggregated && abs(shakeDay.value - 2.0 / 3) < 1e-12)
            } else {
                #expect(shakeDay.conditionalDenominatorExcluded)
            }
        }
    }
}
