import Charts
import HabitCore
import SwiftUI

/// Chart x values for days: noon UTC on the day's civil date, like `DayFormat`, labeled in UTC so every
/// time zone shows the same dates (§3.1: this maps no instant to a day).
enum ChartDay {
    static func date(_ day: DayKey) -> Date {
        DayFormat.noonUTC(day)
    }

    /// Where a day's band starts: midnight UTC before `date(day)`.
    static func start(_ day: DayKey) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day.dayNumber) * 86400)
    }

    /// Where a day's band ends: midnight UTC after `date(day)`.
    static func end(_ day: DayKey) -> Date {
        start(day.adding(days: 1))
    }

    static func domain(_ days: ClosedRange<DayKey>) -> ClosedRange<Date> {
        start(days.lowerBound) ... end(days.upperBound)
    }

    static let label = Date.FormatStyle(timeZone: .gmt).month(.abbreviated).day()
}

/// Plotted values' names, which VoiceOver's audio graphs read out.
enum ChartLabel {
    static let day = String(localized: "Day", bundle: .module)
    static let days = String(localized: "Days", bundle: .module)
    static let week = String(localized: "Week", bundle: .module)
    static let weekday = String(localized: "Weekday", bundle: .module)
    static let from = String(localized: "From", bundle: .module)
    static let through = String(localized: "Through", bundle: .module)
    static let habit = String(localized: "Habit", bundle: .module)
    static let adherence = String(localized: "Adherence", bundle: .module)
    static let target = String(localized: "Target", bundle: .module)
    static let paused = String(localized: "Paused", bundle: .module)
    static let blocked = String(localized: "Blocked", bundle: .module)
}

extension View {
    /// Date axis labeled in UTC (see `ChartDay`).
    func dayAxis() -> some View {
        chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: ChartDay.label)
                    }
                }
            }
        }
    }

    /// 0–100 % axis for adherence.
    func percentAxis() -> some View {
        chartYScale(domain: 0 ... 1)
            .chartYAxis {
                AxisMarks(values: [0, 0.5, 1]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let fraction = value.as(Double.self) {
                            Text(DayFormat.percent(fraction))
                        }
                    }
                }
            }
    }
}

/// Paused and blocked stretches shaded behind a timeline (§12).
struct BandMarks: ChartContent {
    let bands: [DayBand]

    var body: some ChartContent {
        ForEach(bands, id: \.days.lowerBound) { band in
            RectangleMark(
                xStart: .value(ChartLabel.from, ChartDay.start(band.days.lowerBound)),
                xEnd: .value(ChartLabel.through, ChartDay.end(band.days.upperBound))
            )
            .foregroundStyle(BandStyle.color(band.reason))
        }
    }
}

enum BandStyle {
    static func color(_ reason: Unavailability) -> Color {
        switch reason {
        case .paused: .gray.opacity(0.18)
        case .blocked: .gray.opacity(0.32)
        }
    }

    static let vacation = Color.gray.opacity(0.18)
}

/// A titled chart with the data-source legend every chart carries (§12).
struct ChartCard<Content: View, Legend: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @ViewBuilder let legend: Legend

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content
            legend
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// One legend entry: a swatch and what it stands for.
struct LegendItem: View {
    let label: String
    let swatch: AnyView

    init(_ label: String, color: Color, dashed: Bool = false) {
        self.label = label
        swatch = AnyView(
            Capsule()
                .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 2] : []))
                .frame(width: 14, height: 2)
        )
    }

    init(_ label: String, band: Color) {
        self.label = label
        swatch = AnyView(RoundedRectangle(cornerRadius: 2).fill(band).frame(width: 12, height: 10))
    }

    init(_ label: String, swatch: some View) {
        self.label = label
        self.swatch = AnyView(swatch)
    }

    var body: some View {
        HStack(spacing: 4) {
            swatch
            Text(label)
        }
    }
}

/// Legend entries that wrap onto several lines.
struct LegendRow: View {
    let items: [LegendItem]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { ForEach(items.indices, id: \.self) { items[$0] } }
            VStack(alignment: .leading, spacing: 4) { ForEach(items.indices, id: \.self) { items[$0] } }
        }
    }
}

/// A small number with a caption ("Delays: 3").
public struct StatTile: View {
    let title: String
    let value: String

    public init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

/// Shown instead of a chart with fewer than `Insights.minimumChartDays` non-paused days (§12).
public struct NotEnoughData: View {
    let availableDays: Int

    public init(availableDays: Int) {
        self.availableDays = availableDays
    }

    public var body: some View {
        Text(
            "Charts appear after \(Insights.minimumChartDays) days that aren't paused (\(availableDays) so far).",
            bundle: .module
        )
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}
