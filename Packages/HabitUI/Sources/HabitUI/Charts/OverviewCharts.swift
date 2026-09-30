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
        case .regression: String(localized: "\(habitName) is slipping", bundle: .module)
        case .delayedOften: String(localized: "You keep delaying \(habitName)", bundle: .module)
        case let .autonomy(days): String(localized: "Autonomy score: ~\(Self.days(days))", bundle: .module)
        }
    }

    public var message: String {
        switch self {
        case let .regression(regression):
            String(
                localized: "Done on \(DayFormat.percent(regression.recent)) of answered days in the last \(Overview.regressionRecentDays) days, down from \(DayFormat.percent(regression.prior)) in the \(Overview.regressionPriorDays) days before.",
                bundle: .module
            )
        case let .delayedOften(delayed):
            String(
                localized: "Delayed \(delayed.delays) times in the last \(Pauses.frequentDelayWindowDays) days. Fewer days a week or a longer pause might fit better.",
                bundle: .module
            )
        case .autonomy:
            String(
                localized: "On average, each habit is asked about this often. The longer the gap, the more automatic your habits.",
                bundle: .module
            )
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
        return value == 1 ? String(localized: "1 day", bundle: .module) : String(
            localized: "\(rounded) days",
            bundle: .module
        )
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
        ChartCard(title: String(localized: "Questions per day", bundle: .module)) {
            Chart {
                ForEach(overview.vacations, id: \.lowerBound) { range in
                    RectangleMark(
                        xStart: .value(ChartLabel.from, ChartDay.start(range.lowerBound)),
                        xEnd: .value(ChartLabel.through, ChartDay.end(range.upperBound))
                    )
                    .foregroundStyle(BandStyle.vacation)
                }
                ForEach(overview.questionsPerDay, id: \.day) { day in
                    BarMark(
                        x: .value(ChartLabel.day, ChartDay.date(day.day), unit: .day),
                        y: .value(String(localized: "Asked", bundle: .module), day.count)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.3))
                }
                ForEach(average, id: \.day) { point in
                    LineMark(
                        x: .value(ChartLabel.day, ChartDay.date(point.day)),
                        y: .value(Self.weekAverageLabel, point.mean)
                    )
                    .foregroundStyle(Color.accentColor)
                }
            }
            .dayAxis()
            .frame(height: 160)
            .accessibilityLabel(Self.summary(average))
        } legend: {
            VStack(alignment: .leading, spacing: 4) {
                LegendRow(items: [
                    LegendItem(String(localized: "Per day", bundle: .module), band: Color.accentColor.opacity(0.3)),
                    LegendItem(Self.weekAverageLabel, color: .accentColor),
                    LegendItem(String(localized: "Vacation", bundle: .module), band: BandStyle.vacation),
                ])
                Text(
                    "Habits asked about, from shown cards and all answers (widget, watch, Siri included).",
                    bundle: .module
                )
            }
        }
    }

    static func weekAverage(_ counts: [Overview.DayCount]) -> [(day: DayKey, mean: Double)] {
        counts.indices.map { index in
            let window = counts[max(0, index - 6) ... index]
            return (counts[index].day, Double(window.map(\.count).reduce(0, +)) / Double(window.count))
        }
    }

    private static let weekAverageLabel = String(localized: "7-day average", bundle: .module)

    /// "Questions per day, 7-day average: 3.1 90 days ago, 0.9 now".
    nonisolated static func summary(_ average: [(day: DayKey, mean: Double)]) -> String {
        let then = format(average.first?.mean ?? 0)
        let now = format(average.last?.mean ?? 0)
        return String(
            localized: "Questions per day, 7-day average: \(then) \(Overview.burdenDays) days ago, \(now) now",
            bundle: .module
        )
    }

    private nonisolated static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

/// Adherence by weekday, per habit and for all habits together (§12).
public struct WeekdayHeatmapChart: View {
    let overview: Overview
    let habits: [Habit]

    /// "Mon" … "Sun", as `Overview` numbers weekdays; day 4 (1970-01-05) was a Monday.
    nonisolated static let weekdayNames = (4 ..< 11).map { dayNumber in
        DayFormat.noonUTC(DayKey(dayNumber: dayNumber))
            .formatted(Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated))
    }

    private static let allHabits = String(localized: "All habits", bundle: .module)

    public init(overview: Overview, habits: [Habit]) {
        self.overview = overview
        self.habits = habits
    }

    public var body: some View {
        let names = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0.name) })
        let rows = [Self.allHabits] + habits.map(\.name)
        ChartCard(title: String(localized: "By day of the week", bundle: .module)) {
            Chart(overview.weekdays, id: \.self) { cell in
                RectangleMark(
                    x: .value(ChartLabel.weekday, Self.weekdayNames[cell.weekday - 1]),
                    y: .value(ChartLabel.habit, cell.habitID.flatMap { names[$0] } ?? Self.allHabits),
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
            .accessibilityLabel(Self.summary(overview.weekdays))
        } legend: {
            LegendRow(items: [
                LegendItem(String(localized: "Rarely", bundle: .module), band: Color.accentColor.opacity(0.1)),
                LegendItem(String(localized: "Always done", bundle: .module), band: Color.accentColor),
            ] + [LegendItem(String(localized: "Answered days only", bundle: .module), swatch: EmptyView())])
        }
    }
}

extension WeekdayHeatmapChart {
    /// "All habits: best on Mon (90%), worst on Sat (40%)", from the "All habits" row.
    nonisolated static func summary(_ cells: [Overview.WeekdayCell]) -> String {
        let all = cells.filter { $0.habitID == nil && $0.days > 0 }
        guard let best = all.max(by: { $0.mean < $1.mean }), let worst = all.min(by: { $0.mean < $1.mean }) else {
            return String(localized: "No data", bundle: .module)
        }
        return String(
            localized: "All habits: best on \(weekdayNames[best.weekday - 1]) (\(DayFormat.percent(best.mean))), worst on \(weekdayNames[worst.weekday - 1]) (\(DayFormat.percent(worst.mean)))",
            bundle: .module
        )
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
