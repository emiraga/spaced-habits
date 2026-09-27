import Foundation

/// A user's answer to a `Question` (DESIGN.md §3.3). Truth: append-only.
public struct Answer: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let questionID: UUID
    public let habitID: UUID
    public let covers: ClosedRange<DayKey>
    public let value: AnswerValue
    public let answeredAt: Date
    /// Time zone identifier at answer time, kept for audit (§3.1).
    public let timezone: String
    public let channel: Channel

    public enum ValidationError: Error, Equatable {
        case countOutOfRange(done: Int, total: Int)
        case perDayOutsideCovers(DayKey)
        case perDayEmpty
        case delayNotPositive(Int)
    }

    public init(
        id: UUID = UUID(),
        questionID: UUID,
        habitID: UUID,
        covers: ClosedRange<DayKey>,
        value: AnswerValue,
        answeredAt: Date,
        timezone: String,
        channel: Channel
    ) {
        self.id = id
        self.questionID = questionID
        self.habitID = habitID
        self.covers = covers
        self.value = value
        self.answeredAt = answeredAt
        self.timezone = timezone
        self.channel = channel
    }

    /// Checks `value` is consistent with `covers`. Run on input from widgets, watch, notifications and import.
    public func validate() throws {
        switch value {
        case .done, .notDone, .dontRemember:
            return
        case let .perDay(days):
            guard !days.isEmpty else { throw ValidationError.perDayEmpty }
            if let outside = days.keys.sorted().first(where: { !covers.contains($0) }) {
                throw ValidationError.perDayOutsideCovers(outside)
            }
        case let .count(done, total):
            guard total >= 1, (0 ... total).contains(done) else {
                throw ValidationError.countOutOfRange(done: done, total: total)
            }
        case let .delayed(days):
            guard days >= 1 else { throw ValidationError.delayNotPositive(days) }
        }
    }
}

public enum AnswerValue: Codable, Sendable, Hashable {
    /// `singleDay`: "Yes" / "No".
    case done, notDone
    /// `perDay`; keys are within `covers`.
    case perDay([DayKey: Bool])
    /// `count`
    case count(done: Int, total: Int)
    /// Recorded; the covered days become `.unknown`.
    case dontRemember
    /// Creates a `PauseEvent`; carries no day data.
    case delayed(days: Int)
}

public enum Channel: String, Codable, Sendable, Hashable {
    case app, widget, watch, notification, health
}

/// Pauses one or more habits over an inclusive day range (§4.6). Truth; `end` is edited to extend or
/// end early, `start` may be in the past (backdated) or future (scheduled vacation).
public struct PauseEvent: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var habitIDs: [UUID]
    public var start: DayKey
    public var end: DayKey
    public var reason: PauseReason
    public let createdAt: Date
    /// Vacation only.
    public var quietAllNotifications: Bool

    public enum ValidationError: Error, Equatable {
        case noHabits
        case endBeforeStart(start: DayKey, end: DayKey)
    }

    public init(
        id: UUID = UUID(),
        habitIDs: [UUID],
        start: DayKey,
        end: DayKey,
        reason: PauseReason,
        createdAt: Date,
        quietAllNotifications: Bool = false
    ) {
        self.id = id
        self.habitIDs = habitIDs
        self.start = start
        self.end = end
        self.reason = reason
        self.createdAt = createdAt
        self.quietAllNotifications = quietAllNotifications
    }

    public func validate() throws {
        guard !habitIDs.isEmpty else { throw ValidationError.noHabits }
        guard start <= end else { throw ValidationError.endBeforeStart(start: start, end: end) }
    }

    /// True when `habitID` is paused on `day` by this event.
    public func pauses(_ habitID: UUID, on day: DayKey) -> Bool {
        start <= day && day <= end && habitIDs.contains(habitID)
    }
}

public enum PauseReason: Codable, Sendable, Hashable {
    case manual
    case vacation
    case sick
    case other(String)
}

/// A Health sample that satisfied a habit's `HealthBinding` on a day (§9). Truth: append-only.
public struct HealthObservation: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let habitID: UUID
    public let day: DayKey
    /// HealthKit sample UUID string; makes re-imports of the same sample idempotent.
    public let sampleID: String

    public init(id: UUID = UUID(), habitID: UUID, day: DayKey, sampleID: String) {
        self.id = id
        self.habitID = habitID
        self.day = day
        self.sampleID = sampleID
    }
}
