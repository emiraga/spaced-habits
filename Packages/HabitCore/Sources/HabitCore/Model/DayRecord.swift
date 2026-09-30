import Foundation

/// Derived: one per (habit, day), rebuilt from truth by the projection (DESIGN.md §3.2, §4.7).
public struct DayRecord: Codable, Sendable, Hashable {
    public let habitID: UUID
    public let day: DayKey
    /// Expected value in 0...1.
    public let value: Double
    public let source: DaySource
    /// 1.0 for observed; posterior-based for inferred.
    public let confidence: Double
    public let questionID: UUID?
    /// Gated habit on a day its parent was observed not done: counted in P(B), excluded from P(B|A) (§4.5).
    public let conditionalDenominatorExcluded: Bool

    public init(
        habitID: UUID,
        day: DayKey,
        value: Double,
        source: DaySource,
        confidence: Double,
        questionID: UUID? = nil,
        conditionalDenominatorExcluded: Bool = false
    ) {
        self.habitID = habitID
        self.day = day
        self.value = value
        self.source = source
        self.confidence = confidence
        self.questionID = questionID
        self.conditionalDenominatorExcluded = conditionalDenominatorExcluded
    }
}

/// Projected records keyed by habit, then day.
public typealias DayRecords = [UUID: [DayKey: DayRecord]]

/// How we know a day's value (principle 1.1: honest data).
public enum DaySource: String, Codable, Sendable, Hashable, CaseIterable {
    /// The user answered about this specific day (singleDay / perDay).
    case observed
    /// The user answered "N of K"; value = N/K across the window.
    case aggregated
    /// Auto-filled from HealthKit.
    case health
    /// No answer covers this day; value = model posterior mean.
    case inferred
    /// "Don't remember", or beyond the recall cap with the model too uncertain.
    case unknown
    /// Inside a `PauseEvent` for this habit.
    case paused
    /// A gate parent was paused; this habit is moot.
    case blocked
    /// Future / today-before-answer placeholder (display only).
    case notYetDue

    /// Whether days with this source update the adherence model (§4.1).
    public var feedsModel: Bool {
        switch self {
        case .observed, .aggregated, .health: true
        case .inferred, .unknown, .paused, .blocked, .notYetDue: false
        }
    }
}

/// Derived per-habit scheduler state as of a day (§4.1).
public struct SchedulerState: Codable, Sendable, Hashable {
    public let habitID: UUID
    /// Beta posterior pseudo-count for "did it".
    public var alpha: Double
    /// Beta posterior pseudo-count for "didn't".
    public var beta: Double
    /// `AdherenceModel.answeredMean`: the mean as of the latest evidence (§4.2 rule 2).
    public var answeredMean: Double?
    /// `AdherenceModel.answeredEvidence`: the evidence as of the latest answer (§4.2 rule 2).
    public var answeredEvidence: Double?
    /// Last day any answer or health observation covers.
    public var lastCoveredDay: DayKey?
    public var lastAskedDay: DayKey?
    /// For display and charts ("asking every ~9 days").
    public var currentIntervalDays: Int
    /// Set when a pause ends; cleared by the first answer after it (§4.6).
    public var forcedReentryCheck: Bool

    public init(
        habitID: UUID,
        alpha: Double,
        beta: Double,
        answeredMean: Double? = nil,
        answeredEvidence: Double? = nil,
        lastCoveredDay: DayKey? = nil,
        lastAskedDay: DayKey? = nil,
        currentIntervalDays: Int = 1,
        forcedReentryCheck: Bool = false
    ) {
        self.habitID = habitID
        self.alpha = alpha
        self.beta = beta
        // Nil means "derive it": with evidence it is always set, see `AdherenceModel.init`.
        self.answeredMean = answeredMean ?? AdherenceModel.defaultAnsweredMean(alpha: alpha, beta: beta)
        self.answeredEvidence = answeredEvidence ?? AdherenceModel.defaultAnsweredEvidence(alpha: alpha, beta: beta)
        self.lastCoveredDay = lastCoveredDay
        self.lastAskedDay = lastAskedDay
        self.currentIntervalDays = currentIntervalDays
        self.forcedReentryCheck = forcedReentryCheck
    }
}
