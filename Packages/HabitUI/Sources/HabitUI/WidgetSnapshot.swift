import Foundation
import HabitCore
import HabitStore

/// What the widgets show (DESIGN.md §6): plain values, so a timeline entry can carry them.
public struct WidgetSnapshot: Sendable, Hashable {
    /// A question card. Its `id` is the habit's.
    public struct Card: Sendable, Hashable, Identifiable {
        public let id: UUID
        public let title: String
        public let body: String
        public let colorHex: String
        /// Yes / No buttons; per-day and count questions need the app.
        public let isYesNo: Bool
        /// The day a Yes / No answers: the question's ask day (§4.2).
        public let day: DayKey
        /// "Yesterday" when `day` isn't today (before a due time), for sizes too small for `body`.
        public let dayLabel: String?
    }

    /// A habit with today's glyph. Its `id` is the habit's.
    public struct Row: Sendable, Hashable, Identifiable {
        public let id: UUID
        public let title: String
        public let colorHex: String
        public let status: DayStatus
    }

    public let today: DayKey
    /// The session's cards, in priority order.
    public let cards: [Card]
    /// Every habit due today, including ones beyond the cards.
    public let dueCount: Int
    public let habits: [Row]
    /// "Gym, Tomorrow" (the soonest check-in of a habit not due today).
    public let nextCheckIn: String?

    /// The widget gallery's sample.
    public static let placeholder: WidgetSnapshot = {
        let gym = UUID()
        let read = UUID()
        return WidgetSnapshot(
            today: DayKey(dayNumber: 0),
            cards: [Card(
                id: gym,
                title: String(localized: "🏋️ Gym", bundle: .module),
                body: String(localized: "Done today?", bundle: .module),
                colorHex: HabitPalette.colors[0],
                isYesNo: true,
                day: DayKey(dayNumber: 0),
                dayLabel: nil
            )],
            dueCount: 1,
            habits: [
                Row(
                    id: gym,
                    title: String(localized: "🏋️ Gym", bundle: .module),
                    colorHex: HabitPalette.colors[0],
                    status: .due
                ),
                Row(
                    id: read,
                    title: String(localized: "📚 Read", bundle: .module),
                    colorHex: HabitPalette.colors[1],
                    status: .done
                ),
            ],
            nextCheckIn: nil
        )
    }()
}

public extension AppModel {
    func widgetSnapshot() -> WidgetSnapshot {
        WidgetSnapshot(
            today: today,
            cards: questions.compactMap { question in
                guard let habit = habit(question.habitID) else { return nil }
                let text = QuestionText(question, habits: truth.habits, today: today)
                return WidgetSnapshot.Card(
                    id: habit.id, title: text.title, body: text.body, colorHex: habit.colorHex,
                    isYesNo: question.shape == .singleDay, day: question.covers.upperBound,
                    dayLabel: question.covers.upperBound == today ? nil : DayFormat.short(
                        question.covers.upperBound,
                        today: today
                    )
                )
            },
            dueCount: dueHabitIDs.count,
            habits: activeHabits.map {
                WidgetSnapshot.Row(
                    id: $0.id,
                    title: $0.displayName,
                    colorHex: $0.colorHex,
                    status: todayStatus(of: $0.id)
                )
            },
            nextCheckIn: nextCheckIn().map {
                String(
                    localized: "\($0.habit.name), \(DayFormat.checkIn($0.day, dueTime: $0.habit.dueTime, today: today))",
                    bundle: .module
                )
            }
        )
    }
}

/// Widget timelines (DESIGN.md §6): an entry now, one at each active habit's due time before the next day
/// boundary, and one at that boundary. Otherwise the plan only changes when truth does, and every writer (app,
/// widget, Siri) reloads the timelines then.
public enum WidgetTimeline {
    @MainActor
    public static func entries(
        store: TruthStore,
        timeZone: TimeZone,
        defaults: UserDefaults,
        now: Date
    ) throws -> [(date: Date, snapshot: WidgetSnapshot)] {
        func model(at date: Date) throws -> AppModel {
            try AppModel(store: store, timeZone: timeZone, defaults: defaults, logsPresentedQuestions: false) {
                FixedClock(date: date, calendar: $0)
            }
        }
        let current = try model(at: now)
        let startHour = current.truth.settings.dayStartHour
        let calendar = try DayCalendar(timeZone: timeZone, dayStartHour: startHour)
        let boundary = try calendar.date(
            calendar.dayKey(for: now).adding(days: 1), at: TimeOfDay(hour: startHour, minute: 0)
        )
        let later = try (calendar.dueDates(current.dueTimes, after: now, before: boundary) + [boundary]).map {
            try ($0, model(at: $0).widgetSnapshot())
        }
        return [(now, current.widgetSnapshot())] + later
    }
}
