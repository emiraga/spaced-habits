import HabitCore

/// A habit-day's glyph (DESIGN.md §5.1). Aggregated and inferred never share a glyph (§1.1).
public enum DayStatus: String, Sendable, Hashable, CaseIterable {
    case done, notDone, health, aggregated, inferred, unknown, paused, blocked
    /// Today only: no answer yet, and the habit is due / not due.
    case due, notDue

    /// The status of a past day in the history list.
    public init(record: DayRecord) {
        switch record.source {
        case .observed: self = record.value >= 0.5 ? .done : .notDone
        case .aggregated: self = .aggregated
        case .health: self = .health
        case .inferred: self = .inferred
        case .unknown: self = .unknown
        case .paused: self = .paused
        case .blocked: self = .blocked
        case .notYetDue: self = .notDue
        }
    }

    /// Today's status in the habit list: an answer, pause or Health sample shows as such; otherwise the
    /// record is only the model's guess, and the glyph says whether the habit is due.
    public static func today(record: DayRecord?, isDue: Bool) -> DayStatus {
        let unanswered: DayStatus = isDue ? .due : .notDue
        guard let record else { return unanswered }
        switch record.source {
        case .inferred, .notYetDue:
            return unanswered
        case .unknown where record.questionID == nil:
            return unanswered
        default:
            return DayStatus(record: record)
        }
    }

    /// A history row's value: answers as stated, counts and estimates as percentages marked as such.
    public static func historyText(_ record: DayRecord) -> String {
        let status = DayStatus(record: record)
        switch status {
        case .aggregated:
            return String(localized: "\(DayFormat.percent(record.value)) (from a count)", bundle: .module)
        case .inferred:
            return String(localized: "~\(DayFormat.percent(record.value)) (estimated)", bundle: .module)
        case .notDone where record.conditionalDenominatorExcluded:
            return String(localized: "Not done (parent not done)", bundle: .module)
        default: return status.label
        }
    }

    public var glyph: String {
        switch self {
        case .done: "✓"
        case .notDone: "✗"
        case .health: "♥"
        case .aggregated: "◐"
        case .inferred: "≈"
        case .unknown: "?"
        case .paused: "⏸"
        case .blocked: "⛔"
        case .due: "○"
        case .notDue: "·"
        }
    }

    /// Spoken by VoiceOver and shown next to the glyph in history.
    public var label: String {
        switch self {
        case .done: String(localized: "Done", bundle: .module)
        case .notDone: String(localized: "Not done", bundle: .module)
        case .health: String(localized: "Done (Health)", bundle: .module)
        case .aggregated: String(localized: "Answered as a count", bundle: .module)
        case .inferred: String(localized: "Estimated", bundle: .module)
        case .unknown: String(localized: "Unknown", bundle: .module)
        case .paused: String(localized: "Paused", bundle: .module)
        case .blocked: String(localized: "Blocked", bundle: .module)
        case .due: String(localized: "Due today", bundle: .module)
        case .notDue: String(localized: "Not due", bundle: .module)
        }
    }
}
