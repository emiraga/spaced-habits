import Foundation
import HabitCore
import HabitSimulation
@testable import HabitUI
import SwiftUI
import Testing

@MainActor
struct ChartTests {
    /// §13 M9 checkpoint: the §4.8 `steady` run, exported as a fixture ending today and imported, charts an
    /// ask interval that rises from daily to over a week.
    @Test func checkpointSteadyAskIntervalRises() throws {
        let run = try Simulator.run(.steady(), start: start.adding(days: 1 - Scenario.steady().days))
        let url = FileManager.default.temporaryDirectory.appending(path: "steady-\(UUID().uuidString).json")
        try JSONEncoder().encode(run.log).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = try Harness().model()
        try model.importFixture(at: url)
        let habit = try #require(model.activeHabits.first)
        #expect(model.activeHabits.count == 1)
        let insights = model.insights(of: habit, filter: AdherenceFilter())
        #expect(insights.hasEnoughData)
        #expect(insights.series.count == 180)
        // Seed 42: 1, 1, 1, 1, 3, 4, 6, 7, then 7–13 days.
        #expect(insights.series.prefix(4).allSatisfy { $0.intervalDays == 1 })
        #expect(insights.series.suffix(30).allSatisfy { $0.intervalDays >= 7 })
        #expect(render(HabitCharts(insights: insights, color: .blue)) != nil)
    }

    /// §13 M9 checkpoint: 30 habits × 3 years chart in under 100 ms, data and drawing. Habit detail draws
    /// every chart at once. The Insights screen is a lazy list: opening it computes the data for every
    /// section but draws the cards, the overall charts and the first cluster; each further cluster is drawn
    /// as it scrolls in.
    @Test func checkpointChartsRenderFastForThreeYearsOfThirtyHabits() throws {
        let truth = try LargeFixture.make(habits: 30, days: 1095, endingOn: start)
        let projected = try Projection.rebuild(
            truth, clock: FixedClock(date: noon, calendar: DayCalendar(timeZone: .gmt))
        )
        let habits = truth.habits
        let filter = AdherenceFilter()
        // Warm up SwiftUI and Charts on a small dataset first: first-use costs aren't this data's.
        _ = render(HabitCharts(
            insights: HabitInsights(
                habit: habits[0], projected: projected, pauses: [], today: start.adding(days: -1000), filter: filter
            ),
            color: .blue
        ))

        // The gated middle habit of a cluster: every chart type, pause bands included.
        let detail = try measure {
            let insights = HabitInsights(
                habit: habits[1], projected: projected, pauses: truth.pauses, today: start, filter: filter
            )
            #expect(insights.series.count == 1095)
            #expect(!insights.bands.isEmpty)
            return try #require(render(HabitCharts(insights: insights, color: .blue)))
        }
        var groups: [ClusterInsights] = []
        let screen = try measure {
            let overview = Overview(truth: truth, projected: projected, today: start, filter: filter)
            groups = truth.clusters.map { cluster in
                ClusterInsights(
                    clusterID: cluster.id, members: habits.filter { $0.clusterID == cluster.id },
                    records: projected.records, today: start, filter: filter
                )
            }
            return try #require(render(VStack {
                ForEach(InsightCard.cards(overview)) { InsightCardView(card: $0, habitName: "Habit") }
                OverviewCharts(overview: overview, habits: habits)
                ClusterCharts(insights: groups[0], habits: habits)
            }))
        }
        #expect(groups.count == 5)
        #expect(groups.allSatisfy { $0.funnel.count == 3 })
        #expect(detail < .milliseconds(100), "habit detail charts took \(detail)")
        #expect(screen < .milliseconds(100), "Insights charts took \(screen)")
        for group in groups.dropFirst() {
            let section = try measure { try #require(render(ClusterCharts(insights: group, habits: habits))) }
            #expect(section < .milliseconds(100), "a cluster section took \(section)")
        }
    }

    @Test func cardsPutRegressionsFirst() {
        let regression = Overview.Regression(habitID: UUID(), recent: 0.2, prior: 0.9)
        let delayed = Overview.DelayedHabit(habitID: UUID(), delays: 4)
        let cards = [InsightCard.autonomy(9.5), .delayedOften(delayed), .regression(regression)]
        #expect(Set(cards.map(\.id)).count == 3)
        #expect(cards[2].title(habitName: "Gym") == "Gym is slipping")
        #expect(cards[2].message.contains("20%"))
        #expect(cards[2].message.contains("90%"))
        #expect(cards[1].title(habitName: "Gym") == "You keep delaying Gym")
        #expect(cards[0].title(habitName: "") == "Autonomy score: ~9.5 days")
        #expect(cards[0].habitID == nil)
        #expect(cards[1].habitID == delayed.habitID)
    }

    @Test func cardsFromOverview() throws {
        let model = try Harness().model()
        let gym = try addHabit(model, "Gym")
        for _ in 0 ..< 3 {
            try model.pause(gym.id, from: model.today, through: model.today, reason: .manual)
        }
        let cards = InsightCard.cards(model.overview(filter: AdherenceFilter()))
        #expect(cards.map(\.id) == ["delayed-\(gym.id)", "autonomy"])
    }

    @Test func clusterInsightsSkipLooseHabits() throws {
        let model = try Harness().model()
        var cluster = model.newClusterDraft()
        cluster.name = "Fitness"
        try model.save(cluster)
        var gym = try addHabit(model, "Gym")
        gym.clusterID = cluster.id
        try model.save(gym)
        _ = try addHabit(model, "Read")
        let groups = model.clusterInsights(filter: AdherenceFilter())
        #expect(groups.map(\.cluster.id) == [cluster.id])
        #expect(groups.first?.insights.memberIDs == [gym.id])
    }

    @Test func burdenAverageIsTrailingWeek() {
        let counts = (0 ..< 10).map { Overview.DayCount(day: start.adding(days: $0), count: $0 < 7 ? 7 : 0) }
        let average = QuestionsPerDayChart.weekAverage(counts)
        #expect(average.map(\.mean).prefix(7).allSatisfy { $0 == 7 })
        #expect(average.last?.mean == 4)
    }

    private func render(_ view: some View) -> CGImage? {
        let renderer = ImageRenderer(content: VStack(alignment: .leading) { view }.frame(width: 390).padding())
        return renderer.cgImage
    }

    /// The fastest of three runs: other processes (a booting simulator during `make ci`) only ever add
    /// time, so the minimum is the render's own cost.
    private func measure(_ body: () throws -> CGImage) rethrows -> Duration {
        let clock = ContinuousClock()
        var fastest = Duration.seconds(Int64.max)
        for _ in 0 ..< 3 {
            let started = clock.now
            _ = try body()
            fastest = min(fastest, clock.now - started)
        }
        return fastest
    }
}
