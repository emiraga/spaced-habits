import Foundation
import HabitCore

/// A generated long history for performance checks (DESIGN.md §13 M9: charts for 3 years × 30 habits).
/// Cheaper than `Simulator`, which re-plans every day: each habit is answered every third day with a
/// count, clusters of six hold a three-habit gate chain, there is a two-week vacation each year and a few
/// manual delays. Deterministic for a seed.
public enum LargeFixture {
    public static func make(
        habits count: Int = 30,
        days: Int = 1095,
        endingOn end: DayKey,
        seed: UInt64 = 7
    ) throws -> Truth {
        var random = SeededRandomSource(seed: seed)
        let start = end.adding(days: 1 - days)
        let createdAt = Simulator.noon(of: start)
        let clusters = (0 ..< (count + 5) / 6).map { index in
            Cluster(id: Simulator.seededID(&random), name: "Cluster \(index + 1)", colorHex: "#109618")
        }
        var habits: [Habit] = []
        for index in 0 ..< count {
            let position = index % 6
            habits.append(Habit(
                id: Simulator.seededID(&random),
                name: "Habit \(index + 1)",
                colorHex: "#3366CC",
                createdAt: createdAt,
                createdDay: start,
                // Habits 2 and 3 of each cluster gate on the one before: Gym → Shake → Stretch.
                dependencies: (1 ... 2).contains(position) ? [Dependency(parentID: habits[index - 1].id)] : [],
                clusterID: clusters[index / 6].id
            ))
        }
        var truth = Truth(habits: habits, clusters: clusters)
        for (index, habit) in habits.enumerated() {
            appendHistory(of: habit, index: index, days: start ... end, to: &truth, random: &random)
        }
        for first in stride(from: start.adding(days: 200), through: end, by: 365) {
            truth.pauses.append(PauseEvent(
                id: Simulator.seededID(&random), habitIDs: habits.map(\.id), start: first, end: first.adding(days: 13),
                reason: .vacation, createdAt: Simulator.noon(of: first)
            ))
        }
        try truth.validate()
        return truth
    }

    /// A count every third day covering the three days before; manual delays for every fifth habit.
    private static func appendHistory(
        of habit: Habit,
        index: Int,
        days: ClosedRange<DayKey>,
        to truth: inout Truth,
        random: inout SeededRandomSource
    ) {
        let probability = 0.35 + 0.6 * Double(index % 7) / 6
        for last in stride(from: days.lowerBound.adding(days: 2), through: days.upperBound, by: 3) {
            let covers = last.adding(days: -2) ... last
            let done = covers.count { _ in random.bernoulli(probability) }
            let date = Simulator.noon(of: last)
            let question = Question(
                id: Simulator.seededID(&random), habitID: habit.id, covers: covers, shape: .count(total: 3),
                createdAt: date, presentedAt: date
            )
            truth.questions.append(question)
            truth.answers.append(Answer(
                id: Simulator.seededID(&random), questionID: question.id, habitID: habit.id, covers: covers,
                value: .count(done: done, total: 3), answeredAt: date, timezone: "UTC", channel: .app
            ))
        }
        guard index % 5 == 0 else { return }
        for first in stride(from: days.lowerBound.adding(days: 40), through: days.upperBound, by: 90) {
            truth.pauses.append(PauseEvent(
                id: Simulator.seededID(&random), habitIDs: [habit.id], start: first, end: first.adding(days: 2),
                reason: .manual, createdAt: Simulator.noon(of: first)
            ))
        }
    }
}
