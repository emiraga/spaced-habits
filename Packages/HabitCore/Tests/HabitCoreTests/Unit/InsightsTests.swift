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

private func record(
    _ habitID: UUID,
    _ offset: Int,
    _ source: DaySource,
    _ value: Double = 1,
    excluded: Bool = false
) -> DayRecord {
    DayRecord(
        habitID: habitID, day: day(offset), value: value, source: source, confidence: 1,
        conditionalDenominatorExcluded: excluded
    )
}

private func records(_ list: [DayRecord]) -> [DayKey: DayRecord] {
    Dictionary(uniqueKeysWithValues: list.map { ($0.day, $0) })
}

private func answer(_ habit: Habit, _ covers: ClosedRange<DayKey>, _ value: AnswerValue) -> Answer {
    Answer(
        questionID: UUID(), habitID: habit.id, covers: covers, value: value, answeredAt: noon, timezone: "UTC",
        channel: .app
    )
}

private func pause(_ habit: Habit, _ first: Int, _ last: Int, _ reason: PauseReason) -> PauseEvent {
    PauseEvent(habitIDs: [habit.id], start: day(first), end: day(last), reason: reason, createdAt: noon)
}

struct AdherenceFilterTests {
    private let id = UUID()

    @Test func onlyEvidenceCounts() {
        let filter = AdherenceFilter()
        #expect(filter.value(of: record(id, 0, .observed, 1)) == 1)
        #expect(filter.value(of: record(id, 0, .aggregated, 0.5)) == 0.5)
        #expect(filter.value(of: record(id, 0, .health)) == 1)
        #expect(filter.value(of: record(id, 0, .inferred, 0.9)) == nil)
        #expect(filter.value(of: record(id, 0, .unknown, 0.5)) == nil)
        #expect(filter.value(of: record(id, 0, .paused, 0)) == nil)
        #expect(filter.value(of: record(id, 0, .blocked, 0)) == nil)
    }

    @Test func pausedDaysCountAsMissesWhenIncluded() {
        let filter = AdherenceFilter(includingPaused: true)
        #expect(filter.value(of: record(id, 0, .paused, 0)) == 0)
        #expect(filter.value(of: record(id, 0, .blocked, 0)) == 0)
    }

    /// §4.5: P(B|A) leaves out parent-miss days; P(B) counts them.
    @Test func parentMissesOnlyInOverall() {
        let miss = record(id, 0, .observed, 0, excluded: true)
        #expect(AdherenceFilter().value(of: miss) == nil)
        #expect(AdherenceFilter(includingParentMisses: true).value(of: miss) == 0)
    }

    @Test func meanCountsDays() throws {
        let list = [record(id, -2, .observed, 1), record(id, -1, .observed, 0), record(id, 0, .inferred, 0.9)]
        let mean = try #require(AdherenceFilter().mean(of: list))
        #expect(mean.mean == 0.5)
        #expect(mean.days == 2)
        #expect(AdherenceFilter().mean(of: [record(id, 0, .inferred)]) == nil)
    }
}

struct RollingAdherenceTests {
    private let id = UUID()

    @Test func trailingWindowMean() {
        // Done, not done, done, done over four days.
        let list = records([
            record(id, -3, .observed, 1), record(id, -2, .observed, 0), record(id, -1, .observed, 1),
            record(id, 0, .observed, 1),
        ])
        let points = Insights.rollingAdherence(list, over: day(-3) ... day(0), window: 2, filter: AdherenceFilter())
        #expect(points.map(\.mean) == [1, 0.5, 0.5, 1])
        #expect(points.map(\.day) == [day(-3), day(-2), day(-1), day(0)])
        #expect(Set(points.map(\.segment)) == [0])
    }

    @Test func gapsStartANewSegment() {
        // Evidence, then three paused days (longer than the window), then evidence again.
        let list = records([
            record(id, -5, .observed, 1), record(id, -4, .paused, 0), record(id, -3, .paused, 0),
            record(id, -2, .paused, 0), record(id, -1, .observed, 0), record(id, 0, .observed, 1),
        ])
        let points = Insights.rollingAdherence(list, over: day(-5) ... day(0), window: 2, filter: AdherenceFilter())
        #expect(points.map(\.day) == [day(-5), day(-4), day(-1), day(0)])
        #expect(points.map(\.segment) == [0, 0, 1, 1])
        let included = Insights.rollingAdherence(
            list, over: day(-5) ... day(0), window: 2, filter: AdherenceFilter(includingPaused: true)
        )
        #expect(included.count == 6)
        #expect(included[2].mean == 0)
    }

    /// The first window reaches back before the charted range.
    @Test func windowIncludesDaysBeforeRange() {
        let list = records([record(id, -1, .observed, 0), record(id, 0, .observed, 1)])
        let points = Insights.rollingAdherence(list, over: day(0) ... day(0), window: 7, filter: AdherenceFilter())
        #expect(points.map(\.mean) == [0.5])
    }
}

struct PauseBandTests {
    @Test func consecutiveDaysMergeByReason() {
        let id = UUID()
        let list = records([
            record(id, -6, .observed), record(id, -5, .paused, 0), record(id, -4, .paused, 0),
            record(id, -3, .blocked, 0), record(id, -2, .observed), record(id, -1, .paused, 0),
        ])
        #expect(Insights.pauseBands(list) == [
            DayBand(days: day(-5) ... day(-4), reason: .paused),
            DayBand(days: day(-3) ... day(-3), reason: .blocked),
            DayBand(days: day(-1) ... day(-1), reason: .paused),
        ])
        #expect(Insights.availableDays(list) == 2)
    }
}

struct HabitInsightsTests {
    @Test func summarizesProjection() throws {
        let gym = habit("Gym", createdDaysAgo: 20)
        let truth = Truth(
            habits: [gym],
            answers: [
                answer(gym, day(-20) ... day(-14), .count(done: 7, total: 7)),
                answer(gym, day(0) ... day(0), .done),
            ],
            pauses: [pause(gym, -10, -8, .manual), pause(gym, -5, -5, .manual), pause(gym, 5, 6, .manual)]
        )
        let projected = try Projection.rebuild(
            truth,
            clock: FixedClock(date: noon, calendar: DayCalendar(timeZone: .gmt))
        )
        let insights = HabitInsights(
            habit: gym, projected: projected, pauses: truth.pauses, today: today, filter: AdherenceFilter()
        )
        #expect(insights.days.count == 21)
        #expect(insights.series.count == 21)
        #expect(insights.pausedDays == 4)
        #expect(insights.availableDays == 17)
        #expect(insights.hasEnoughData)
        // The scheduled pause hasn't started.
        #expect(insights.delays == 2)
        #expect(insights.bands.map(\.days) == [day(-10) ... day(-8), day(-5) ... day(-5)])
        #expect(insights.rolling7.last?.mean == 1)
        #expect(insights.target == gym.targetAdherence)
    }

    @Test func tooFewDaysHidesCharts() throws {
        let gym = habit("Gym", createdDaysAgo: 5)
        let projected = try Projection.rebuild(
            Truth(habits: [gym]), clock: FixedClock(date: noon, calendar: DayCalendar(timeZone: .gmt))
        )
        let insights = HabitInsights(
            habit: gym,
            projected: projected,
            pauses: [],
            today: today,
            filter: AdherenceFilter()
        )
        #expect(insights.availableDays == 6)
        #expect(!insights.hasEnoughData)
    }
}

struct WeekdayTests {
    @Test func isoWeekdays() {
        #expect(DayKey(dayNumber: 0).weekday == 4) // 1970-01-01, Thursday
        #expect(today.weekday == 7) // Sunday
        #expect(today.adding(days: 1).weekday == 1)
        #expect(DayKey(dayNumber: -1).weekday == 3)
    }
}
