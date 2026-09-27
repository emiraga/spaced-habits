import Charts
import HabitCore
import SwiftUI

/// An insight card on the Insights screen (§5.1 screen 6): delayed often, a regression, the autonomy score.
public enum InsightCard: Hashable, Identifiable {
    case regression(Overview.Regression)
    case delayedOften(Overview.DelayedHabit)
    case autonomy(Double)

    /// Regressions first, then habits delayed often, then the autonomy score.
    public static func cards(_ overview: Overview) -> [InsightCard] {
        overview.regressions.map(InsightCard.regression) + overview.delayedOften.map(InsightCard.delayedOften)
            + (overview.autonomyScore.map { [.autonomy($0)] } ?? [])
    }

    public var id: String {
        switch self {
        case let .regression(regression): "regression-\(regression.habitID)"
        case let .delayedOften(delayed): "delayed-\(delayed.habitID)"
        case .autonomy: "autonomy"
        }
    }

    /// The habit the card is about, if any.
    public var habitID: UUID? {
        switch self {
        case let .regression(regression): regression.habitID
        case let .delayedOften(delayed): delayed.habitID
        case .autonomy: nil
        }
    }

    public func title(habitName: String) -> String {
        switch self {
        case .regression: "\(habitName) is slipping"
        case .delayedOften: "You keep delaying \(habitName)"
        case let .autonomy(days): "Autonomy score: ~\(Self.days(days))"
        }
    }

    public var message: String {
        switch self {
        case let .regression(regression):
            "Done on \(DayFormat.percent(regression.recent)) of answered days in the last "
                + "\(Overview.regressionRecentDays) days, down from \(DayFormat.percent(regression.prior)) "
                + "in the \(Overview.regressionPriorDays) days before."
        case let .delayedOften(delayed):
            "Delayed \(delayed.delays) times in the last \(Pauses.frequentDelayWindowDays) days. "
                + "A lower target or a longer pause might fit better."
        case .autonomy:
            "On average, each habit is asked about this often. The longer the gap, the more automatic your habits."
        }
    }

    public var systemImage: String {
        switch self {
        case .regression: "chart.line.downtrend.xyaxis"
        case .delayedOften: "clock.arrow.circlepath"
        case .autonomy: "leaf"
        }
    }

    static func days(_ value: Double) -> String {
        let rounded = value.formatted(.number.precision(.fractionLength(0 ... 1)))
        return value == 1 ? "1 day" : "\(rounded) days"
    }
}

public struct InsightCardView: View {
    let card: InsightCard
    let habitName: String

    public init(card: InsightCard, habitName: String) {
        self.card = card
        self.habitName = habitName
    }

    public var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title(habitName: habitName))
                    .font(.headline)
                Text(card.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: card.systemImage)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Habits asked about per day over 90 days (§12): the app's burden, which should trend down.
public struct QuestionsPerDayChart: View {
    let overview: Overview

    public init(overview: Overview) {
        self.overview = overview
    }

    public var body: some View {
        let average = Self.weekAverage(overview.questionsPerDay)
        ChartCard(title: "Questions per day") {
            Chart {
                ForEach(overview.vacations, id: \.lowerBound) { range in
                    RectangleMark(
                        xStart: .value("From", ChartDay.start(range.lowerBound)),
                        xEnd: .value("Through", ChartDay.end(range.upperBound))
                    )
                    .foregroundStyle(BandStyle.vacation)
                }
                ForEach(overview.questionsPerDay, id: \.day) { day in
                    BarMark(x: .value("Day", ChartDay.date(day.day), unit: .day), y: .value("Asked", day.count))
                        .foregroundStyle(Color.accentColor.opacity(0.3))
                }
                ForEach(average, id: \.day) { point in
                    LineMark(x: .value("Day", ChartDay.date(point.day)), y: .value("7-day average", point.mean))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .dayAxis()
            .frame(height: 160)
            .accessibilityLabel(
                "Questions per day, 7-day average: \(average.first.map { Self.format($0.mean) } ?? "0") "
                    + "\(Overview.burdenDays) days ago, \(average.last.map { Self.format($0.mean) } ?? "0") now"
            )
        } legend: {
            VStack(alignment: .leading, spacing: 4) {
                LegendRow(items: [
                    LegendItem("Per day", band: Color.accentColor.opacity(0.3)),
                    LegendItem("7-day average", color: .accentColor),
                    LegendItem("Vacation", band: BandStyle.vacation),
                ])
                Text("Habits asked about, from shown cards and all answers (widget, watch, Siri included).")
            }
        }
    }

    static func weekAverage(_ counts: [Overview.DayCount]) -> [(day: DayKey, mean: Double)] {
        counts.indices.map { index in
            let window = counts[max(0, index - 6) ... index]
            return (counts[index].day, Double(window.map(\.count).reduce(0, +)) / Double(window.count))
        }
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

/// Adherence by weekday, per habit and for all habits together (§12).
public struct WeekdayHeatmapChart: View {
    let overview: Overview
    let habits: [Habit]

    private static let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private static let allHabits = "All habits"

    public init(overview: Overview, habits: [Habit]) {
        self.overview = overview
        self.habits = habits
    }

    public var body: some View {
        let names = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0.name) })
        let rows = [Self.allHabits] + habits.map(\.name)
        ChartCard(title: "By day of the week") {
            Chart(overview.weekdays, id: \.self) { cell in
                RectangleMark(
                    x: .value("Weekday", Self.weekdayNames[cell.weekday - 1]),
                    y: .value("Habit", cell.habitID.flatMap { names[$0] } ?? Self.allHabits),
                    width: .ratio(0.92),
                    height: .ratio(0.85)
                )
                .foregroundStyle(Color.accentColor.opacity(0.1 + 0.9 * cell.mean))
            }
            .chartXScale(domain: Self.weekdayNames)
            .chartYScale(domain: rows)
            .chartYAxis {
                AxisMarks(preset: .extended, position: .leading) { _ in AxisValueLabel(centered: true) }
            }
            .frame(height: CGFloat(rows.count) * 24 + 30)
        } legend: {
            LegendRow(items: [
                LegendItem("Rarely", band: Color.accentColor.opacity(0.1)),
                LegendItem("Always done", band: Color.accentColor),
            ] + [LegendItem("Answered days only", swatch: EmptyView())])
        }
    }
}

/// The overall charts on the Insights screen (§12), or why there are none yet.
public struct OverviewCharts: View {
    let overview: Overview
    let habits: [Habit]

    public init(overview: Overview, habits: [Habit]) {
        self.overview = overview
        self.habits = habits
    }

    public var body: some View {
        if overview.hasEnoughData {
            QuestionsPerDayChart(overview: overview)
            WeekdayHeatmapChart(overview: overview, habits: habits)
        } else {
            NotEnoughData(availableDays: overview.availableDays)
        }
    }
}
