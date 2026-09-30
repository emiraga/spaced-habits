import Charts
import HabitCore
import SwiftUI

/// Days between check-ins over time: the signature chart (§12). Rising means the habit is becoming
/// automatic.
public struct AskIntervalChart: View {
    let insights: HabitInsights
    let color: Color

    public init(insights: HabitInsights, color: Color) {
        self.insights = insights
        self.color = color
    }

    public var body: some View {
        ChartCard(title: String(localized: "Days between check-ins", bundle: .module)) {
            Chart {
                BandMarks(bands: insights.bands)
                ForEach(insights.series, id: \.day) { point in
                    LineMark(
                        x: .value(ChartLabel.day, ChartDay.date(point.day)),
                        y: .value(ChartLabel.days, point.intervalDays)
                    )
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(color)
                }
            }
            .dayAxis()
            .chartXScale(domain: insights.domain)
            .frame(height: 160)
            .accessibilityLabel(Self.summary(insights.series))
        } legend: {
            LegendRow(items: [
                LegendItem(
                    String(localized: "Ask interval, from the model after each day", bundle: .module),
                    color: color
                ),
            ] + bandLegend(insights))
        }
    }

    /// "Days between check-ins: 1 at first, 11 now, at most 12".
    nonisolated static func summary(_ series: [ModelPoint]) -> String {
        guard let first = series.first, let last = series.last else {
            return String(localized: "No data", bundle: .module)
        }
        let most = series.map(\.intervalDays).max() ?? last.intervalDays
        return String(
            localized: "Days between check-ins: \(first.intervalDays) at first, \(last.intervalDays) now, at most \(most)",
            bundle: .module
        )
    }
}

/// Rolling 7- and 30-day adherence against the target (§12). Answered days only.
public struct AdherenceChart: View {
    let insights: HabitInsights
    let color: Color

    public init(insights: HabitInsights, color: Color) {
        self.insights = insights
        self.color = color
    }

    public var body: some View {
        ChartCard(title: ChartLabel.adherence) {
            Chart {
                BandMarks(bands: insights.bands)
                line(insights.rolling30, name: Self.days30, dashed: false)
                line(insights.rolling7, name: Self.days7, dashed: true)
                RuleMark(y: .value(ChartLabel.target, insights.target))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            .dayAxis()
            .percentAxis()
            .chartXScale(domain: insights.domain)
            .frame(height: 160)
            .accessibilityLabel(
                Self.summary(month: insights.rolling30, week: insights.rolling7, target: insights.target)
            )
        } legend: {
            VStack(alignment: .leading, spacing: 4) {
                LegendRow(items: [
                    LegendItem(Self.days30, color: color),
                    LegendItem(Self.days7, color: color.opacity(0.6), dashed: true),
                    LegendItem(ChartLabel.target, color: .secondary, dashed: true),
                ] + bandLegend(insights))
                Text("From answered days: yes/no, counts and Health. Estimated days are left out.", bundle: .module)
            }
        }
    }

    /// "Adherence now: 30 days 82%, 7 days 70%. Goal: 6 days a week".
    nonisolated static func summary(month: [AdherencePoint], week: [AdherencePoint], target: Double) -> String {
        let target = DayFormat.target(target)
        guard let month = month.last, let week = week.last else {
            return String(localized: "Adherence: no answered days yet. Goal: \(target)", bundle: .module)
        }
        return String(
            localized: "Adherence now: 30 days \(DayFormat.percent(month.mean)), 7 days \(DayFormat.percent(week.mean)). Goal: \(target)",
            bundle: .module
        )
    }

    private static let days30 = String(localized: "30 days", bundle: .module)
    private static let days7 = String(localized: "7 days", bundle: .module)

    private func line(_ points: [AdherencePoint], name: String, dashed: Bool) -> some ChartContent {
        ForEach(points, id: \.day) { point in
            LineMark(
                x: .value(ChartLabel.day, ChartDay.date(point.day)),
                y: .value(ChartLabel.adherence, point.mean),
                // One series per window and gap-free segment; the name is never shown.
                series: .value("Window", "\(name) \(point.segment)")
            )
            .foregroundStyle(dashed ? color.opacity(0.6) : color)
            .lineStyle(StrokeStyle(lineWidth: dashed ? 1.5 : 2, dash: dashed ? [4, 3] : []))
        }
    }
}

/// The model's estimate with ± 1 standard deviation (§12).
public struct ConfidenceChart: View {
    let insights: HabitInsights
    let color: Color

    public init(insights: HabitInsights, color: Color) {
        self.insights = insights
        self.color = color
    }

    public var body: some View {
        ChartCard(title: String(localized: "Model confidence", bundle: .module)) {
            Chart {
                BandMarks(bands: insights.bands)
                ForEach(insights.series, id: \.day) { point in
                    AreaMark(
                        x: .value(ChartLabel.day, ChartDay.date(point.day)),
                        yStart: .value(
                            String(localized: "Low", bundle: .module),
                            max(0, point.mean - point.standardDeviation)
                        ),
                        yEnd: .value(
                            String(localized: "High", bundle: .module),
                            min(1, point.mean + point.standardDeviation)
                        )
                    )
                    .foregroundStyle(color.opacity(0.2))
                    LineMark(x: .value(ChartLabel.day, ChartDay.date(point.day)), y: .value(Self.estimate, point.mean))
                        .foregroundStyle(color)
                }
            }
            .dayAxis()
            .percentAxis()
            .chartXScale(domain: insights.domain)
            .frame(height: 140)
            .accessibilityLabel(Self.summary(insights.series))
        } legend: {
            LegendRow(items: [
                LegendItem(Self.estimate, color: color),
                LegendItem(String(localized: "± 1 sd", bundle: .module), band: color.opacity(0.2)),
            ] + bandLegend(insights))
        }
    }

    private static let estimate = String(localized: "Estimate", bundle: .module)

    /// "Model estimate now: 85%, likely between 75% and 95%".
    nonisolated static func summary(_ series: [ModelPoint]) -> String {
        guard let last = series.last else {
            return String(localized: "No data", bundle: .module)
        }
        let low = DayFormat.percent(max(0, last.mean - last.standardDeviation))
        let high = DayFormat.percent(min(1, last.mean + last.standardDeviation))
        return String(
            localized: "Model estimate now: \(DayFormat.percent(last.mean)), likely between \(low) and \(high)",
            bundle: .module
        )
    }
}

/// Every per-habit chart for habit detail (§12), or why there are none yet.
public struct HabitCharts: View {
    let insights: HabitInsights
    let color: Color

    public init(insights: HabitInsights, color: Color) {
        self.insights = insights
        self.color = color
    }

    public var body: some View {
        if insights.hasEnoughData {
            AskIntervalChart(insights: insights, color: color)
            AdherenceChart(insights: insights, color: color)
            ConfidenceChart(insights: insights, color: color)
            CalendarHeatmap(days: insights.days, color: color)
        } else {
            NotEnoughData(availableDays: insights.availableDays)
        }
        HStack {
            StatTile(String(localized: "Delays", bundle: .module), value: insights.delays.formatted())
            StatTile(String(localized: "Days paused", bundle: .module), value: insights.pausedDays.formatted())
            if insights.blockedDays > 0 {
                StatTile(String(localized: "Days blocked", bundle: .module), value: insights.blockedDays.formatted())
            }
        }
    }
}

extension HabitInsights {
    /// The x range of the habit's timelines: its whole history.
    var domain: ClosedRange<Date> {
        guard let first = days.first?.day, let last = days.last?.day else {
            let now = Date(timeIntervalSince1970: 0)
            return now ... now
        }
        return ChartDay.domain(first ... last)
    }
}

/// Legend entries for the bands this habit actually has.
@MainActor
private func bandLegend(_ insights: HabitInsights) -> [LegendItem] {
    let reasons = Set(insights.bands.map(\.reason))
    return [Unavailability.paused, .blocked].filter(reasons.contains).map { reason in
        LegendItem(reason == .paused ? ChartLabel.paused : ChartLabel.blocked, band: BandStyle.color(reason))
    }
}
