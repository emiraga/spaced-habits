import Foundation

/// Everything the projection is rebuilt from (DESIGN.md §3.2): the synced, append-only truth, and the
/// complete export (§11). Clusters, habit revisions and questions are record-keeping: the scheduler and
/// projection never read them.
public struct Truth: Codable, Sendable, Hashable {
    public var habits: [Habit]
    public var clusters: [Cluster]
    /// Snapshot of a habit after each edit, for history and export.
    public var habitRevisions: [HabitRevision]
    /// Every presented question, including dismissed ones ("Later").
    public var questions: [Question]
    public var answers: [Answer]
    public var pauses: [PauseEvent]
    public var healthObservations: [HealthObservation]
    public var settings: Settings

    public enum ValidationError: Error, Equatable {
        case unknownHabit(UUID)
        case unknownCluster(UUID)
    }

    public init(
        habits: [Habit],
        clusters: [Cluster] = [],
        habitRevisions: [HabitRevision] = [],
        questions: [Question] = [],
        answers: [Answer] = [],
        pauses: [PauseEvent] = [],
        healthObservations: [HealthObservation] = [],
        settings: Settings = .default
    ) {
        self.habits = habits
        self.clusters = clusters
        self.habitRevisions = habitRevisions
        self.questions = questions
        self.answers = answers
        self.pauses = pauses
        self.healthObservations = healthObservations
        self.settings = settings
    }

    /// Validates every element, the dependency graph, and that all references name a known habit or cluster.
    public func validate() throws {
        try settings.validate()
        let byID = try Dependencies.index(Dependencies.topologicallySorted(habits))
        func check(_ id: UUID) throws {
            guard byID[id] != nil else { throw ValidationError.unknownHabit(id) }
        }
        try clusters.forEach { try $0.validate() }
        let clusterIDs = Set(clusters.map(\.id))
        for clusterID in habits.compactMap(\.clusterID) where !clusterIDs.contains(clusterID) {
            throw ValidationError.unknownCluster(clusterID)
        }
        for revision in habitRevisions {
            try revision.habit.validate()
            try check(revision.habit.id)
        }
        for question in questions {
            try question.validate()
            try check(question.habitID)
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
