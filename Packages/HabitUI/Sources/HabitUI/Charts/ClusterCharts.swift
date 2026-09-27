import Charts
import HabitCore
import SwiftUI

/// A cluster's charts (§12): stacked weekly adherence per member, `P(B|A)` against `P(B)` for gated
/// members, and the funnel along its gate chain.
public struct ClusterCharts: View {
    let insights: ClusterInsights
    let habits: [Habit]

    /// `habits` must include every member and their parents.
    public init(insights: ClusterInsights, habits: [Habit]) {
        self.insights = insights
        self.habits = habits
    }

    public var body: some View {
        if insights.hasEnoughData {
            stacked
            if !insights.pairs.isEmpty {
                pairs
            }
            if !insights.funnel.isEmpty {
                funnel
            }
        } else {
            NotEnoughData(availableDays: insights.availableDays)
        }
    }

    private func name(_ id: UUID) -> String {
        habits.first { $0.id == id }?.name ?? String(localized: "Unknown habit", bundle: .module)
    }

    private var members: [Habit] {
        insights.memberIDs.compactMap { id in habits.first { $0.id == id } }
    }

    private var stacked: some View {
        ChartCard(title: String(localized: "Adherence by week", bundle: .module)) {
            Chart(insights.memberWeeks, id: \.self) { week in
                BarMark(
                    x: .value(ChartLabel.week, ChartDay.date(week.weekStart), unit: .weekOfYear),
                    y: .value(ChartLabel.adherence, week.mean)
                )
                .foregroundStyle(by: .value(ChartLabel.habit, name(week.habitID)))
            }
            .chartForegroundStyleScale(domain: members.map(\.name), range: members.map { Color(hex: $0.colorHex) })
            .dayAxis()
            .frame(height: 160)
        } legend: {
            Text(
                "Each habit's share of answered days done, per week, stacked. Estimated and paused days left out.",
                bundle: .module
            )
        }
    }

    private var pairs: some View {
        ChartCard(title: String(localized: "Together and on their own", bundle: .module)) {
            Chart {
                ForEach(insights.pairs, id: \.habitID) { pair in
                    if let conditional = pair.conditional {
                        BarMark(
                            x: .value(ChartLabel.adherence, conditional),
                            y: .value(ChartLabel.habit, name(pair.habitID))
                        )
                        .position(by: .value(ChartLabel.days, Self.parentDays))
                        .foregroundStyle(by: .value(ChartLabel.days, Self.parentDays))
                    }
                    if let overall = pair.overall {
                        BarMark(
                            x: .value(ChartLabel.adherence, overall),
                            y: .value(ChartLabel.habit, name(pair.habitID))
                        )
                        .position(by: .value(ChartLabel.days, Self.allDays))
                        .foregroundStyle(by: .value(ChartLabel.days, Self.allDays))
                    }
                }
            }
            .chartXScale(domain: 0 ... 1)
            .chartForegroundStyleScale([Self.parentDays: Color.accentColor, Self.allDays: Color.gray])
            .frame(height: CGFloat(insights.pairs.count) * 50 + 30)
        } legend: {
            Text(
                "Last \(ClusterInsights.windowDays) days. On parent days: how often a habit follows the one it depends on. All days: how often it happens at all.",
                bundle: .module
            )
        }
    }

    private var funnel: some View {
        ChartCard(title: String(localized: "Chain", bundle: .module)) {
            Chart(Array(insights.funnel.enumerated()), id: \.offset) { index, step in
                BarMark(
                    x: .value(ChartLabel.days, step.days),
                    y: .value(
                        String(localized: "Step", bundle: .module),
                        index == 0 ? name(step.habitID) : "+ \(name(step.habitID))"
                    )
                )
                .foregroundStyle(Color(hex: habits.first { $0.id == step.habitID }?.colorHex ?? ""))
                .annotation(position: .trailing) {
                    Text(step.days.formatted(.number.precision(.fractionLength(0))))
                        .font(.caption)
                }
            }
            .chartXScale(domain: 0 ... Double(max(1, insights.funnelDays)))
            .frame(height: CGFloat(insights.funnel.count) * 36 + 30)
        } legend: {
            Text(
                "Days the whole chain happened, over the \(insights.funnelDays) of the last \(ClusterInsights.windowDays) days answered for every habit in it. Counts add fractions of days.",
                bundle: .module
            )
        }
    }

    private static let parentDays = String(localized: "On parent days", bundle: .module)
    private static let allDays = String(localized: "All days", bundle: .module)
}
