import Foundation

/// The Insights screen's overall charts and cards (DESIGN.md §12, overall), across active habits.
public struct Overview: Sendable, Hashable {
    public struct DayCount: Sendable, Hashable {
        public let day: DayKey
        public let count: Int

        public init(day: DayKey, count: Int) {
            self.day = day
            self.count = count
        }
    }

    /// A habit whose recent adherence dropped (`Overview.regressionDrop`).
    public struct Regression: Sendable, Hashable {
        public let habitID: UUID
        public let recent: Double
        public let prior: Double

        public init(habitID: UUID, recent: Double, prior: Double) {
            self.habitID = habitID
            self.recent = recent
            self.prior = prior
        }
    }

    /// A habit the user keeps delaying (§4.6), with its delays in the last `Pauses.frequentDelayWindowDays`.
    public struct DelayedHabit: Sendable, Hashable {
        public let habitID: UUID
        public let delays: Int

        public init(habitID: UUID, delays: Int) {
            self.habitID = habitID
            self.delays = delays
        }
    }

    /// Adherence on one weekday; `habitID` nil is every habit together.
    public struct WeekdayCell: Sendable, Hashable {
        public let habitID: UUID?
        /// ISO: 1 is Monday.
        public let weekday: Int
        public let mean: Double
        public let days: Int

        public init(habitID: UUID?, weekday: Int, mean: Double, days: Int) {
            self.habitID = habitID
            self.weekday = weekday
            self.mean = mean
            self.days = days
        }
    }

    public static let burdenDays = 90
    public static let regressionRecentDays = 14
    public static let regressionPriorDays = 30
    public static let regressionDrop = 0.2
    /// Each window needs this many counted days before a drop means anything.
    public static let regressionMinimumDays = 3

    /// Habits asked about per day over the last `burdenDays` days, zero-filled (§12 "questions per day").
    public let questionsPerDay: [DayCount]
    /// Vacations overlapping the burden window, clipped to it.
    public let vacations: [ClosedRange<DayKey>]
    /// Mean ask interval across active habits, in days. Nil with no habits.
    public let autonomyScore: Double?
    public let regressions: [Regression]
    /// Habits delayed at least `Pauses.frequentDelayThreshold` times recently, and how often.
    public let delayedOften: [DelayedHabit]
    public let weekdays: [WeekdayCell]
    /// Days since the first active habit was created, minus days every habit was away. Charts need
    /// `Insights.minimumChartDays`.
    public let availableDays: Int

    public var hasEnoughData: Bool {
        availableDays >= Insights.minimumChartDays
    }

    public init(truth: Truth, projected: Projected, today: DayKey, filter: AdherenceFilter) {
        let habits = truth.habits.filter { !$0.isArchived }
        let ids = Set(habits.map(\.id))
        let window = today.adding(days: 1 - Self.burdenDays) ... today
        questionsPerDay = Self.questionsPerDay(truth: truth, habitIDs: ids, window: window)
        vacations = Self.vacations(truth.pauses, clippedTo: window)
        let intervals = habits.compactMap { projected.states[$0.id]?.currentIntervalDays }
        autonomyScore = intervals.isEmpty ? nil : Double(intervals.reduce(0, +)) / Double(intervals.count)
        regressions = habits.compactMap { habit in
            Self.regression(habit.id, records: projected.records[habit.id] ?? [:], today: today, filter: filter)
        }
        let recentDelays = Pauses.delayCounts(
            pauses: truth.pauses, startingIn: today.adding(days: 1 - Pauses.frequentDelayWindowDays) ... today
        )
        delayedOften = habits.compactMap { habit in
            recentDelays[habit.id].flatMap {
                $0 >= Pauses.frequentDelayThreshold ? DelayedHabit(habitID: habit.id, delays: $0) : nil
            }
        }
        weekdays = Self.weekdays(habits: habits, records: projected.records, filter: filter)
        availableDays = Self.availableDays(habits: habits, records: projected.records)
    }

    /// Distinct (habit, day) pairs across logged questions and answers. Widget and Siri answers log no
    /// question, and a card shown again after "Later" logs a second one, so neither is counted alone. A
    /// question's `covers` end on the day it was asked (§4.7).
    static func questionsPerDay(truth: Truth, habitIDs: Set<UUID>, window: ClosedRange<DayKey>) -> [DayCount] {
        struct Asked: Hashable {
            let habitID: UUID
            let day: DayKey
        }
        var asked = Set<Asked>()
        for question in truth.questions where window.contains(question.covers.upperBound) {
            asked.insert(Asked(habitID: question.habitID, day: question.covers.upperBound))
        }
        for answer in truth.answers where window.contains(answer.covers.upperBound) {
            asked.insert(Asked(habitID: answer.habitID, day: answer.covers.upperBound))
        }
        asked = asked.filter { habitIDs.contains($0.habitID) }
        var counts: [DayKey: Int] = [:]
        for ask in asked {
            counts[ask.day, default: 0] += 1
        }
        return window.map { DayCount(day: $0, count: counts[$0] ?? 0) }
    }

    static func vacations(_ pauses: [PauseEvent], clippedTo window: ClosedRange<DayKey>) -> [ClosedRange<DayKey>] {
        let ranges = pauses
            .filter { $0.reason == .vacation && !$0.isCancelled && $0.start <= window.upperBound }
            .filter { $0.end >= window.lowerBound }
            .map { max($0.start, window.lowerBound) ... min($0.end, window.upperBound) }
            .sorted { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<DayKey>] = []
        for range in ranges {
            if let last = merged.last, range.lowerBound <= last.upperBound.adding(days: 1) {
                merged[merged.count - 1] = last.lowerBound ... max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// The last `regressionRecentDays` days against the `regressionPriorDays` before them.
    static func regression(
        _ habitID: UUID,
        records: [DayKey: DayRecord],
        today: DayKey,
        filter: AdherenceFilter
    ) -> Regression? {
        func mean(_ days: ClosedRange<DayKey>) -> Double? {
            filter.mean(of: days.compactMap { records[$0] })
                .flatMap { $0.days >= regressionMinimumDays ? $0.mean : nil }
        }
        let recentStart = today.adding(days: 1 - regressionRecentDays)
        let priorStart = recentStart.adding(days: -regressionPriorDays)
        guard let recent = mean(recentStart ... today), let prior = mean(priorStart ... recentStart.adding(days: -1)),
              prior - recent >= regressionDrop - 1e-9
        else { return nil }
        return Regression(habitID: habitID, recent: recent, prior: prior)
    }

    /// Per habit and for all habits together, every weekday that has a day that counts.
    static func weekdays(habits: [Habit], records: DayRecords, filter: AdherenceFilter) -> [WeekdayCell] {
        // Indexed by ISO weekday; 0 is unused.
        var all = [(sum: Double, days: Int)](repeating: (0, 0), count: 8)
        var result: [WeekdayCell] = []
        func cells(_ totals: [(sum: Double, days: Int)], habitID: UUID?) -> [WeekdayCell] {
            (1 ... 7).compactMap { weekday in
                let total = totals[weekday]
                return total.days == 0 ? nil : WeekdayCell(
                    habitID: habitID, weekday: weekday, mean: total.sum / Double(total.days), days: total.days
                )
            }
        }
        for habit in habits {
            var byWeekday = [(sum: Double, days: Int)](repeating: (0, 0), count: 8)
            for record in (records[habit.id] ?? [:]).values {
                guard let value = filter.value(of: record) else { continue }
                let weekday = record.day.weekday
                byWeekday[weekday].sum += value
                byWeekday[weekday].days += 1
                all[weekday].sum += value
                all[weekday].days += 1
            }
            result += cells(byWeekday, habitID: habit.id)
        }
        return result + cells(all, habitID: nil)
    }

    /// Days on which at least one of `habits` was neither paused nor blocked.
    static func availableDays(habits: [Habit], records: DayRecords) -> Int {
        let byHabit = habits.compactMap { records[$0.id] }
        guard let first = byHabit.compactMap({ $0.keys.min() }).min(),
              let last = byHabit.compactMap({ $0.keys.max() }).max()
        else { return 0 }
        var available = [Bool](repeating: false, count: first.days(to: last) + 1)
        for records in byHabit {
            for record in records.values where Insights.unavailability(record) == nil {
                available[first.days(to: record.day)] = true
            }
        }
        return available.count { $0 }
    }
}
