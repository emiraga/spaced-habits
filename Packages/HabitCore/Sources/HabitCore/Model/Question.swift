import Foundation

/// One question presented to the user (DESIGN.md §3.3). Created lazily by the planner at presentation
/// time; a dismissed question is discarded and re-planned, never carried as state (§4.4).
public struct Question: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let habitID: UUID
    /// The days this question is about (≤ `maxRecallGapDays`).
    public let covers: ClosedRange<DayKey>
    public let shape: QuestionShape
    public let createdAt: Date
    public var presentedAt: Date?
    /// "Later": re-planned next session.
    public var dismissedAt: Date?
    /// For gated habits: how many days in `covers` the parents were done (§4.5).
    public var parentContext: ParentContext?

    public init(
        id: UUID = UUID(),
        habitID: UUID,
        covers: ClosedRange<DayKey>,
        shape: QuestionShape,
        createdAt: Date,
        presentedAt: Date? = nil,
        dismissedAt: Date? = nil,
        parentContext: ParentContext? = nil
    ) {
        self.id = id
        self.habitID = habitID
        self.covers = covers
        self.shape = shape
        self.createdAt = createdAt
        self.presentedAt = presentedAt
        self.dismissedAt = dismissedAt
        self.parentContext = parentContext
    }
}

public enum QuestionShape: Codable, Sendable, Hashable {
    /// "Did you do X today?" (gap == 1)
    case singleDay
    /// One toggle per listed day (gap 2...3, or the parent-done days of a gated habit).
    case perDay(days: [DayKey])
    /// Stepper "N of K days" (gap 4...maxRecallGap, or K = parent-done days).
    case count(total: Int)
}

/// "You did Gym on 4 of 6 days." Shown on cards of gated habits.
public struct ParentContext: Codable, Sendable, Hashable {
    public let parentIDs: [UUID]
    /// round(Σ parent value over `covers`); the `total` of a gated `count` question.
    public let parentDoneDays: Int

    public init(parentIDs: [UUID], parentDoneDays: Int) {
        self.parentIDs = parentIDs
        self.parentDoneDays = parentDoneDays
    }
}
