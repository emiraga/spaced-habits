import Foundation

/// Vacation mode (DESIGN.md §4.6): one `PauseEvent` with reason `.vacation` over every active habit the
/// user doesn't keep. The kept set starts from each habit's `vacationBehavior` and is written back, so the
/// next vacation remembers it.
public enum Vacation {
    public enum ValidationError: Error, Equatable {
        /// Every active habit is kept, so the vacation would pause nothing.
        case nothingToPause
    }

    /// Active habits whose `vacationBehavior` is `.keep`: the checklist's initial state.
    public static func defaultKept(_ habits: [Habit]) -> Set<UUID> {
        Set(habits.filter { !$0.isArchived && $0.vacationBehavior == .keep }.map(\.id))
    }

    /// What the vacation sheet collects.
    public struct Plan: Sendable, Hashable {
        public var start: DayKey
        public var end: DayKey
        /// Habits that keep being asked; every other active habit is paused.
        public var kept: Set<UUID>
        public var quietAllNotifications: Bool

        public init(start: DayKey, end: DayKey, kept: Set<UUID>, quietAllNotifications: Bool = false) {
            self.start = start
            self.end = end
            self.kept = kept
            self.quietAllNotifications = quietAllNotifications
        }
    }

    /// The vacation pausing every active habit not in `plan.kept`, in `habits` order.
    public static func event(for plan: Plan, habits: [Habit], createdAt: Date) throws -> PauseEvent {
        let paused = habits.filter { !$0.isArchived && !plan.kept.contains($0.id) }.map(\.id)
        guard !paused.isEmpty else { throw ValidationError.nothingToPause }
        let event = PauseEvent(
            habitIDs: paused,
            start: plan.start,
            end: plan.end,
            reason: .vacation,
            createdAt: createdAt,
            quietAllNotifications: plan.quietAllNotifications
        )
        try event.validate()
        return event
    }

    /// Kept habits that the vacation would block because a gate parent (transitively) is paused.
    /// The vacation sheet offers "Also keep parents" (`keepingParents`) or accepting the block.
    public static func blockedKept(habits: [Habit], kept: Set<UUID>) throws -> Set<UUID> {
        let active = habits.filter { !$0.isArchived }
        let paused = active.filter { !kept.contains($0.id) }.map(\.id)
        guard !paused.isEmpty else { return [] }
        // Unavailability doesn't depend on the day, only on which habits the pause lists.
        let day = DayKey(dayNumber: 0)
        let probe = PauseEvent(habitIDs: paused, start: day, end: day, reason: .vacation, createdAt: .distantPast)
        let unavailable = try Pauses.unavailable(on: day, habits: habits, pauses: [probe])
        return Set(unavailable.filter { $0.value == .blocked }.keys).intersection(kept)
    }

    /// `kept` plus every active gate ancestor of a kept habit, so no kept habit is blocked.
    public static func keepingParents(habits: [Habit], kept: Set<UUID>) throws -> Set<UUID> {
        let byID = try Dependencies.index(habits)
        var result = kept
        var pending = Array(kept)
        while let id = pending.popLast() {
            guard let habit = byID[id] else { continue }
            let parents = try Dependencies.activeGateParentIDs(of: habit, in: byID)
            pending += parents.filter { result.insert($0).inserted }
        }
        return result
    }

    /// Active habits whose `vacationBehavior` differs from the checklist, updated to match it.
    public static func rememberingChoices(habits: [Habit], kept: Set<UUID>) -> [Habit] {
        habits.compactMap { habit in
            guard !habit.isArchived else { return nil }
            let behavior: VacationBehavior = kept.contains(habit.id) ? .keep : .pause
            guard habit.vacationBehavior != behavior else { return nil }
            var updated = habit
            updated.vacationBehavior = behavior
            return updated
        }
    }

    /// The vacation in effect today or, failing that, the next scheduled one.
    public static func current(pauses: [PauseEvent], today: DayKey) -> PauseEvent? {
        pauses
            .filter { $0.reason == .vacation && !$0.isCancelled && $0.end >= today }
            .min { ($0.start, $0.id.uuidString) < ($1.start, $1.id.uuidString) }
    }

    /// Whether a vacation with "Quiet all notifications" is in effect on `day` (read by notifications, M5).
    public static func quietsNotifications(on day: DayKey, pauses: [PauseEvent]) -> Bool {
        pauses.contains { $0.reason == .vacation && $0.quietAllNotifications && $0.isActive(on: day) }
    }
}
