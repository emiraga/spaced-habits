import Foundation

/// One local notification to schedule (DESIGN.md §8).
public struct PlannedNotification: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// The slot's top-priority question and how many habits are due then (≥ 1, grouped into one).
        case question(Question, dueCount: Int)
        /// Nothing is due but `onlyWhenQuestionsDue` is off.
        case reminder
        /// No answer since `lastActiveDay` (§4.6): offer vacation mode from the day after.
        case silenceNudge(lastActiveDay: DayKey)
    }

    public let fireAt: Date
    /// The habit day the slot falls on.
    public let day: DayKey
    public let kind: Kind

    public init(fireAt: Date, day: DayKey, kind: Kind) {
        self.fireAt = fireAt
        self.day = day
        self.kind = kind
    }
}

/// Decides which notifications to schedule (DESIGN.md §8). Pure: the app replaces every pending
/// notification with `plan`'s output whenever truth changes, on foreground and on background refresh.
///
/// A slot's content is what the app would plan at that instant if nothing were answered before it: the
/// projection and planner run with a clock at the slot, so decay, pauses, gates and spot checks all apply.
public enum NotificationPlanner {
    /// Days ahead to plan. Background refresh and every app open extend it.
    public static let horizonDays = 7
    /// iOS keeps at most 64 pending local notifications per app.
    public static let maxNotifications = 60

    public static func plan(truth: Truth, calendar: DayCalendar, now: Date) throws -> [PlannedNotification] {
        let settings = truth.settings.notifications
        guard let lastActive = lastActiveDay(truth: truth, calendar: calendar) else { return [] }
        let today = calendar.dayKey(for: now)
        var horizon = today.adding(days: horizonDays)
        if case let .everyNDays(days, _) = settings.cadence {
            horizon = max(horizon, today.adding(days: days))
        }
        let nudgeDay = settings.nudgeAfterSilentDays.map { lastActive.adding(days: $0) }
        let planner = try QuestionPlanner(settings: truth.settings)

        var projections: [DayKey: Projected] = [:]
        var questions: [PlannedNotification] = []
        var nudge: PlannedNotification?
        let candidates = slots(settings, calendar: calendar, after: now, through: max(horizon, nudgeDay ?? horizon))
        for (fireAt, day) in candidates where !Vacation.quietsNotifications(on: day, pauses: truth.pauses) {
            if nudge == nil, day == nudgeDay, !truth.pauses.contains(where: { $0.isActive(on: day) }) {
                nudge = PlannedNotification(fireAt: fireAt, day: day, kind: .silenceNudge(lastActiveDay: lastActive))
                continue
            }
            guard day <= horizon, isCadenceDay(day, settings.cadence, lastActive: lastActive) else { continue }
            let clock = FixedClock(date: fireAt, calendar: calendar)
            let projected = try projections[day] ?? Projection.rebuild(truth, clock: clock)
            projections[day] = projected
            let kind = try slotKind(truth: truth, projected: projected, planner: planner, clock: clock)
            if let kind {
                questions.append(PlannedNotification(fireAt: fireAt, day: day, kind: kind))
            } else if !settings.onlyWhenQuestionsDue {
                questions.append(PlannedNotification(fireAt: fireAt, day: day, kind: .reminder))
            }
        }
        guard let nudge else { return Array(questions.prefix(maxNotifications)) }
        return (questions.prefix(maxNotifications - 1) + [nudge]).sorted { $0.fireAt < $1.fireAt }
    }

    /// The day of the latest answer, or the earliest active habit's `createdDay` before any. Nil without
    /// active habits, when there is nothing to notify about.
    public static func lastActiveDay(truth: Truth, calendar: DayCalendar) -> DayKey? {
        let active = truth.habits.filter { !$0.isArchived }
        guard let created = active.map(\.createdDay).min() else { return nil }
        return truth.answers.map { calendar.dayKey(for: $0.answeredAt) }.max() ?? created
    }

    /// Cadence times after `now` on habit days through `last`, minus quiet hours. `.everyNDays` yields a
    /// slot every day here; `isCadenceDay` thins it, so the silence nudge can use any day's time.
    static func slots(
        _ settings: NotificationSettings,
        calendar: DayCalendar,
        after now: Date,
        through last: DayKey
    ) -> [(fireAt: Date, day: DayKey)] {
        let times = switch settings.cadence {
        case let .timesPerDay(times): Set(times).sorted()
        case let .everyNDays(_, time): [time]
        }
        let audible = times.filter { !(settings.quietHours?.contains(hour: $0.hour) ?? false) }
        // A time before `dayStartHour` on civil date C belongs to habit day C - 1, so scan one extra date.
        let first = calendar.dayKey(for: now)
        return (first ... last.adding(days: 1)).flatMap { date in
            audible.map { time in
                let fireAt = calendar.date(date, at: time)
                return (fireAt: fireAt, day: calendar.dayKey(for: fireAt))
            }
        }
        .filter { $0.fireAt > now && $0.day <= last }
        .sorted { $0.fireAt < $1.fireAt }
    }

    /// `.everyNDays(n)` reminds on every n-th day since the last answer; `.timesPerDay` on every day.
    static func isCadenceDay(_ day: DayKey, _ cadence: NotificationSettings.Cadence, lastActive: DayKey) -> Bool {
        switch cadence {
        case .timesPerDay:
            true
        case let .everyNDays(days, _):
            lastActive.days(to: day) > 0 && lastActive.days(to: day) % days == 0
        }
    }

    /// The top question and due count at `clock`'s instant, or nil when nothing is due. `projected` is as of
    /// `clock`'s day (it depends only on the day).
    private static func slotKind(
        truth: Truth,
        projected: Projected,
        planner: QuestionPlanner,
        clock: FixedClock
    ) throws -> PlannedNotification.Kind? {
        let day = clock.today()
        let unavailable = try Pauses.unavailable(on: day, habits: truth.habits, pauses: truth.pauses)
        let session = try planner.session(
            habits: truth.habits, states: projected.states, records: projected.records,
            unavailable: Set(unavailable.keys), clock: clock
        )
        guard let top = session.questions.first else { return nil }
        return .question(top, dueCount: session.questions.count + session.queued.count)
    }
}
