import Foundation

/// Why a habit is due today (DESIGN.md §4.2). Cases are listed in the order `dueReason` checks them.
public enum DueReason: String, Codable, Sendable, Hashable, CaseIterable {
    /// Rule 4: first active day after a pause.
    case reentry
    /// Rule 2: mean below the habit's target and not yet asked today.
    case belowTarget
    /// Rule 3: `maxIntervalDays` without covering an answer.
    case maxInterval
    /// Rule 1: posterior sd above `uncertaintyThreshold`.
    case uncertain
    /// Rule 5: calibration check on a long natural interval.
    case spotCheck

    /// Sort tier ahead of the score (§4.4, D20): re-entry checks first, then struggling habits.
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
    /// Due but over budget, in priority order.
    public let queued: [DueHabit]
}

/// Decides which habits are due, what to ask and in what order (DESIGN.md §4.2–4.4). Pure: all inputs
/// are values, today comes from the injected `Clock`.
///
/// Pauses, paused parents and failing gate parents (§4.5, §4.6) are decided outside the planner and
/// passed in as `unavailable` habit IDs.
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
        if model.mean < habit.targetAdherence, state.lastAskedDay.map({ $0 < today }) ?? true {
            return .belowTarget
        }
        if gapDays(habit: habit, state: state, today: today) >= settings.maxIntervalDays {
            return .maxInterval
        }
        if model.standardDeviation > settings.uncertaintyThreshold {
            return .uncertain
        }
        let interval = try model.naturalIntervalDays(
            threshold: settings.uncertaintyThreshold,
            decayRate: settings.decayPerDay,
            maxDays: settings.maxIntervalDays
        )
        guard interval > SpotCheck.minNaturalIntervalDays else { return nil }
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

    public func question(habit: Habit, state: SchedulerState, today: DayKey, createdAt: Date) -> Question? {
        guard let covers = covers(habit: habit, state: state, today: today) else { return nil }
        return Question(habitID: habit.id, covers: covers, shape: Self.shape(for: covers), createdAt: createdAt)
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

    /// All due, available habits in presentation order: priority tier, then score, then habit ID so
    /// ties are deterministic. Habits without a state use `SchedulerState.initial`.
    public func rankedDue(
        habits: [Habit],
        states: [UUID: SchedulerState],
        unavailable: Set<UUID>,
        today: DayKey
    ) throws -> [DueHabit] {
        try rankedCandidates(habits: habits, states: states, unavailable: unavailable, today: today).map(\.due)
    }

    /// Plans a session: questions for the top `sessionBudget` due habits, the rest queued.
    public func session(
        habits: [Habit],
        states: [UUID: SchedulerState],
        unavailable: Set<UUID> = [],
        clock: some Clock
    ) throws -> SessionPlan {
        let today = clock.today()
        let ranked = try rankedCandidates(habits: habits, states: states, unavailable: unavailable, today: today)
        let questions = ranked.prefix(settings.sessionBudget).compactMap {
            question(habit: $0.habit, state: $0.state, today: today, createdAt: clock.now())
        }
        return SessionPlan(questions: questions, queued: ranked.dropFirst(settings.sessionBudget).map(\.due))
    }

    private struct Candidate {
        let habit: Habit
        let state: SchedulerState
        let due: DueHabit
    }

    private func rankedCandidates(
        habits: [Habit],
        states: [UUID: SchedulerState],
        unavailable: Set<UUID>,
        today: DayKey
    ) throws -> [Candidate] {
        var candidates: [Candidate] = []
        for habit in habits where !unavailable.contains(habit.id) {
            let state = states[habit.id] ?? .initial(habitID: habit.id)
            guard let reason = try dueReason(habit: habit, state: state, today: today) else { continue }
            let due = DueHabit(
                habitID: habit.id,
                reason: reason,
                score: score(habit: habit, state: state, today: today)
            )
            candidates.append(Candidate(habit: habit, state: state, due: due))
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
