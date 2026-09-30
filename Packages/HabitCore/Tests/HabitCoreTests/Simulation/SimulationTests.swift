import Foundation
import HabitCore
import HabitSimulation
import Testing

/// The engine's acceptance tests (DESIGN.md §4.8): synthetic users, 180 days, seeded.
struct SimulationTests {
    /// Full weeks only: the 180-day run ends in a partial week.
    private func fullWeeks(_ result: SimulationResult, habit: Int) -> [Int] {
        Array(result.questionsPerWeek(habit: habit).prefix(result.truth[habit].count / 7))
    }

    /// From week 4 on, every 4-week window averages under 1.5 questions a week.
    private func expectRarelyAsked(_ result: SimulationResult, sourceLocation: SourceLocation = #_sourceLocation) {
        let weeks = fullWeeks(result, habit: 0)
        for start in 3 ... weeks.count - 4 {
            let window = weeks[start ..< start + 4]
            #expect(
                Double(window.reduce(0, +)) / 4 < 1.5, "weeks \(start + 1)–\(start + 4): \(Array(window))",
                sourceLocation: sourceLocation
            )
        }
    }

    @Test func steadyUserIsAskedLessAndInferredWell() throws {
        let result = try Simulator.run(.steady(probability: 0.95))
        expectRarelyAsked(result)
        // Inferred days: the average inferred value is within 0.15 of the true rate on those days.
        let inferred = result.truth[0].indices.compactMap { index -> (Double, Double)? in
            guard let record = result.record(habit: 0, day: index), record.source == .inferred else { return nil }
            return (record.value, result.truth[0][index] ? 1 : 0)
        }
        #expect(inferred.count >= 30)
        let meanInferred = inferred.map(\.0).reduce(0, +) / Double(inferred.count)
        let meanTruth = inferred.map(\.1).reduce(0, +) / Double(inferred.count)
        #expect(abs(meanInferred - meanTruth) < 0.15)
    }

    /// Morning sessions before a 20:00 due time only ever ask about days through yesterday (§4.2).
    @Test func steadyUserWithAnEveningDueTimeIsAskedAboutPastDays() throws {
        let result = try Simulator.run(.steady(
            probability: 0.95,
            dueTime: TimeOfDay(hour: 20, minute: 0),
            sessionHour: 8
        ))
        let asks = result.asks[0].enumerated().compactMap { index, ask in ask.map { (index, $0) } }
        #expect(!asks.isEmpty)
        for (index, ask) in asks {
            #expect(ask.question.covers.upperBound == result.day(index - 1), "day \(index)")
        }
        #expect(result.asks[0][0] == nil)
        expectRarelyAsked(result)
    }

    /// Not "every week": a long lucky streak (seed 42: 14 yeses, days 133–146) lifts the mean above
    /// target and legitimately earns a break, until the next check-in finds the truth (§4.8).
    @Test func flakyUserIsAskedAlmostDaily() throws {
        let result = try Simulator.run(.flaky(probability: 0.5))
        let asked = result.asks[0].map { $0 != nil }
        #expect(Double(asked.count { $0 }) / Double(asked.count) >= 0.8, "\(fullWeeks(result, habit: 0))")
        let longestSilence = asked.split(separator: true).map(\.count).max() ?? 0
        #expect(longestSilence <= Settings.default.maxIntervalDays)
    }

    @Test func collapseIsDetectedWithinTenDays() throws {
        let result = try Simulator.run(.collapsing(before: 0.95, after: 0.1, collapseDay: 60))
        // Rule 2 as the planner applied it: the first day asked because the day before ended below target.
        let asked = try #require((60 ..< 180).first { result.asks[0][$0]?.reason == .belowTarget })
        let detected = asked - 1
        #expect(detected - 60 <= 10, "detected on day \(detected)")
    }

    @Test func vacationFreezesStateAndReentersOnce() throws {
        let pause = 60 ... 73
        let result = try Simulator.run(.vacation(probability: 0.9, pause: pause))
        #expect(pause.allSatisfy { result.asks[0][$0] == nil })
        let frozen = try #require(result.live[0][pause.lowerBound - 1])
        for day in pause {
            let point = try #require(result.live[0][day])
            #expect(point.mean == frozen.mean && point.standardDeviation == frozen.standardDeviation, "day \(day)")
        }
        let reentries = result.asks[0].indices.filter { result.asks[0][$0]?.reason == .reentry }
        #expect(reentries == [pause.upperBound + 1])
        let reentry = try #require(result.asks[0][pause.upperBound + 1])
        #expect(reentry.question.covers.lowerBound == result.day(pause.upperBound + 1))
    }

    @Test func dependentIsAskedOnlyWhenParentHappenedAndLearnsConditional() throws {
        let result = try Simulator.run(.dependentPair(parent: 0.9, childGivenParent: 0.8))
        var childQuestions = 0
        for (index, ask) in result.asks[1].enumerated() {
            guard let ask else { continue }
            childQuestions += 1
            #expect(ask.question.parentContext != nil)
            let parentDone = ask.question.covers.contains { result.truth[0][result.start.days(to: $0)] }
            #expect(parentDone, "asked about the child on day \(index) though the parent never happened")
        }
        #expect(childQuestions > 0)
        // Estimated P(child | parent) over the first 60 days: evidence days that are not excluded.
        let evidence = (0 ..< 60).compactMap { result.record(habit: 1, day: $0) }
            .filter { $0.source.feedsModel && !$0.conditionalDenominatorExcluded }
        #expect(evidence.count >= 20)
        let estimate = evidence.map(\.value).reduce(0, +) / Double(evidence.count)
        #expect(abs(estimate - 0.8) < 0.1, "estimated P(child | parent) = \(estimate)")
    }

    /// Question and answer IDs are random, so compare everything that doesn't carry them.
    @Test func runsAreReproducible() throws {
        let first = try Simulator.run(.dependentPair())
        let second = try Simulator.run(.dependentPair())
        #expect(first.habits == second.habits)
        #expect(first.live == second.live)
        #expect(first.projected.series == second.projected.series)
        #expect(first.projected.states == second.projected.states)
        #expect(SimulationTable.render(first) == SimulationTable.render(second))
    }
}
