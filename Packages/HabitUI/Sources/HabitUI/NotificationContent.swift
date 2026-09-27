import Foundation
import HabitCore

/// What a notification carries back to the app when it is tapped or answered (DESIGN.md §8).
public enum NotificationPayload: Sendable, Hashable {
    /// The question it showed; `.done` / `.notDone` answer it, `.later` logs a dismissal.
    case question(Question)
    /// "Time for a check-in", nothing due when planned.
    case reminder
    /// Silence nudge: opens the vacation sheet starting the day after `lastActiveDay`.
    case silenceNudge(lastActiveDay: DayKey)

    public enum PayloadError: Error, Equatable {
        case notUTF8
        case missingKind
        case unknownKind(String)
        case missingValue(String)
        case invalidDay(String)
    }

    private enum Key {
        static let kind = "kind"
        static let question = "question"
        static let lastActiveDay = "lastActiveDay"
    }

    /// `UNNotificationContent.userInfo`: plain strings, the question as its `HabitCore` JSON.
    public func userInfo() throws -> [String: String] {
        switch self {
        case let .question(question):
            guard let json = try String(bytes: JSONEncoder().encode(question), encoding: .utf8) else {
                throw PayloadError.notUTF8
            }
            return [Key.kind: "question", Key.question: json]
        case .reminder:
            return [Key.kind: "reminder"]
        case let .silenceNudge(lastActiveDay):
            return [Key.kind: "silenceNudge", Key.lastActiveDay: lastActiveDay.description]
        }
    }

    public init(userInfo: [AnyHashable: Any]) throws {
        guard let kind = userInfo[Key.kind] as? String else { throw PayloadError.missingKind }
        func value(_ key: String) throws -> String {
            guard let value = userInfo[key] as? String else { throw PayloadError.missingValue(key) }
            return value
        }
        switch kind {
        case "question":
            let question = try JSONDecoder().decode(Question.self, from: Data(value(Key.question).utf8))
            try question.validate()
            self = .question(question)
        case "reminder":
            self = .reminder
        case "silenceNudge":
            let string = try value(Key.lastActiveDay)
            guard let day = DayKey(string) else { throw PayloadError.invalidDay(string) }
            self = .silenceNudge(lastActiveDay: day)
        default:
            throw PayloadError.unknownKind(kind)
        }
    }
}

/// The actions of `NotificationContent.questionCategory`; raw values are the action identifiers.
public enum NotificationAction: String, CaseIterable, Sendable {
    case done = "YES"
    case notDone = "NO"
    case later = "LATER"

    public var title: String {
        switch self {
        case .done: "Yes"
        case .notDone: "No"
        case .later: "Later"
        }
    }
}

/// A `PlannedNotification` rendered for `UNNotificationRequest` (DESIGN.md §8). Pure, so it is tested
/// without a notification center.
public struct NotificationContent: Sendable, Hashable {
    /// Category of single-day questions: answerable with Yes / No / Later without opening the app. Other
    /// shapes need the card, so their notifications have no category and a tap opens the app.
    public static let questionCategory = "HABIT_QUESTION"
    public static let threadIdentifier = "check-ins"

    public let identifier: String
    public let fireAt: Date
    public let title: String
    public let subtitle: String
    public let body: String
    /// Empty for no actions.
    public let categoryIdentifier: String
    public let payload: NotificationPayload

    /// `shift` moves the fire date (the debug day offset: the plan runs on the shifted clock, notifications
    /// fire on the real one).
    public init(_ planned: PlannedNotification, habits: [Habit], shift: TimeInterval = 0) {
        fireAt = planned.fireAt.addingTimeInterval(shift)
        identifier = "slot-\(Int(fireAt.timeIntervalSince1970))"
        switch planned.kind {
        case let .question(question, dueCount):
            let byID = Dictionary(habits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let habit = byID[question.habitID]
            title = habit.map { [$0.emoji, $0.name].compactMap(\.self).joined(separator: " ") } ?? "Spaced Habits"
            subtitle = dueCount > 1 ? "\(dueCount) habits to review" : ""
            let context = question.parentContext.map { context in
                QuestionCard.contextLine(
                    parentNames: context.parentIDs.compactMap { byID[$0]?.name },
                    context: context,
                    coverDays: question.covers.count
                )
            }
            body = [context, QuestionCard.prompt(for: question)].compactMap(\.self).joined(separator: " ")
            categoryIdentifier = question.shape == .singleDay ? Self.questionCategory : ""
            payload = .question(question)
        case .reminder:
            title = "Spaced Habits"
            subtitle = ""
            body = "Time for a quick check-in."
            categoryIdentifier = ""
            payload = .reminder
        case let .silenceNudge(lastActiveDay):
            let days = lastActiveDay.days(to: planned.day)
            title = "Taking a break?"
            subtitle = ""
            body = "No check-ins for \(days) days. Turn on vacation mode for them so they don't count against you."
            categoryIdentifier = ""
            payload = .silenceNudge(lastActiveDay: lastActiveDay)
        }
    }
}
