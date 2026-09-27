import Foundation

/// Why a habit is due today (DESIGN.md §4.2). Cases are listed in the order `dueReason` checks them.
public enum DueReason: String, Codable, Sendable, Hashable, CaseIterable {
    /// Rule 4: first active day after a pause.
    case reentry
    /// Rule 2: evidence mean below the habit's target and not yet asked today.
    case belowTarget
    /// Rule 3: `maxIntervalDays` without covering an answer.
    case maxInterval
    /// Rule 1: posterior sd above `uncertaintyThreshold`.
    case uncertain
    /// Rule 5: calibration check on a long natural interval.
    case spotCheck

    /// Sort tier ahead of the score (§4.4): re-entry checks first, then struggling habits.
    var priorityTier: Int {
        switch self {
        case .reentry: 2
        case .belowTarget: 1
        case .maxInterval, .uncertain, .spotCheck: 0
        }
    }
}

/// A due habit with its priority (§4.4). Questions are built from it only at presentation time.
public struct DueHabit: Sendable, Hashable {
    public let habitID: UUID
    public let reason: DueReason
    /// `uncertainty × importanceWeight × staleness`.
    public let score: Double
}

/// One session's output (§4.4): at most `sessionBudget` questions; the rest wait behind "More…".
public struct SessionPlan: Sendable, Hashable {
    public let questions: [Question]
    /// Why each question is asked; aligned with `questions`.
    public let presented: [DueHabit]
    /// Due but over budget, in priority order.
    public let queued: [DueHabit]
}

/// Decides which habits are due, what to ask and in what order (DESIGN.md §4.2–4.4). Pure: all inputs
/// are values, today comes from the injected `Clock`.
///
/// Gated habits (§4.5) are gated here from the parents' projected `records`. Pauses and paused parents
/// (§4.6) are decided outside the planner and passed in as `unavailable` habit IDs.
public struct QuestionPlanner: Sendable {
    public let settings: Settings

    public init(settings: Settings) throws {
        try settings.validate()
        self.settings = settings
    }

    // MARK: Due rules (§4.2)

    /// Nil when the habit is not due. Archived habits and habits already covered through `today` are
    /// never due.
    public func dueReason(habit: Habit, state: SchedulerState, today: DayKey) throws -> DueReason? {
        guard !habit.isArchived, gapDays(habit: habit, state: state, today: today) >= 1 else { return nil }
        let model = state.adherence
        if state.forcedReentryCheck {
            return .reentry
        }
        if model.isBelowTarget(habit.targetAdherence), state.lastAskedDay.map({ $0 < today }) ?? true {
            return .belowTarget
        }
        if gapDays(habit: habit, state: state, today: today) >= settings.maxIntervalDays {
            return .maxInterval
        }
        if model.standardDeviation > settings.uncertaintyThreshold {
            return .uncertain
        }
        let interval = try model.askIntervalDays(target: habit.targetAdherence, settings: settings)
        guard interval > SpotCheck.minAskIntervalDays else { return nil }
        return SpotCheck.isSpotCheck(habitID: habit.id, day: today, rate: settings.spotCheckRate) ? .spotCheck : nil
    }

    // MARK: Question construction (§4.3)

    /// Days since the last covered day; a habit never covered counts from its `createdDay` inclusive.
    public func gapDays(habit: Habit, state: SchedulerState, today: DayKey) -> Int {
        let lastCovered = state.lastCoveredDay ?? habit.createdDay.adding(days: -1)
        return lastCovered.days(to: today)
    }

    /// The trailing `min(gap, maxRecallGapDays)` days ending today, or nil if nothing is uncovered.
    /// Uncovered days before the window are left to the projection to infer.
    public func covers(habit: Habit, state: SchedulerState, today: DayKey) -> ClosedRange<DayKey>? {
        let gap = gapDays(habit: habit, state: state, today: today)
        guard gap >= 1 else { return nil }
        let coverDays = min(gap, habit.maxRecallGapDays)
        return today.adding(days: 1 - coverDays) ... today
    }

    public static func shape(for covers: ClosedRange<DayKey>) -> QuestionShape {
        switch covers.count {
        case 1: .singleDay
        case 2 ... 3: .perDay(days: Array(covers))
        default: .count(total: covers.count)
        }
    }

    /// The question for `habit`, conditioned on its `gate` (from `gate(habit:...)`); nil when nothing is
    /// uncovered or the gate is closed.
    public func question(
        habit: Habit,
        state: SchedulerState,
        today: DayKey,
        createdAt: Date,
        gate: Gate? = nil
    ) -> Question? {
        guard let covers = covers(habit: habit, state: state, today: today) else { return nil }
        switch gate {
        case nil:
            return Question(habitID: habit.id, covers: covers, shape: Self.shape(for: covers), createdAt: createdAt)
        case let .open(shape, context):
            return Question(
                habitID: habit.id,
                covers: covers,
                shape: shape,
                createdAt: createdAt,
                parentContext: context
            )
        case .closed:
            return nil
        }
    }

    // MARK: Gating (§4.5)

    /// The gate over the habit's prospective `covers`, or nil if it has no active gate parents or nothing
    /// is uncovered. `byID` must contain every parent; habits without a state use `SchedulerState.initial`.
    public func gate(
        habit: Habit,
        byID: [UUID: Habit],
        states: [UUID: SchedulerState],
        records: DayRecords,
        today: DayKey
    ) throws -> Gate? {
        let state = states[habit.id] ?? .initial(habitID: habit.id)
        guard let covers = covers(habit: habit, state: state, today: today) else { return nil }
        let parentIDs = try Dependencies.activeGateParentIDs(of: habit, in: byID)
        return Dependencies.gate(parentIDs: parentIDs, covers: covers, states: states, records: records)
    }

    // MARK: Prioritization and budget (§4.4)

    public static func importanceWeight(_ importance: Importance) -> Double {
        switch importance {
        case .low: 1
        case .normal: 1.5
        case .high: 2
        }
    }

    public func score(habit: Habit, state: SchedulerState, today: DayKey) -> Double {
        let lastAsked = state.lastAskedDay ?? habit.createdDay
        let staleness = 1 + Double(max(0, lastAsked.days(to: today))) / 7
        return state.adherence.standardDeviation * Self.importanceWeight(habit.importance) * staleness
    }

    /// All due, available, ungated-or-open habits in presentation order: priority tier, then score, then
    /// habit ID so ties are deterministic. Habits without a state use `SchedulerState.initial`. `habits`
    /// must include every gate parent; `records` are the projected days used for gating.
    public func rankedDue(
        habits: [Habit],
        states: [UUID: SchedulerState],
        records: DayRecords,
        unavailable: Set<UUID>,
        today: DayKey
    ) throws -> [DueHabit] {
        try rankedCandidates(
            habits: habits, states: states, records: records, unavailable: unavailable, today: today
        ).map(\.due)
    }

    /// Plans a session: questions for the top `sessionBudget` due habits, the rest queued.
    public func session(
        habits: [Habit],
        states: [UUID: SchedulerState],
        records: DayRecords,
        unavailable: Set<UUID> = [],
        clock: some Clock
    ) throws -> SessionPlan {
        let today = clock.today()
        let ranked = try rankedCandidates(
            habits: habits, states: states, records: records, unavailable: unavailable, today: today
        )
        let shown = ranked.prefix(settings.sessionBudget).compactMap { candidate in
            question(
                habit: candidate.habit, state: candidate.state, today: today, createdAt: clock.now(),
                gate: candidate.gate
            ).map { ($0, candidate.due) }
        }
        return SessionPlan(
            questions: shown.map(\.0),
            presented: shown.map(\.1),
            queued: ranked.dropFirst(settings.sessionBudget).map(\.due)
        )
    }

    private struct Candidate {
        let habit: Habit
        let state: SchedulerState
        let gate: Gate?
        let due: DueHabit
    }

    private func rankedCandidates(
        habits: [Habit],
        states: [UUID: SchedulerState],
        records: DayRecords,
        unavailable: Set<UUID>,
        today: DayKey
    ) throws -> [Candidate] {
        let byID = try Dependencies.index(habits)
        var candidates: [Candidate] = []
        for habit in habits where !unavailable.contains(habit.id) {
            let state = states[habit.id] ?? .initial(habitID: habit.id)
            guard let reason = try dueReason(habit: habit, state: state, today: today) else { continue }
            let gate = try gate(habit: habit, byID: byID, states: states, records: records, today: today)
            if gate == .closed {
                continue
            }
            let due = DueHabit(
                habitID: habit.id,
                reason: reason,
                score: score(habit: habit, state: state, today: today)
            )
            candidates.append(Candidate(habit: habit, state: state, gate: gate, due: due))
        }
        return candidates.sorted { lhs, rhs in
            let (left, right) = (lhs.due, rhs.due)
            if left.reason.priorityTier != right.reason.priorityTier {
                return left.reason.priorityTier > right.reason.priorityTier
            }
            if left.score != right.score {
                return left.score > right.score
            }
            return left.habitID.uuidString < right.habitID.uuidString
        }
    }
}
