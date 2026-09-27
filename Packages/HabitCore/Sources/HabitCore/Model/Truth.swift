import Foundation

/// Everything the projection is rebuilt from (DESIGN.md §3.2): the synced, append-only truth.
public struct Truth: Codable, Sendable, Hashable {
    public var habits: [Habit]
    public var answers: [Answer]
    public var pauses: [PauseEvent]
    public var healthObservations: [HealthObservation]
    public var settings: Settings

    public enum ValidationError: Error, Equatable {
        case unknownHabit(UUID)
    }

    public init(
        habits: [Habit],
        answers: [Answer] = [],
        pauses: [PauseEvent] = [],
        healthObservations: [HealthObservation] = [],
        settings: Settings = .default
    ) {
        self.habits = habits
        self.answers = answers
        self.pauses = pauses
        self.healthObservations = healthObservations
        self.settings = settings
    }

    /// Validates every element, the dependency graph, and that all references name a known habit.
    public func validate() throws {
        try settings.validate()
        let byID = try Dependencies.index(Dependencies.topologicallySorted(habits))
        func check(_ id: UUID) throws {
            guard byID[id] != nil else { throw ValidationError.unknownHabit(id) }
        }
        for answer in answers {
            try answer.validate()
            try check(answer.habitID)
        }
        for pause in pauses {
            try pause.validate()
            try pause.habitIDs.forEach(check)
        }
        try healthObservations.map(\.habitID).forEach(check)
    }
}
