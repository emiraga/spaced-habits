import Foundation
import HabitCore
import Testing

/// 2026-09-27.
private let today = DayKey(dayNumber: 20723)
private let noon = Date(timeIntervalSince1970: TimeInterval(today.dayNumber * 86400 + 12 * 3600))

private func settings(spotCheckRate: Double = 0, sessionBudget: Int = 3) -> Settings {
    var settings = Settings.default
    settings.spotCheckRate = spotCheckRate
    settings.sessionBudget = sessionBudget
    return settings
}

private func planner(spotCheckRate: Double = 0, sessionBudget: Int = 3) throws -> QuestionPlanner {
    try QuestionPlanner(settings: settings(spotCheckRate: spotCheckRate, sessionBudget: sessionBudget))
}

private func habit(
    id: UUID = UUID(),
    createdDaysAgo: Int = 100,
    importance: Importance = .normal,
    maxRecallGapDays: Int = Habit.defaultMaxRecallGapDays
) -> Habit {
    Habit(
        id: id,
        name: "Gym",
        colorHex: "#00AA00",
        createdAt: noon,
        createdDay: today.adding(days: -createdDaysAgo),
        importance: importance,
        maxRecallGapDays: maxRecallGapDays
    )
}

/// State of a habit answered "yes" daily for a long time: mean ≈ 0.93, sd ≈ 0.06, interval 14 days (the ceiling).
private func steadyState(
    for habit: Habit,
    coveredDaysAgo: Int = 1,
    askedDaysAgo: Int = 1,
    reentry: Bool = false
) -> SchedulerState {
    SchedulerState(
        habitID: habit.id,
        alpha: 13.5,
        beta: 1,
        lastCoveredDay: today.adding(days: -coveredDaysAgo),
        lastAskedDay: today.adding(days: -askedDaysAgo),
        forcedReentryCheck: reentry
    )
}

struct QuestionPlannerDueTests {
    @Test func rejectsInvalidSettings() {
        var bad = Settings.default
        bad.sessionBudget = 0
        #expect(throws: Settings.ValidationError.sessionBudgetOutOfRange(0)) { try QuestionPlanner(settings: bad) }
    }

    @Test func newHabitIsDueToday() throws {
        let new = habit(createdDaysAgo: 0)
        // No evidence: rule 2 has nothing to compare, rule 1 fires on the prior's sd ≈ 0.29.
        let reason = try planner().dueReason(habit: new, state: .initial(habitID: new.id), today: today)
        #expect(reason == .uncertain)
        let question = try #require(try planner().question(
            habit: new, state: .initial(habitID: new.id), today: today, createdAt: noon
        ))
        #expect(question.covers == today ... today)
        #expect(question.shape == .singleDay)
    }

    @Test func habitCreatedAfterTodayIsNotDue() throws {
        let future = habit(createdDaysAgo: -1)
        #expect(try planner().dueReason(habit: future, state: .initial(habitID: future.id), today: today) == nil)
    }

    @Test func steadyHabitIsNotDue() throws {
        let steady = habit()
        #expect(try planner().dueReason(habit: steady, state: steadyState(for: steady), today: today) == nil)
    }

    @Test func archivedOrCoveredTodayIsNeverDue() throws {
        var archived = habit()
        archived.archivedAt = noon
        #expect(try planner().dueReason(habit: archived, state: .initial(habitID: archived.id), today: today) == nil)

        let covered = habit()
        let state = SchedulerState(
            habitID: covered.id,
            alpha: 1,
            beta: 5,
            lastCoveredDay: today,
            forcedReentryCheck: true
        )
        #expect(try planner().dueReason(habit: covered, state: state, today: today) == nil)
    }

    @Test func reentryWinsOverOtherRules() throws {
        let paused = habit()
        let state = steadyState(for: paused, reentry: true)
        #expect(try planner().dueReason(habit: paused, state: state, today: today) == .reentry)
    }

    @Test func belowTargetAskedOncePerDay() throws {
        let struggling = habit()
        // mean 0.6 with lots of evidence: sd ≈ 0.049, below threshold, so only rule 2 applies.
        var state = SchedulerState(habitID: struggling.id, alpha: 60, beta: 40, lastCoveredDay: today.adding(days: -1))
        state.lastAskedDay = today.adding(days: -1)
        #expect(try planner().dueReason(habit: struggling, state: state, today: today) == .belowTarget)
        state.lastAskedDay = today
        #expect(try planner().dueReason(habit: struggling, state: state, today: today) == nil)
    }

    /// O6 regression: a steady habit left unasked drifts toward mean 0.5, but that is fading
    /// confidence, not struggling. It comes back as `.uncertain`, never `.belowTarget`.
    @Test func silenceIsNotStruggling() throws {
        let steady = habit()
        // A 90% habit at full evidence (mean 0.84 with the prior), last answered 13 days ago.
        var state = SchedulerState(
            habitID: steady.id, alpha: 12.25, beta: 2.25, lastCoveredDay: today.adding(days: -13),
            lastAskedDay: today.adding(days: -13)
        )
        var decayed = state.adherence
        try decayed.decay(days: 13, rate: Settings.default.decayPerDay)
        state.adherence = decayed
        #expect(decayed.mean < steady.targetAdherence)
        #expect(try planner().dueReason(habit: steady, state: state, today: today) == .uncertain)
    }

    @Test func maxIntervalCeiling() throws {
        let steady = habit()
        let maxDays = Settings.default.maxIntervalDays
        let atCeiling = steadyState(for: steady, coveredDaysAgo: maxDays, askedDaysAgo: maxDays)
        #expect(try planner().dueReason(habit: steady, state: atCeiling, today: today) == .maxInterval)
        let belowCeiling = steadyState(for: steady, coveredDaysAgo: maxDays - 1, askedDaysAgo: maxDays - 1)
        #expect(try planner().dueReason(habit: steady, state: belowCeiling, today: today) == nil)
    }

    @Test func uncertainWhenEvidenceIsThin() throws {
        let thin = habit()
        // Two days of "yes": evidence mean 1.0, but sd ≈ 0.19 is above threshold.
        let state = SchedulerState(
            habitID: thin.id,
            alpha: 3,
            beta: 1,
            lastCoveredDay: today.adding(days: -1),
            lastAskedDay: today
        )
        #expect(state.adherence.standardDeviation > Settings.default.uncertaintyThreshold)
        #expect(try planner().dueReason(habit: thin, state: state, today: today) == .uncertain)
    }

    @Test func spotCheckOnlyOnLongAskIntervals() throws {
        let steady = habit()
        #expect(try planner(spotCheckRate: 1)
            .dueReason(habit: steady, state: steadyState(for: steady), today: today) == .spotCheck)
        // mean ≈ 0.82, sd just under threshold: ask interval is short, so no spot check.
        let shortInterval = SchedulerState(
            habitID: steady.id, alpha: 7, beta: 1.5, lastCoveredDay: today.adding(days: -1),
            lastAskedDay: today.adding(days: -1)
        )
        let interval = try shortInterval.adherence.askIntervalDays(target: steady.targetAdherence, settings: .default)
        #expect(interval <= SpotCheck.minAskIntervalDays)
        #expect(try planner(spotCheckRate: 1).dueReason(habit: steady, state: shortInterval, today: today) == nil)
    }

    @Test func nextCheckInFollowsTheAskInterval() throws {
        let steady = habit()
        var state = steadyState(for: steady, coveredDaysAgo: 0)
        state.currentIntervalDays = 9
        #expect(try planner().nextCheckIn(habit: steady, state: state, askDay: today) == today.adding(days: 9))
    }

    @Test func nextCheckInIsCappedByTheCeiling() throws {
        let steady = habit()
        var state = steadyState(for: steady, coveredDaysAgo: 10)
        state.currentIntervalDays = 9
        // Covered 10 days ago, ceiling 14: due in 4 days, before the interval runs out.
        #expect(try planner().nextCheckIn(habit: steady, state: state, askDay: today) == today.adding(days: 4))
    }

    @Test func nextCheckInIsAfterTheAskDay() throws {
        let fresh = habit(createdDaysAgo: 0)
        #expect(try planner().nextCheckIn(habit: fresh, state: .initial(habitID: fresh.id), askDay: today)
            == today.adding(days: 1))
        let overdue = habit()
        #expect(try planner().nextCheckIn(
            habit: overdue,
            state: steadyState(for: overdue, coveredDaysAgo: 20),
            askDay: today
        ) == today.adding(days: 1))
    }
}

struct QuestionPlannerShapeTests {
    private func covers(gap: Int, cap: Int = Habit.defaultMaxRecallGapDays) throws -> ClosedRange<DayKey>? {
        let subject = habit(maxRecallGapDays: cap)
        return try planner().covers(habit: subject, state: steadyState(for: subject, coveredDaysAgo: gap), today: today)
    }

    @Test func shapesFollowGap() throws {
        #expect(try covers(gap: 0) == nil)
        let one = try #require(try covers(gap: 1))
        #expect(QuestionPlanner.shape(for: one) == .singleDay)
        let three = try #require(try covers(gap: 3))
        #expect(three == today.adding(days: -2) ... today)
        #expect(QuestionPlanner.shape(for: three) == .perDay(days: [
            today.adding(days: -2),
            today.adding(days: -1),
            today,
        ]))
        let four = try #require(try covers(gap: 4))
        #expect(QuestionPlanner.shape(for: four) == .count(total: 4))
    }

    @Test func recallCapLimitsCovers() throws {
        let capped = try #require(try covers(gap: 12))
        #expect(capped == today.adding(days: -6) ... today)
        #expect(QuestionPlanner.shape(for: capped) == .count(total: 7))
        let tight = try #require(try covers(gap: 5, cap: 2))
        #expect(QuestionPlanner.shape(for: tight) == .perDay(days: [today.adding(days: -1), today]))
    }
}

struct QuestionPlannerRankingTests {
    private func clock() throws -> FixedClock {
        let utc = try #require(TimeZone(identifier: "UTC"))
        return try FixedClock(date: noon, calendar: DayCalendar(timeZone: utc))
    }

    @Test func clockMapsToToday() throws {
        #expect(try clock().today() == today)
    }

    @Test func importanceAndStalenessScale() throws {
        let low = habit(importance: .low)
        let high = habit(importance: .high)
        let state = SchedulerState(habitID: low.id, alpha: 2, beta: 2, lastAskedDay: today.adding(days: -7))
        let deviation = state.adherence.standardDeviation
        #expect(try planner().score(habit: low, state: state, today: today) == deviation * 1 * 2)
        #expect(try planner().score(habit: high, state: state, today: today) == deviation * 2 * 2)
    }

    @Test func reentryAndStrugglingSurfaceFirst() throws {
        let uncertainHigh = habit(importance: .high)
        let struggling = habit(importance: .low)
        let reentry = habit(importance: .low)
        let states: [UUID: SchedulerState] = [
            uncertainHigh.id: SchedulerState(
                habitID: uncertainHigh.id, alpha: 2, beta: 1, lastCoveredDay: today.adding(days: -10),
                lastAskedDay: today
            ),
            struggling.id: SchedulerState(
                habitID: struggling.id,
                alpha: 60,
                beta: 40,
                lastCoveredDay: today.adding(days: -1)
            ),
            reentry.id: steadyState(for: reentry, reentry: true),
        ]
        let ranked = try planner().rankedDue(
            habits: [uncertainHigh, struggling, reentry],
            states: states,
            records: [:],
            unavailable: [],
            clock: clock()
        )
        #expect(ranked.map(\.habitID) == [reentry.id, struggling.id, uncertainHigh.id])
        #expect(ranked.map(\.reason) == [.reentry, .belowTarget, .uncertain])
        #expect(ranked[2].score > ranked[0].score)
    }

    @Test func tiesBreakByHabitID() throws {
        let first = try habit(id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")))
        let second = try habit(id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")))
        let ranked = try planner().rankedDue(
            habits: [second, first],
            states: [:],
            records: [:],
            unavailable: [],
            clock: clock()
        )
        #expect(ranked.map(\.habitID) == [first.id, second.id])
    }

    @Test func sessionRespectsBudgetAndAvailability() throws {
        let habits = (0 ..< 5).map { _ in habit() }
        let paused = habits[4]
        let plan = try planner(sessionBudget: 3).session(
            habits: habits,
            states: [:],
            records: [:],
            unavailable: [paused.id],
            clock: clock()
        )
        #expect(plan.questions.count == 3)
        #expect(plan.presented.map(\.habitID) == plan.questions.map(\.habitID))
        #expect(plan.queued.count == 1)
        let asked = Set(plan.questions.map(\.habitID) + plan.queued.map(\.habitID))
        #expect(asked == Set(habits.prefix(4).map(\.id)))
        for question in plan.questions {
            #expect(question.createdAt == noon)
            #expect(question.shape == .count(total: 7))
        }
    }
}

struct SpotCheckTests {
    @Test func drawIsStableAcrossProcesses() throws {
        let id = try #require(UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301"))
        // Pinned: changing the hash reshuffles every user's spot-check days.
        #expect(SpotCheck.draw(habitID: id, day: today) == 0.9772427304195902)
        #expect(SpotCheck.draw(habitID: id, day: today) != SpotCheck.draw(habitID: id, day: today.adding(days: 1)))
    }

    @Test func rateMatchesSetting() throws {
        let id = try #require(UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301"))
        let draws = (0 ..< 20000).map { SpotCheck.draw(habitID: id, day: today.adding(days: $0)) }
        #expect(draws.allSatisfy { (0.0 ..< 1.0).contains($0) })
        let hits = draws.count { $0 < 0.05 }
        #expect(abs(Double(hits) / Double(draws.count) - 0.05) < 0.01)
        #expect(SpotCheck.isSpotCheck(habitID: id, day: today, rate: 0.98))
        #expect(!SpotCheck.isSpotCheck(habitID: id, day: today, rate: 0.97))
    }
}
