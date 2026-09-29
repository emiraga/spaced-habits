import Foundation
import HabitCore

/// A question the simulated user was shown, and why.
public struct SimulatedAsk: Sendable, Hashable {
    public let question: Question
    public let reason: DueReason
}

/// Outcome of running a `Scenario` through the engine.
public struct SimulationResult: Sendable {
    public let scenario: String
    public let start: DayKey
    public let habits: [Habit]
    /// `[habit][day index]`.
    public let truth: [[Bool]]
    /// `[habit][day index]`: the question asked that day, if any.
    public let asks: [[SimulatedAsk?]]
    /// `[habit][day index]`: the model the engine held at the end of that day, after its answers. Unlike
    /// `projected.series`, later answers don't rewrite it, so it shows when the engine knew something.
    public let live: [[ModelPoint?]]
    /// Projection as of the last day, after its answers: the retrospective view of every day.
    public let projected: Projected
    /// Everything the simulated user did, as the app would have stored it: `simulate --json` exports it as
    /// a fixture (§4.8).
    public let log: Truth

    public func day(_ index: Int) -> DayKey {
        start.adding(days: index)
    }

    /// Retrospective model at the end of day `index`, including what later answers revealed.
    public func model(habit: Int, day index: Int) -> ModelPoint? {
        projected.series[habits[habit].id]?.first { $0.day == day(index) }
    }

    public func record(habit: Int, day index: Int) -> DayRecord? {
        projected.records[habits[habit].id]?[day(index)]
    }

    /// Questions asked about `habit` in each 7-day week.
    public func questionsPerWeek(habit: Int) -> [Int] {
        stride(from: 0, to: asks[habit].count, by: 7).map { weekStart in
            asks[habit][weekStart ..< min(weekStart + 7, asks[habit].count)].count { $0 != nil }
        }
    }
}

/// Runs a synthetic user day by day through the real planner and projection (DESIGN.md §4.8): each day
/// it answers up to `sessionBudget` questions truthfully, re-planning after each answer.
public enum Simulator {
    /// 2026-01-01.
    public static let defaultStart = DayKey(dayNumber: 20454)

    public static func run(
        _ scenario: Scenario,
        settings: Settings = .default,
        start: DayKey = defaultStart
    ) throws -> SimulationResult {
        let truth = scenario.drawTruth()
        let habits = try makeHabits(scenario, start: start)
        let planner = try QuestionPlanner(settings: settings)
        let calendar = try DayCalendar(timeZone: utc())
        var log = Truth(
            habits: habits,
            // Creating a habit in the app stores its first revision (§3.2).
            habitRevisions: habits.map { HabitRevision(habit: $0, editedAt: $0.createdAt) },
            pauses: makePauses(scenario, habits: habits, start: start),
            settings: settings
        )
        var asks = habits.map { _ in [SimulatedAsk?](repeating: nil, count: scenario.days) }
        var live = habits.map { _ in [ModelPoint?](repeating: nil, count: scenario.days) }
        let index = Dictionary(uniqueKeysWithValues: habits.enumerated().map { ($1.id, $0) })

        for dayIndex in 0 ..< scenario.days {
            let today = start.adding(days: dayIndex)
            let clock = try FixedClock(
                date: calendar.date(today, at: TimeOfDay(hour: scenario.sessionHour, minute: 0)), calendar: calendar
            )
            let unavailable = try Pauses.unavailable(habits: habits, pauses: log.pauses, clock: clock)
            // Like the app, build each question only when it is presented: re-plan after every answer, so a
            // child's card sees its parent's answer from earlier in the same session.
            var projected = try Projection.rebuild(log, clock: clock)
            for offset in 0 ..< settings.sessionBudget {
                let plan = try planner.session(
                    habits: habits,
                    states: projected.states,
                    records: projected.records,
                    unavailable: unavailable,
                    clock: clock
                )
                guard let question = plan.questions.first, let due = plan.presented.first,
                      let habit = index[question.habitID]
                else { break }
                asks[habit][dayIndex] = SimulatedAsk(question: question, reason: due.reason)
                let value = answer(question, habit: habit, truth: truth, start: start)
                let now = clock.now().addingTimeInterval(TimeInterval(offset))
                var presented = question
                presented.presentedAt = now
                log.questions.append(presented)
                log.answers.append(makeAnswer(question, value, at: now))
                projected = try Projection.rebuild(log, clock: clock)
            }
            for (habit, value) in habits.enumerated() {
                live[habit][dayIndex] = projected.series[value.id]?.last
            }
        }
        let lastDay = start.adding(days: scenario.days - 1)
        let projected = try Projection.rebuild(log, clock: FixedClock(date: noon(of: lastDay), calendar: calendar))
        return SimulationResult(
            scenario: scenario.name, start: start, habits: habits, truth: truth, asks: asks, live: live,
            projected: projected, log: log
        )
    }

    /// The truthful answer. For a gated `count`, the user counts days they did both, capped at the total.
    static func answer(_ question: Question, habit: Int, truth: [[Bool]], start: DayKey) -> AnswerValue {
        func did(_ day: DayKey) -> Bool {
            truth[habit][start.days(to: day)]
        }
        switch question.shape {
        case .singleDay:
            return did(question.covers.upperBound) ? .done : .notDone
        case let .perDay(days):
            return .perDay(Dictionary(uniqueKeysWithValues: days.map { ($0, did($0)) }))
        case let .count(total):
            // A child is only ever done on parent-done days, so counting its days counts "both".
            let done = question.covers.count { did($0) }
            return .count(done: min(done, total), total: total)
        }
    }

    private static func makeAnswer(_ question: Question, _ value: AnswerValue, at date: Date) -> Answer {
        Answer(
            questionID: question.id,
            habitID: question.habitID,
            covers: question.covers,
            value: value,
            answeredAt: date,
            timezone: "UTC",
            channel: .app
        )
    }

    private static func makePauses(_ scenario: Scenario, habits: [Habit], start: DayKey) -> [PauseEvent] {
        scenario.pauses.map { spec in
            PauseEvent(
                habitIDs: [habits[spec.habit].id],
                start: start.adding(days: spec.days.lowerBound),
                end: start.adding(days: spec.days.upperBound),
                reason: .vacation,
                createdAt: noon(of: start)
            )
        }
    }

    /// Habit IDs come from the seed: spot checks and ranking ties depend on them, so runs must not vary.
    private static func makeHabits(_ scenario: Scenario, start: DayKey) throws -> [Habit] {
        var random = SeededRandomSource(seed: ~scenario.seed)
        let habits = scenario.habits.map { spec in
            Habit(
                id: seededID(&random),
                name: spec.name,
                colorHex: "#3366CC",
                createdAt: noon(of: start),
                createdDay: start,
                dueTime: spec.dueTime
            )
        }
        return try habits.enumerated().map { index, habit in
            var habit = habit
            if let parent = scenario.habits[index].parent {
                habit.dependencies = [Dependency(parentID: habits[parent].id)]
            }
            try habit.validate()
            return habit
        }
    }

    static func seededID(_ random: inout SeededRandomSource) -> UUID {
        let (high, low) = (random.next(), random.next())
        let bytes = (0 ..< 16).map { UInt8(truncatingIfNeeded: ($0 < 8 ? high : low) >> (8 * UInt64(7 - $0 % 8))) }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    public static func noon(of day: DayKey) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day.dayNumber) * 86400 + 12 * 3600)
    }

    private static func utc() throws -> TimeZone {
        guard let zone = TimeZone(identifier: "UTC") else { throw SimulationError.missingTimeZone("UTC") }
        return zone
    }
}

public enum SimulationError: Error, Equatable {
    case missingTimeZone(String)
}
