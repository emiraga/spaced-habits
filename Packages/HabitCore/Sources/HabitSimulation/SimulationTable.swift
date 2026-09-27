import Foundation
import HabitCore

/// Plain-text day-by-day table of a simulation, for the `simulate` executable and commit evidence.
public enum SimulationTable {
    public static func render(_ result: SimulationResult) -> String {
        var lines = ["scenario: \(result.scenario), start \(result.start), \(result.truth.first?.count ?? 0) days"]
        let habitHeader = "did ask  why        mean   sd    ivl src"
        lines.append("day  date       " + result.habits.map { "| \($0.name.padded(to: habitHeader.count)) " }.joined())
        lines.append("                " + result.habits.map { _ in "| \(habitHeader) " }.joined())
        for index in result.truth.first?.indices ?? 0 ..< 0 {
            var line = "\(String(index).padded(to: 4)) \(result.day(index)) "
            for habit in result.habits.indices {
                let ask = result.asks[habit][index]
                let model = result.live[habit][index]
                let cells = [
                    (result.truth[habit][index] ? "Y" : ".").padded(to: 3),
                    (ask.map { shape($0.question.shape) } ?? "-").padded(to: 4),
                    (ask?.reason.rawValue ?? "").padded(to: 10),
                    model.map { format($0.mean) } ?? "-",
                    model.map { format($0.standardDeviation) } ?? "-",
                    String(model?.intervalDays ?? 0).padded(to: 3),
                    result.record(habit: habit, day: index)?.source.rawValue.prefix(3).description ?? "-",
                ]
                line += "| \(cells.joined(separator: " ")) "
            }
            lines.append(line)
        }
        lines.append("")
        for (habit, value) in result.habits.enumerated() {
            let weeks = result.questionsPerWeek(habit: habit).map(String.init).joined(separator: " ")
            lines.append("\(value.name) questions/week: \(weeks)")
        }
        return lines.joined(separator: "\n")
    }

    static func shape(_ shape: QuestionShape) -> String {
        switch shape {
        case .singleDay: "1"
        case let .perDay(days): "P\(days.count)"
        case let .count(total): "C\(total)"
        }
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value).padded(to: 5)
    }
}

private extension String {
    func padded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
