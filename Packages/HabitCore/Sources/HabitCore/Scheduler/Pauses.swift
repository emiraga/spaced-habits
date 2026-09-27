import Foundation

/// Why a habit is out of play on a day (DESIGN.md §4.5, §4.6).
public enum Unavailability: String, Codable, Sendable, Hashable {
    /// Inside a `PauseEvent` for this habit.
    case paused
    /// A gate parent is paused or blocked, so this habit is moot.
    case blocked

    /// The `DayRecord` source for such a day.
    public var source: DaySource {
        switch self {
        case .paused: .paused
        case .blocked: .blocked
        }
    }
}

/// Pauses, delays and vacation (DESIGN.md §4.6). All three are `PauseEvent`s; this decides their effect
/// on a given day. Freezing the model and the re-entry check are applied by `Projection`.
public enum Pauses {
    /// The pause a `.delayed(days: n)` answer creates: the answer's day through `n - 1` days later.
    /// Nil for any other answer value.
    public static func event(
        forDelay answer: Answer,
        reason: PauseReason = .manual,
        createdAt: Date
    ) throws -> PauseEvent? {
        guard case let .delayed(days) = answer.value else { return nil }
        try answer.validate()
        let start = answer.covers.upperBound
        return PauseEvent(
            habitIDs: [answer.habitID],
            start: start,
            end: start.adding(days: days - 1),
            reason: reason,
            createdAt: createdAt
        )
    }

    /// Paused and blocked habits on `day`; pass the keys to `QuestionPlanner` as `unavailable`.
    ///
    /// Blocking is transitive over active gate edges (`Dependencies.activeGateParentIDs`): a child of
    /// a blocked habit is blocked too. A habit that is itself paused is `.paused`, never `.blocked`.
    public static func unavailable(
        on day: DayKey,
        habits: [Habit],
        pauses: [PauseEvent]
    ) throws -> [UUID: Unavailability] {
        let sorted = try Dependencies.topologicallySorted(habits)
        return try unavailable(on: day, sorted: sorted, byID: Dependencies.index(sorted), pauses: pauses)
    }

    /// As above, for callers that already hold the topologically sorted habits and their index.
    static func unavailable(
        on day: DayKey,
        sorted: [Habit],
        byID: [UUID: Habit],
        pauses: [PauseEvent]
    ) throws -> [UUID: Unavailability] {
        let active = pauses.filter { $0.isActive(on: day) }
        var result: [UUID: Unavailability] = [:]
        for habit in sorted {
            if active.contains(where: { $0.habitIDs.contains(habit.id) }) {
                result[habit.id] = .paused
            } else if try Dependencies.activeGateParentIDs(of: habit, in: byID).contains(where: {
                result[$0] != nil
            }) {
                result[habit.id] = .blocked
            }
        }
        return result
    }

    // MARK: Queries for the UI

    /// The first day after `today` on which `habitID` is no longer paused ("Resumes <date>"), or nil if
    /// it is not paused today. Back-to-back and overlapping pauses count as one.
    public static func resumeDay(of habitID: UUID, today: DayKey, pauses: [PauseEvent]) -> DayKey? {
        let own = pauses.filter { $0.habitIDs.contains(habitID) && !$0.isCancelled }
        guard own.contains(where: { $0.isActive(on: today) }) else { return nil }
        var day = today
        while let covering = own.filter({ $0.isActive(on: day) }).map(\.end).max() {
            day = covering.adding(days: 1)
        }
        return day
    }

    /// Pauses of `habitID` in effect on `today` or later, soonest first (ties by ID).
    public static func current(of habitID: UUID, today: DayKey, pauses: [PauseEvent]) -> [PauseEvent] {
        pauses
            .filter { $0.habitIDs.contains(habitID) && !$0.isCancelled && $0.end >= today }
            .sorted { ($0.start, $0.id.uuidString) < ($1.start, $1.id.uuidString) }
    }

    // MARK: Insights

    /// Manual delays at or above which a habit gets the "You keep delaying this" card (§4.6).
    public static let frequentDelayThreshold = 3
    /// The window, in days ending today, in which delays are counted.
    public static let frequentDelayWindowDays = 60

    /// Habits with at least `frequentDelayThreshold` manual pauses starting in the last
    /// `frequentDelayWindowDays` days. Cancelled pauses don't count: the user took them back.
    public static func frequentlyDelayedHabitIDs(pauses: [PauseEvent], today: DayKey) -> Set<UUID> {
        let counts = delayCounts(pauses: pauses, startingIn: today.adding(days: 1 - frequentDelayWindowDays) ... today)
        return Set(counts.filter { $0.value >= frequentDelayThreshold }.keys)
    }

    /// Manual, uncancelled pauses per habit that start in `days`: the "Delays" stat tile (§12) and the
    /// delayed-often card.
    public static func delayCounts(pauses: [PauseEvent], startingIn days: ClosedRange<DayKey>) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        let delays = pauses.filter { $0.reason == .manual && !$0.isCancelled && days.contains($0.start) }
        for habitID in delays.flatMap({ Set($0.habitIDs) }) {
            counts[habitID, default: 0] += 1
        }
        return counts
    }
}
