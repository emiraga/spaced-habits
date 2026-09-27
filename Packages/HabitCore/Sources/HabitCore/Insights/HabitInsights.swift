import Foundation

/// Everything the habit detail charts show (DESIGN.md §12, per habit), computed from the projection.
public struct HabitInsights: Sendable, Hashable {
    public let habitID: UUID
    /// The model at the end of each day: ask interval, and mean ± sd for the confidence chart.
    public let series: [ModelPoint]
    public let rolling7: [AdherencePoint]
    public let rolling30: [AdherencePoint]
    public let target: Double
    public let bands: [DayBand]
    /// Every projected day, oldest first, for the calendar heatmap.
    public let days: [DayRecord]
    /// Non-paused, non-blocked days; the charts need `Insights.minimumChartDays`.
    public let availableDays: Int
    /// Manual delays over the habit's whole history.
    public let delays: Int
    public let pausedDays: Int
    public let blockedDays: Int

    public var hasEnoughData: Bool {
        availableDays >= Insights.minimumChartDays
    }

    public init(habit: Habit, projected: Projected, pauses: [PauseEvent], today: DayKey, filter: AdherenceFilter) {
        let records = projected.records[habit.id] ?? [:]
        habitID = habit.id
        series = projected.series[habit.id] ?? []
        target = habit.targetAdherence
        days = records.values.sorted { $0.day < $1.day }
        if let first = days.first?.day, let last = days.last?.day {
            rolling7 = Insights.rollingAdherence(records, over: first ... last, window: 7, filter: filter)
            rolling30 = Insights.rollingAdherence(records, over: first ... last, window: 30, filter: filter)
        } else {
            rolling7 = []
            rolling30 = []
        }
        bands = Insights.pauseBands(records)
        availableDays = Insights.availableDays(records)
        let history = min(habit.createdDay, today) ... today
        delays = Pauses.delayCounts(pauses: pauses, startingIn: history)[habit.id] ?? 0
        pausedDays = days.count { $0.source == .paused }
        blockedDays = days.count { $0.source == .blocked }
    }
}
