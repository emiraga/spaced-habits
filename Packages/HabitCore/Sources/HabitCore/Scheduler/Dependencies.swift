import Foundation

/// Whether a gated habit's parents make a question about its window meaningful (DESIGN.md §4.5).
public enum Gate: Sendable, Hashable {
    /// Ask with this shape; `context` drives the card's "You did Gym on 4 of 6 days".
    case open(shape: QuestionShape, context: ParentContext)
    /// Parents are failing over the window; asking would produce noise, so the habit is not due.
    case closed
}

/// Habit dependency graph: DAG validation, ordering and gating (DESIGN.md §4.5).
public enum Dependencies {
    /// Every gate parent's posterior mean must reach this.
    public static let minParentMean = 0.5
    /// Expected days in the window on which all gate parents were done must reach this.
    public static let minExpectedParentDoneDays = 1.0
    /// A day counts as parent-done (gets a per-day toggle) when the joint parent value reaches this.
    public static let parentDoneDayThreshold = 0.5

    public enum ValidationError: Error, Equatable {
        case duplicateHabitID(UUID)
        case unknownParent(habitID: UUID, parentID: UUID)
        /// Habit IDs along the cycle; each is a parent of the one before it.
        case cycle([UUID])
    }

    /// Validates every habit and that parent edges (all modes) point at known habits and form a DAG.
    /// Run at edit time and on import.
    public static func validate(_ habits: [Habit]) throws {
        _ = try topologicallySorted(habits)
    }

    /// Parents before children (all edge modes); otherwise input order. Throws like `validate`.
    public static func topologicallySorted(_ habits: [Habit]) throws -> [Habit] {
        let byID = try index(habits)
        for habit in habits {
            try habit.validate()
            if let unknown = habit.allParentIDs.first(where: { byID[$0] == nil }) {
                throw ValidationError.unknownParent(habitID: habit.id, parentID: unknown)
            }
        }
        var sorter = TopologicalSorter(byID: byID)
        for habit in habits {
            try sorter.visit(habit.id)
        }
        return sorter.order
    }

    /// The loop that making `habitID` depend on `parentID` (any mode) would close, or nil if the edge is
    /// safe. Starts and ends at `habitID`; each habit depends on the next: `[Shake, Gym, Shake]` means Shake
    /// would depend on Gym, which already depends on Shake. For the editor's picker, before `validate`.
    public static func cycle(ifAdding parentID: UUID, to habitID: UUID, in habits: [Habit]) -> [UUID]? {
        let byID = Dictionary(habits.map { ($0.id, $0) }) { first, _ in first }
        var visited: Set<UUID> = []
        func path(from id: UUID) -> [UUID]? {
            if id == habitID {
                return [id]
            }
            guard visited.insert(id).inserted, let habit = byID[id] else { return nil }
            for next in habit.allParentIDs {
                if let rest = path(from: next) {
                    return [id] + rest
                }
            }
            return nil
        }
        return path(from: parentID).map { [habitID] + $0 }
    }

    /// Habits keyed by ID; throws on duplicates.
    public static func index(_ habits: [Habit]) throws -> [UUID: Habit] {
        try Dictionary(habits.map { ($0.id, $0) }) { first, _ in
            throw ValidationError.duplicateHabitID(first.id)
        }
    }

    /// Gate parents that still gate `habit`. Edges to archived parents are ignored: an archived parent
    /// gets no new evidence and would otherwise gate its children forever.
    public static func activeGateParentIDs(of habit: Habit, in byID: [UUID: Habit]) throws -> [UUID] {
        try habit.gateParentIDs.filter { parentID in
            guard let parent = byID[parentID] else {
                throw ValidationError.unknownParent(habitID: habit.id, parentID: parentID)
            }
            return !parent.isArchived
        }
    }

    /// Evaluates the gate for a question covering `covers`, or nil if `parentIDs` is empty (ungated).
    ///
    /// Open when every parent's mean ≥ `minParentMean` and the known number of days on which all parents
    /// were done (per-day product of `knownValue`) ≥ `minExpectedParentDoneDays`, so a child waits until its
    /// parents have been answered for the window. The shape is conditional on those days: `perDay` lists
    /// parent-done days when each is exactly known (observed or Health), otherwise `count` totals
    /// `parentDoneDays` and the user reconciles against the days they remember.
    public static func gate(
        parentIDs: [UUID],
        covers: ClosedRange<DayKey>,
        states: [UUID: SchedulerState],
        records: DayRecords
    ) -> Gate? {
        guard !parentIDs.isEmpty else { return nil }
        let means = parentIDs.map { (states[$0] ?? .initial(habitID: $0)).adherence.mean }
        guard means.allSatisfy({ $0 >= minParentMean }) else { return .closed }
        let joint = jointParentValues(parentIDs: parentIDs, covers: covers, records: records)
        let expectedDoneDays = joint.reduce(0) { $0 + $1.value }
        guard expectedDoneDays >= minExpectedParentDoneDays else { return .closed }
        let context = ParentContext(parentIDs: parentIDs, parentDoneDays: Int(expectedDoneDays.rounded()))
        switch QuestionPlanner.shape(for: covers) {
        case .singleDay:
            return .open(shape: .singleDay, context: context)
        case .perDay:
            let days = joint.filter { $0.value >= parentDoneDayThreshold }.map(\.day)
            guard !days.isEmpty else { return .closed }
            let known = days.allSatisfy { day in
                parentIDs.allSatisfy { [.observed, .health].contains(records[$0]?[day]?.source) }
            }
            return .open(shape: known ? .perDay(days: days) : .count(total: context.parentDoneDays), context: context)
        case .count:
            return .open(shape: .count(total: context.parentDoneDays), context: context)
        }
    }

    /// Per day in `covers`, the known value that all parents were done: the product of each parent's
    /// `knownValue`.
    public static func jointParentValues(
        parentIDs: [UUID],
        covers: ClosedRange<DayKey>,
        records: DayRecords
    ) -> [(day: DayKey, value: Double)] {
        covers.map { day in
            (day, parentIDs.reduce(1.0) { $0 * knownValue(of: records[$1]?[day]) })
        }
    }

    /// Days in `covers` on which all parents were known done (joint value ≥ `parentDoneDayThreshold`).
    public static func parentDoneDays(parentIDs: [UUID], covers: ClosedRange<DayKey>, records: DayRecords) -> [DayKey] {
        jointParentValues(parentIDs: parentIDs, covers: covers, records: records)
            .filter { $0.value >= parentDoneDayThreshold }
            .map(\.day)
    }

    /// What evidence says about a parent's day: the value of an observed, aggregated or Health record, else
    /// 0. Inferred days are guesses; building a child's question on them asks about days the parent may
    /// not have happened, and truthful "no" answers then bias P(child | parent) down.
    static func knownValue(of record: DayRecord?) -> Double {
        guard let record, record.source.feedsModel else { return 0 }
        return record.value
    }
}

/// Depth-first post-order over parent edges; reports the first cycle it walks into.
private struct TopologicalSorter {
    let byID: [UUID: Habit]
    private(set) var order: [Habit] = []
    private var done: Set<UUID> = []
    private var path: [UUID] = []

    init(byID: [UUID: Habit]) {
        self.byID = byID
    }

    mutating func visit(_ id: UUID) throws {
        guard !done.contains(id) else { return }
        if let start = path.firstIndex(of: id) {
            throw Dependencies.ValidationError.cycle(Array(path[start...]))
        }
        guard let habit = byID[id] else { return }
        path.append(id)
        for parentID in habit.allParentIDs {
            try visit(parentID)
        }
        path.removeLast()
        done.insert(id)
        order.append(habit)
    }
}
