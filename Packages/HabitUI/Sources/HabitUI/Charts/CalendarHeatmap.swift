import HabitCore
import SwiftUI

/// How a heatmap cell is drawn (§12). Aggregated and inferred always look different (§1.1): a count's
/// days are filled with a dotted outline, estimates are only hatched.
enum HeatmapCell: CaseIterable {
    /// Answered for the day, or from Health: filled by value.
    case answered
    /// From an "N of K" count: filled by value, dotted outline.
    case aggregated
    /// The model's estimate: hatched.
    case inferred
    case paused
    /// A parent was paused: striped.
    case blocked
    /// "Don't remember", or too uncertain to estimate: hollow.
    case unknown

    init?(_ source: DaySource) {
        switch source {
        case .observed, .health: self = .answered
        case .aggregated: self = .aggregated
        case .inferred: self = .inferred
        case .paused: self = .paused
        case .blocked: self = .blocked
        case .unknown: self = .unknown
        case .notYetDue: return nil
        }
    }

    var label: String {
        switch self {
        case .answered: String(localized: "Answered", bundle: .module)
        case .aggregated: String(localized: "From a count", bundle: .module)
        case .inferred: String(localized: "Estimated", bundle: .module)
        case .paused: ChartLabel.paused
        case .blocked: ChartLabel.blocked
        case .unknown: String(localized: "Unknown", bundle: .module)
        }
    }

    /// Draws the cell in `rect`; `value` is the day's value in 0...1.
    func draw(in context: GraphicsContext, rect: CGRect, value: Double, color: Color) {
        let shape = Path(roundedRect: rect, cornerRadius: min(3, rect.width / 4))
        // Even a 0 stays visible: an answered "no" is not an empty cell.
        let fill = color.opacity(0.12 + 0.88 * min(1, max(0, value)))
        switch self {
        case .answered:
            context.fill(shape, with: .color(fill))
        case .aggregated:
            context.fill(shape, with: .color(fill))
            context.stroke(
                shape, with: .color(.primary.opacity(0.7)),
                style: StrokeStyle(lineWidth: 1, dash: [1.5, 1.5])
            )
        case .inferred:
            var clipped = context
            clipped.clip(to: shape)
            clipped.stroke(lines(in: rect, diagonal: true), with: .color(fill), lineWidth: 1.2)
        case .paused:
            context.fill(shape, with: .color(.gray.opacity(0.35)))
        case .blocked:
            var clipped = context
            clipped.clip(to: shape)
            clipped.stroke(lines(in: rect, diagonal: false), with: .color(.gray.opacity(0.6)), lineWidth: 1)
        case .unknown:
            let inset = rect.insetBy(dx: 0.5, dy: 0.5)
            context.stroke(
                Path(roundedRect: inset, cornerRadius: min(3, inset.width / 4)), with: .color(.gray), lineWidth: 1
            )
        }
    }

    /// Hatching: diagonal lines, or horizontal stripes.
    private func lines(in rect: CGRect, diagonal: Bool) -> Path {
        var path = Path()
        let step = max(2.5, rect.width / 4)
        if diagonal {
            var offset = -rect.height
            while offset < rect.width {
                path.move(to: CGPoint(x: rect.minX + offset, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX + offset + rect.height, y: rect.minY))
                offset += step
            }
        } else {
            var line = rect.minY + step / 2
            while line < rect.maxY {
                path.move(to: CGPoint(x: rect.minX, y: line))
                path.addLine(to: CGPoint(x: rect.maxX, y: line))
                line += step
            }
        }
        return path
    }
}

/// The last `weeks` weeks of a habit, one column per week (Monday on top), one cell per day (§12).
public struct CalendarHeatmap: View {
    let days: [DayRecord]
    let color: Color
    let weeks: Int

    public static let defaultWeeks = 26

    /// `days` oldest first, as in `HabitInsights.days`.
    public init(days: [DayRecord], color: Color, weeks: Int = defaultWeeks) {
        self.days = days
        self.color = color
        self.weeks = weeks
    }

    public var body: some View {
        ChartCard(title: String(localized: "Calendar", bundle: .module)) {
            grid
                .frame(height: 7 * 15)
                .accessibilityElement()
                .accessibilityLabel(summary)
        } legend: {
            legend
        }
    }

    private var grid: some View {
        let shown = recent
        let firstMonday = shown.first.map { $0.day.adding(days: 1 - $0.day.weekday) }
        return Canvas { context, size in
            guard let firstMonday else { return }
            let cell = min(size.width / CGFloat(weeks), size.height / 7)
            let gap = max(1, cell / 8)
            for record in shown {
                guard let style = HeatmapCell(record.source) else { continue }
                let offset = firstMonday.days(to: record.day)
                let rect = CGRect(
                    x: CGFloat(offset / 7) * cell, y: CGFloat(record.day.weekday - 1) * cell,
                    width: cell - gap, height: cell - gap
                )
                style.draw(in: context, rect: rect, value: record.value, color: color)
            }
        }
    }

    /// The days in the last `weeks` weeks, from a Monday.
    private var recent: ArraySlice<DayRecord> {
        guard let last = days.last?.day else { return [] }
        let firstMonday = last.adding(days: 1 - last.weekday - 7 * (weeks - 1))
        let start = days.firstIndex { $0.day >= firstMonday } ?? days.endIndex
        return days[start...]
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(HeatmapCell.allCases, id: \.self) { style in
                LegendItem(
                    style.label,
                    swatch: Canvas { context, size in
                        style.draw(in: context, rect: CGRect(origin: .zero, size: size), value: 0.8, color: color)
                    }
                    .frame(width: 12, height: 12)
                )
            }
        }
    }

    private var summary: String {
        let counts = Dictionary(grouping: recent.compactMap { HeatmapCell($0.source) }, by: { $0 }).mapValues(\.count)
        let parts = HeatmapCell.allCases
            .compactMap { style in counts[style].map { "\($0) \(style.label.lowercased())" } }
            .formatted(.list(type: .and))
        return String(localized: "Calendar, last \(weeks) weeks: \(parts)", bundle: .module)
    }
}
