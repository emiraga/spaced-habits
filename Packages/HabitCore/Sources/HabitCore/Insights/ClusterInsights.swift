import Foundation

/// A cluster's charts (DESIGN.md §12, per cluster): stacked weekly adherence per member, `P(B|A)` against
/// `P(B)` for gated members, and a funnel along the longest gate chain.
public struct ClusterInsights: Sendable, Hashable {
    /// One member's adherence over one week.
    public struct MemberWeek: Sendable, Hashable {
        public let habitID: UUID
        /// First day of the 7-day week; the last week ends today.
        public let weekStart: DayKey
        public let mean: Double

        public init(habitID: UUID, weekStart: DayKey, mean: Double) {
            self.habitID = habitID
            self.weekStart = weekStart
            self.mean = mean
        }
    }

    /// A gated member's adherence on its parents' days (`conditional`, the scheduler's `P(B|A)`) and on
    /// all days (`overall`, `P(B)`), over the last `windowDays` days.
    public struct Pair: Sendable, Hashable {
        public let habitID: UUID
        public let parentIDs: [UUID]
        public let conditional: Double?
        public let overall: Double?

        public init(habitID: UUID, parentIDs: [UUID], conditional: Double?, overall: Double?) {
            self.habitID = habitID
            self.parentIDs = parentIDs
            self.conditional = conditional
            self.overall = overall
        }
    }

    /// How many days reached each step of a gate chain: A, then A and B, then A, B and C.
    public struct FunnelStep: Sendable, Hashable {
        public let habitID: UUID
        /// Expected days: aggregated days contribute their fraction.
        public let days: Double

        public init(habitID: UUID, days: Double) {
            self.habitID = habitID
            self.days = days
        }
    }

    public static let weeks = 12
    public static let windowDays = 30

    public let clusterID: UUID
    public let memberIDs: [UUID]
    public let memberWeeks: [MemberWeek]
    public let pairs: [Pair]
    /// Empty without a chain of at least two members.
    public let funnel: [FunnelStep]
    /// Days, in the funnel window, with evidence for every chain member: the funnel's base.
    public let funnelDays: Int
    public let availableDays: Int

    public var hasEnoughData: Bool {
        availableDays >= Insights.minimumChartDays
    }

    /// `members` are the cluster's active habits in display order.
    public init(clusterID: UUID, members: [Habit], records: DayRecords, today: DayKey, filter: AdherenceFilter) {
        self.clusterID = clusterID
        memberIDs = members.map(\.id)
        memberWeeks = (0 ..< Self.weeks).reversed().flatMap { week in
            let end = today.adding(days: -7 * week)
            let days = end.adding(days: -6) ... end
            return members.compactMap { habit -> MemberWeek? in
                let records = records[habit.id] ?? [:]
                return filter.mean(of: days.compactMap { records[$0] }).map {
                    MemberWeek(habitID: habit.id, weekStart: days.lowerBound, mean: $0.mean)
                }
            }
        }
        let window = today.adding(days: 1 - Self.windowDays) ... today
        pairs = members.filter { !$0.gateParentIDs.isEmpty }.map { habit in
            let recent = window.compactMap { records[habit.id]?[$0] }
            var overall = filter
            overall.includingParentMisses = true
            return Pair(
                habitID: habit.id, parentIDs: habit.gateParentIDs,
                conditional: filter.mean(of: recent)?.mean, overall: overall.mean(of: recent)?.mean
            )
        }
        let chain = Self.longestGateChain(members)
        (funnel, funnelDays) = chain.count < 2 ? ([], 0) : Self.funnel(chain, records: records, window: window)
        availableDays = Overview.availableDays(habits: members, records: records)
    }

    /// The longest path along gate edges between members, parent first; ties go to the earlier member.
    static func longestGateChain(_ members: [Habit]) -> [UUID] {
        let ids = Set(members.map(\.id))
        var memo: [UUID: [UUID]] = [:]
        /// Longest chain ending at `habit`. Gate edges form a DAG (`Dependencies.validate`).
        func chain(to habit: Habit) -> [UUID] {
            if let known = memo[habit.id] {
                return known
            }
            let parents = members.filter { habit.gateParentIDs.contains($0.id) && ids.contains($0.id) }
            let best = parents.map(chain(to:)).reduce([UUID]()) { $1.count > $0.count ? $1 : $0 }
            memo[habit.id] = best + [habit.id]
            return best + [habit.id]
        }
        return members.map(chain(to:)).reduce([UUID]()) { $1.count > $0.count ? $1 : $0 }
    }

    /// Over the window's days with evidence for every chain member, the expected number of days each prefix
    /// of the chain was all done. A child's value on a parent-miss day is an observed 0, so it counts.
    static func funnel(
        _ chain: [UUID],
        records: DayRecords,
        window: ClosedRange<DayKey>
    ) -> (steps: [FunnelStep], days: Int) {
        let everyDay = AdherenceFilter(includingParentMisses: true)
        var totals = [Double](repeating: 0, count: chain.count)
        var days = 0
        for day in window {
            let values = chain.compactMap { records[$0]?[day].flatMap(everyDay.value(of:)) }
            guard values.count == chain.count else { continue }
            days += 1
            var product = 1.0
            for (index, value) in values.enumerated() {
                product *= value
                totals[index] += product
            }
        }
        return (zip(chain, totals).map { FunnelStep(habitID: $0, days: $1) }, days)
    }
}
