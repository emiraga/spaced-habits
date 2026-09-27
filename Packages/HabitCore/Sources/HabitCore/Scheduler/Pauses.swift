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
    public static func event(forDelay answer: Answer, createdAt: Date) throws -> PauseEvent? {
        guard case let .delayed(days) = answer.value else { return nil }
        try answer.validate()
        let start = answer.covers.upperBound
        return PauseEvent(
            habitIDs: [answer.habitID],
            start: start,
            end: start.adding(days: days - 1),
            reason: .manual,
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
        let active = pauses.filter { $0.start <= day && day <= $0.end }
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
}
