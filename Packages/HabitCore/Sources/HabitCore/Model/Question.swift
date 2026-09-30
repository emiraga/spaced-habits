import Foundation

/// One question presented to the user (DESIGN.md §3.3). Created lazily by the planner at presentation
/// time; a dismissed question is re-planned, never carried as scheduler state (§4.4). Presented
/// questions are logged in `Truth.questions` for history and export only.
public struct Question: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let habitID: UUID
    /// The days this question is about (≤ `maxRecallGapDays`).
    public let covers: ClosedRange<DayKey>
    public let shape: QuestionShape
    public let createdAt: Date
    public var presentedAt: Date?
    /// "Later": snoozes the habit (`Snooze`, §4.4), then it is re-planned.
    public var dismissedAt: Date?
    /// Where "Later" was pressed: after a notification's, a notification asks again when the snooze ends
    /// (§8); a card comes back quietly. Nil for dismissals logged before it was recorded.
    public var dismissedVia: Channel?
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
        dismissedVia: Channel? = nil,
        parentContext: ParentContext? = nil
    ) {
        self.id = id
        self.habitID = habitID
        self.covers = covers
        self.shape = shape
        self.createdAt = createdAt
        self.presentedAt = presentedAt
        self.dismissedAt = dismissedAt
        self.dismissedVia = dismissedVia
        self.parentContext = parentContext
    }

    public enum ValidationError: Error, Equatable {
        case singleDayCoversSeveralDays(Int)
        case perDayEmpty
        case perDayOutsideCovers(DayKey)
        case countOutOfRange(total: Int, coverDays: Int)
        case negativeParentDoneDays(Int)
    }

    /// Checks `shape` is consistent with `covers`. Run on questions logged by widgets, watch and import.
    public func validate() throws {
        switch shape {
        case .singleDay:
            guard covers.count == 1 else { throw ValidationError.singleDayCoversSeveralDays(covers.count) }
        case let .perDay(days):
            guard !days.isEmpty else { throw ValidationError.perDayEmpty }
            if let outside = days.first(where: { !covers.contains($0) }) {
                throw ValidationError.perDayOutsideCovers(outside)
            }
        case let .count(total):
            guard (1 ... covers.count).contains(total) else {
                throw ValidationError.countOutOfRange(total: total, coverDays: covers.count)
            }
        }
        if let parentContext, parentContext.parentDoneDays < 0 {
            throw ValidationError.negativeParentDoneDays(parentContext.parentDoneDays)
        }
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
