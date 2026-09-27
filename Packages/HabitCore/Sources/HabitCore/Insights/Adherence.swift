import Foundation

/// Which days count toward an adherence figure in the charts (DESIGN.md §12).
///
/// Only evidence counts (observed, aggregated, Health): inferred days are the model's guess, not adherence,
/// and unknown days say nothing. Paused and blocked days are left out unless `includingPaused`, when they
/// count as not done. For a gated habit the default is P(habit | parents) (§4.5); `includingParentMisses`
/// adds the days its parents were not done, giving P(habit).
public struct AdherenceFilter: Sendable, Hashable {
    public var includingPaused: Bool
    public var includingParentMisses: Bool

    public init(includingPaused: Bool = false, includingParentMisses: Bool = false) {
        self.includingPaused = includingPaused
        self.includingParentMisses = includingParentMisses
    }

    /// The record's value if the day counts, else nil.
    public func value(of record: DayRecord) -> Double? {
        switch record.source {
        case .observed, .aggregated, .health:
            record.conditionalDenominatorExcluded && !includingParentMisses ? nil : record.value
        case .paused, .blocked:
            includingPaused ? 0 : nil
        case .inferred, .unknown, .notYetDue:
            nil
        }
    }

    /// Mean over the days that count, and how many there were. Nil if none do.
    public func mean(of records: some Sequence<DayRecord>) -> (mean: Double, days: Int)? {
        var sum = 0.0
        var days = 0
        for value in records.lazy.compactMap(value(of:)) {
            sum += value
            days += 1
        }
        return days == 0 ? nil : (sum / Double(days), days)
    }
}

/// One point of a rolling adherence line. A new `segment` starts after a day whose window had nothing to
/// count, so the chart breaks the line there instead of bridging the gap.
public struct AdherencePoint: Sendable, Hashable {
    public let day: DayKey
    public let mean: Double
    public let segment: Int

    public init(day: DayKey, mean: Double, segment: Int) {
        self.day = day
        self.mean = mean
        self.segment = segment
    }
}

/// A run of consecutive days a habit was paused or blocked: the shaded bands on timelines (§12).
public struct DayBand: Sendable, Hashable {
    public let days: ClosedRange<DayKey>
    public let reason: Unavailability

    public init(days: ClosedRange<DayKey>, reason: Unavailability) {
        self.days = days
        self.reason = reason
    }
}

public enum Insights {
    /// Charts are hidden below this many non-paused days (§12): too little to show a trend.
    public static let minimumChartDays = 7

    /// Mean over each trailing `window` days, for every day in `days` whose window has a day that counts.
    public static func rollingAdherence(
        _ records: [DayKey: DayRecord],
        over days: ClosedRange<DayKey>,
        window: Int,
        filter: AdherenceFilter
    ) -> [AdherencePoint] {
        var points: [AdherencePoint] = []
        var sum = 0.0
        var count = 0
        var segment = 0
        var gap = false
        func add(_ day: DayKey, _ sign: Double) {
            guard let value = records[day].flatMap(filter.value(of:)) else { return }
            sum += sign * value
            count += sign > 0 ? 1 : -1
        }
        // Warm up with the `window` days before `days`; the first step drops the oldest of them.
        for day in stride(from: days.lowerBound.adding(days: -window), to: days.lowerBound, by: 1) {
            add(day, 1)
        }
        for day in days {
            add(day, 1)
            add(day.adding(days: -window), -1)
            guard count > 0 else {
                gap = true
                continue
            }
            if gap, !points.isEmpty {
                segment += 1
            }
            gap = false
            points.append(AdherencePoint(day: day, mean: sum / Double(count), segment: segment))
        }
        return points
    }

    /// Runs of paused and blocked days, oldest first. A run changes band when the reason changes.
    public static func pauseBands(_ records: [DayKey: DayRecord]) -> [DayBand] {
        var bands: [DayBand] = []
        for day in records.keys.sorted() {
            guard let reason = records[day].flatMap(unavailability) else { continue }
            if let last = bands.last, last.reason == reason, last.days.upperBound.adding(days: 1) == day {
                bands[bands.count - 1] = DayBand(days: last.days.lowerBound ... day, reason: reason)
            } else {
                bands.append(DayBand(days: day ... day, reason: reason))
            }
        }
        return bands
    }

    /// Days neither paused nor blocked; charts need `minimumChartDays` of them.
    public static func availableDays(_ records: [DayKey: DayRecord]) -> Int {
        records.values.count { unavailability($0) == nil }
    }

    static func unavailability(_ record: DayRecord) -> Unavailability? {
        switch record.source {
        case .paused: .paused
        case .blocked: .blocked
        default: nil
        }
    }
}
