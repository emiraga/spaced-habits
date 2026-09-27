import Foundation
import HabitCore
import Testing

/// 2026-09-27, a Sunday.
private let today = DayKey(dayNumber: 20723)
private let noon = Date(timeIntervalSince1970: TimeInterval(today.dayNumber * 86400 + 12 * 3600))

private func day(_ offset: Int) -> DayKey {
    today.adding(days: offset)
}

private func habit(_ name: String, parents: [UUID] = [], createdDaysAgo: Int = 60) -> Habit {
    Habit(
        name: name, colorHex: "#00AA00", createdAt: noon, createdDay: day(-createdDaysAgo),
        dependencies: parents.map { Dependency(parentID: $0) }
    )
}

private func answer(_ habit: Habit, _ offset: Int, _ done: Bool) -> Answer {
    Answer(
        questionID: UUID(), habitID: habit.id, covers: day(offset) ... day(offset), value: done ? .done : .notDone,
        answeredAt: noon.addingTimeInterval(TimeInterval(offset * 86400)), timezone: "UTC", channel: .app
    )
}

/// One answer per day from `first` through `last`, done where `done(offset)`.
private func answers(_ habit: Habit, _ first: Int, _ last: Int, done: (Int) -> Bool) -> [Answer] {
    (first ... last).map { answer(habit, $0, done($0)) }
}

private func question(_ habit: Habit, _ offset: Int) -> Question {
    Question(habitID: habit.id, covers: day(offset) ... day(offset), shape: .singleDay, createdAt: noon)
}

private func pause(_ habit: Habit, _ first: Int, _ last: Int, _ reason: PauseReason) -> PauseEvent {
    PauseEvent(habitIDs: [habit.id], start: day(first), end: day(last), reason: reason, createdAt: noon)
}

private func project(_ truth: Truth) throws -> Projected {
    try Projection.rebuild(truth, clock: FixedClock(date: noon, calendar: DayCalendar(timeZone: .gmt)))
}

private func overview(_ truth: Truth, filter: AdherenceFilter = AdherenceFilter()) throws -> Overview {
    try Overview(truth: truth, projected: project(truth), today: today, filter: filter)
}

struct OverviewTests {
    /// A card shown again after "Later" and a widget answer with no logged question each count once.
    @Test func questionsPerDayCountsHabitsAsked() throws {
        let gym = habit("Gym")
        let read = habit("Read")
        let truth = Truth(
            habits: [gym, read],
            questions: [question(gym, 0), question(gym, 0), question(read, -1)],
            answers: [answer(gym, 0, true), answer(read, 0, true)]
        )
        let burden = try overview(truth).questionsPerDay
        #expect(burden.count == Overview.burdenDays)
        #expect(burden.last == Overview.DayCount(day: today, count: 2))
        #expect(burden[burden.count - 2].count == 1)
        #expect(burden.dropLast(2).map(\.count).max() == 0)
    }

    @Test func autonomyIsMeanAskInterval() throws {
        let steady = habit("Steady")
        let flaky = habit("Flaky")
        let truth = Truth(
            habits: [steady, flaky],
            answers: answers(steady, -40, 0) { _ in true } + answers(flaky, -40, 0) { $0 % 2 == 0 }
        )
        let projected = try project(truth)
        let result = Overview(truth: truth, projected: projected, today: today, filter: AdherenceFilter())
        let intervals = try [steady, flaky].map { try #require(projected.states[$0.id]?.currentIntervalDays) }
        #expect(result.autonomyScore == Double(intervals.reduce(0, +)) / 2)
        #expect(try overview(Truth(habits: [])).autonomyScore == nil)
    }

    @Test func regressionIsA14DayDropOfAtLeastPointTwo() throws {
        let collapsing = habit("Collapsing")
        let steady = habit("Steady")
        let truth = Truth(
            habits: [collapsing, steady],
            answers: answers(collapsing, -43, 0) { $0 < -13 } + answers(steady, -43, 0) { _ in true }
        )
        let result = try overview(truth)
        #expect(result.regressions == [Overview.Regression(habitID: collapsing.id, recent: 0, prior: 1)])
    }

    @Test func noRegressionWithoutEnoughRecentAnswers() throws {
        let sparse = habit("Sparse")
        let truth = Truth(
            habits: [sparse],
            answers: answers(sparse, -43, -14) { _ in true } + [answer(sparse, -1, false), answer(sparse, 0, false)]
        )
        #expect(try overview(truth).regressions.isEmpty)
    }

    @Test func delayedOftenNeedsThreeRecentDelays() throws {
        let gym = habit("Gym")
        let read = habit("Read")
        let truth = Truth(
            habits: [gym, read],
            pauses: [
                pause(gym, -30, -30, .manual), pause(gym, -20, -20, .manual), pause(gym, -10, -10, .manual),
                pause(read, -70, -70, .manual), pause(read, -20, -20, .manual), pause(read, -10, -10, .sick),
            ]
        )
        #expect(try overview(truth).delayedOften == [Overview.DelayedHabit(habitID: gym.id, delays: 3)])
    }

    @Test func vacationsMergeAndClipToWindow() throws {
        let gym = habit("Gym", createdDaysAgo: 200)
        let truth = Truth(
            habits: [gym],
            pauses: [
                pause(gym, -120, -85, .vacation), pause(gym, -30, -25, .vacation), pause(gym, -24, -20, .vacation),
                pause(gym, -10, -8, .manual),
            ]
        )
        #expect(try overview(truth).vacations == [day(-89) ... day(-85), day(-30) ... day(-20)])
    }

    @Test func weekdayAdherencePerHabitAndOverall() throws {
        let gym = habit("Gym")
        let read = habit("Read")
        // Gym done on Sundays only; Read every day. Two weeks.
        let truth = Truth(
            habits: [gym, read],
            answers: answers(gym, -13, 0) { day($0).weekday == 7 } + answers(read, -13, 0) { _ in true }
        )
        let cells = try overview(truth).weekdays
        let gymSunday = try #require(cells.first { $0.habitID == gym.id && $0.weekday == 7 })
        let gymMonday = try #require(cells.first { $0.habitID == gym.id && $0.weekday == 1 })
        let allMonday = try #require(cells.first { $0.habitID == nil && $0.weekday == 1 })
        #expect(gymSunday.mean == 1)
        #expect(gymMonday.mean == 0)
        #expect(allMonday.mean == 0.5)
        #expect(allMonday.days == 4)
    }

    @Test func pausedDaysOnlyCountWhenIncluded() throws {
        let gym = habit("Gym", createdDaysAgo: 13)
        let truth = Truth(
            habits: [gym],
            answers: answers(gym, -13, -7) { _ in true },
            pauses: [pause(gym, -6, 0, .vacation)]
        )
        let excluded = try overview(truth)
        #expect(excluded.weekdays.filter { $0.habitID == nil }.allSatisfy { $0.mean == 1 })
        #expect(excluded.availableDays == 7)
        let included = try overview(truth, filter: AdherenceFilter(includingPaused: true))
        #expect(included.weekdays.filter { $0.habitID == nil }.allSatisfy { $0.mean == 0.5 })
    }

    @Test func archivedHabitsAreLeftOut() throws {
        var old = habit("Old")
        old.archivedAt = noon
        let truth = Truth(habits: [old], questions: [question(old, 0)])
        let result = try overview(truth)
        #expect(result.questionsPerDay.map(\.count).max() == 0)
        #expect(result.availableDays == 0)
        #expect(!result.hasEnoughData)
    }
}

struct ClusterInsightsTests {
    private let cluster = Cluster(name: "Fitness", colorHex: "#00AA00")

    @Test func pairsCompareConditionalAndOverall() throws {
        let gym = habit("Gym")
        let shake = habit("Shake", parents: [gym.id])
        // Gym on even days; Shake after 3 of every 4 gym days.
        let truth = Truth(
            habits: [gym, shake],
            answers: answers(gym, -29, 0) { $0 % 2 == 0 } + (-29 ... 0).filter { $0 % 2 == 0 }.map {
                answer(shake, $0, $0 % 8 != 0)
            }
        )
        let result = try ClusterInsights(
            clusterID: cluster.id, members: [gym, shake], records: project(truth).records, today: today,
            filter: AdherenceFilter()
        )
        let pair = try #require(result.pairs.first)
        #expect(result.pairs.count == 1)
        #expect(pair.habitID == shake.id)
        #expect(pair.parentIDs == [gym.id])
        // 15 gym days (-28 ... 0 even), shake missed on 0, -8, -16, -24.
        #expect(pair.conditional == 11.0 / 15)
        #expect(pair.overall == 11.0 / 30)
    }

    @Test func funnelFollowsLongestChain() throws {
        let gym = habit("Gym")
        let shake = habit("Shake", parents: [gym.id])
        let stretch = habit("Stretch", parents: [shake.id])
        let read = habit("Read")
        let truth = Truth(
            habits: [read, gym, shake, stretch],
            answers: answers(gym, -9, 0) { $0 >= -5 } + answers(shake, -5, 0) { $0 >= -3 }
                + answers(stretch, -3, 0) { $0 >= -1 } + answers(read, -9, 0) { _ in true }
        )
        let result = try ClusterInsights(
            clusterID: cluster.id, members: [read, gym, shake, stretch], records: project(truth).records,
            today: today, filter: AdherenceFilter()
        )
        #expect(result.funnel.map(\.habitID) == [gym.id, shake.id, stretch.id])
        #expect(result.funnel.map(\.days) == [6, 4, 2])
        #expect(result.funnelDays == 10)
    }

    @Test func noFunnelWithoutAChain() throws {
        let gym = habit("Gym")
        let read = habit("Read")
        let result = try ClusterInsights(
            clusterID: cluster.id, members: [gym, read], records: project(Truth(habits: [gym, read])).records,
            today: today, filter: AdherenceFilter()
        )
        #expect(result.funnel.isEmpty)
        #expect(result.pairs.isEmpty)
    }

    @Test func memberWeeksCoverTwelveWeeksEndingToday() throws {
        let gym = habit("Gym", createdDaysAgo: 100)
        let truth = Truth(habits: [gym], answers: answers(gym, -83, 0) { $0 >= -6 })
        let result = try ClusterInsights(
            clusterID: cluster.id, members: [gym], records: project(truth).records, today: today,
            filter: AdherenceFilter()
        )
        #expect(result.memberWeeks.count == ClusterInsights.weeks)
        #expect(result.memberWeeks.first?.weekStart == day(-83))
        #expect(result.memberWeeks.last == ClusterInsights.MemberWeek(habitID: gym.id, weekStart: day(-6), mean: 1))
        #expect(result.memberWeeks.dropLast().allSatisfy { $0.mean == 0 })
    }
}
