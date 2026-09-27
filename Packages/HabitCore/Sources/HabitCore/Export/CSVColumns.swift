import Foundation

/// Column names and values of the CSV export (DESIGN.md §11). Empty string for absent values; dates are
/// `ExportDate` strings; lists inside a field are `;`-separated.
enum CSVColumns {
    static let habit = [
        "id", "name", "emoji", "color_hex", "created_at", "created_day", "archived_at", "kind", "importance",
        "target_adherence", "max_recall_gap_days", "vacation_behavior", "cluster_id", "health_binding", "notes",
    ]

    /// Every `habit` column but `id`.
    static func values(of habit: Habit) -> [String] {
        [
            habit.name, habit.emoji ?? "", habit.colorHex, date(habit.createdAt), habit.createdDay.description,
            date(habit.archivedAt), habit.kind.rawValue, String(describing: habit.importance),
            String(habit.targetAdherence), String(habit.maxRecallGapDays), habit.vacationBehavior.rawValue,
            id(habit.clusterID), habit.healthBinding.map(healthBinding) ?? "", habit.notes ?? "",
        ]
    }

    static let answer = [
        "id", "question_id", "habit_id", "covers_start", "covers_end", "value", "done", "total", "per_day",
        "delay_days", "answered_at", "timezone", "channel",
    ]

    static func values(_ answer: Answer) -> [String] {
        // value, done, total, per_day, delay_days
        let value: [String] = switch answer.value {
        case .done: ["done", "1", "1", "", ""]
        case .notDone: ["not_done", "0", "1", "", ""]
        case let .perDay(days):
            [
                "per_day", String(days.values.count { $0 }), String(days.count),
                days.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value ? 1 : 0)" }.joined(separator: ";"), "",
            ]
        case let .count(done, total): ["count", String(done), String(total), "", ""]
        case .dontRemember: ["dont_remember", "", "", "", ""]
        case let .delayed(days): ["delayed", "", "", "", String(days)]
        }
        return [
            answer.id.uuidString, answer.questionID.uuidString, answer.habitID.uuidString,
            answer.covers.lowerBound.description, answer.covers.upperBound.description,
        ] + value + [date(answer.answeredAt), answer.timezone, answer.channel.rawValue]
    }

    static let question = [
        "id", "habit_id", "covers_start", "covers_end", "shape", "days", "total", "created_at", "presented_at",
        "dismissed_at", "parent_ids", "parent_done_days",
    ]

    static func values(_ question: Question) -> [String] {
        // shape, days, total
        let shape: [String] = switch question.shape {
        case .singleDay: ["single_day", "", ""]
        case let .perDay(days): ["per_day", days.map(\.description).joined(separator: ";"), ""]
        case let .count(total): ["count", "", String(total)]
        }
        return [
            question.id.uuidString, question.habitID.uuidString, question.covers.lowerBound.description,
            question.covers.upperBound.description,
        ] + shape + [
            date(question.createdAt), date(question.presentedAt), date(question.dismissedAt),
            question.parentContext.map { $0.parentIDs.map(\.uuidString).joined(separator: ";") } ?? "",
            question.parentContext.map { String($0.parentDoneDays) } ?? "",
        ]
    }

    static let pause = [
        "id", "habit_ids", "start", "end", "reason", "reason_text", "created_at", "quiet_all_notifications",
        "cancelled_at",
    ]

    static func values(_ pause: PauseEvent) -> [String] {
        let reason: (String, String) = switch pause.reason {
        case .manual: ("manual", "")
        case .vacation: ("vacation", "")
        case .sick: ("sick", "")
        case let .other(text): ("other", text)
        }
        return [
            pause.id.uuidString, pause.habitIDs.map(\.uuidString).joined(separator: ";"), pause.start.description,
            pause.end.description, reason.0, reason.1, date(pause.createdAt), String(pause.quietAllNotifications),
            date(pause.cancelledAt),
        ]
    }

    static func date(_ date: Date?) -> String {
        date.map(ExportDate.string) ?? ""
    }

    private static func id(_ id: UUID?) -> String {
        id?.uuidString ?? ""
    }

    /// `workout>=30min`, `steps>=8000`, `sleep>=7.5h`, `mindful>=10min`.
    private static func healthBinding(_ binding: HealthBinding) -> String {
        switch binding {
        case let .workout(minutes): "workout>=\(minutes)min"
        case let .steps(steps): "steps>=\(steps)"
        case let .sleep(hours): "sleep>=\(hours)h"
        case let .mindfulMinutes(minutes): "mindful>=\(minutes)min"
        }
    }
}
