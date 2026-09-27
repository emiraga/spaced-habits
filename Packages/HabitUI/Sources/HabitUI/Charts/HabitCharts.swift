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
        ChartCard(title: "Days between check-ins") {
            Chart {
                BandMarks(bands: insights.bands)
                ForEach(insights.series, id: \.day) { point in
                    LineMark(x: .value("Day", ChartDay.date(point.day)), y: .value("Days", point.intervalDays))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(color)
                }
            }
            .dayAxis()
            .chartXScale(domain: insights.domain)
            .frame(height: 160)
            .accessibilityLabel(Self.summary(insights.series))
        } legend: {
            LegendRow(items: [LegendItem("Ask interval, from the model after each day", color: color)] +
                bandLegend(insights))
        }
    }

    /// "Days between check-ins: 1 at first, 11 now, at most 12".
    static func summary(_ series: [ModelPoint]) -> String {
        guard let first = series.first, let last = series.last else { return "No data" }
        return "Days between check-ins: \(first.intervalDays) at first, \(last.intervalDays) now, "
            + "at most \(series.map(\.intervalDays).max() ?? last.intervalDays)"
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
        ChartCard(title: "Adherence") {
            Chart {
                BandMarks(bands: insights.bands)
                line(insights.rolling30, name: "30 days", dashed: false)
                line(insights.rolling7, name: "7 days", dashed: true)
                RuleMark(y: .value("Target", insights.target))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            .dayAxis()
            .percentAxis()
            .chartXScale(domain: insights.domain)
            .frame(height: 160)
        } legend: {
            VStack(alignment: .leading, spacing: 4) {
                LegendRow(items: [
                    LegendItem("30 days", color: color),
                    LegendItem("7 days", color: color.opacity(0.6), dashed: true),
                    LegendItem("Target", color: .secondary, dashed: true),
                ] + bandLegend(insights))
                Text("From answered days: yes/no, counts and Health. Estimated days are left out.")
            }
        }
    }

    private func line(_ points: [AdherencePoint], name: String, dashed: Bool) -> some ChartContent {
        ForEach(points, id: \.day) { point in
            LineMark(
                x: .value("Day", ChartDay.date(point.day)),
                y: .value("Adherence", point.mean),
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
        ChartCard(title: "Model confidence") {
            Chart {
                BandMarks(bands: insights.bands)
                ForEach(insights.series, id: \.day) { point in
                    AreaMark(
                        x: .value("Day", ChartDay.date(point.day)),
                        yStart: .value("Low", max(0, point.mean - point.standardDeviation)),
                        yEnd: .value("High", min(1, point.mean + point.standardDeviation))
                    )
                    .foregroundStyle(color.opacity(0.2))
                    LineMark(x: .value("Day", ChartDay.date(point.day)), y: .value("Estimate", point.mean))
                        .foregroundStyle(color)
                }
            }
            .dayAxis()
            .percentAxis()
            .chartXScale(domain: insights.domain)
            .frame(height: 140)
        } legend: {
            LegendRow(items: [
                LegendItem("Estimate", color: color),
                LegendItem("± 1 sd", band: color.opacity(0.2)),
            ] + bandLegend(insights))
        }
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
            StatTile("Delays", value: "\(insights.delays)")
            StatTile("Days paused", value: "\(insights.pausedDays)")
            if insights.blockedDays > 0 {
                StatTile("Days blocked", value: "\(insights.blockedDays)")
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
        LegendItem(reason == .paused ? "Paused" : "Blocked", band: BandStyle.color(reason))
    }
}
