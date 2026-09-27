import Foundation
import HabitCore
import HabitStore
import Observation

/// The app's state and actions (DESIGN.md §4.4, §5): loads truth, projects it, plans the session and
/// records answers. Every change is persisted before the in-memory state moves on, then re-projected.
///
/// A session starts on launch, on foreground and on pull-to-refresh (`startSession`). "Later" hides a
/// habit until the next session; a shown card keeps its question (and ID) until it is answered or its
/// covers change.
@MainActor
@Observable
public final class AppModel {
    public internal(set) var truth: Truth
    public private(set) var projected: Projected
    /// The cards to show now, in priority order.
    public private(set) var questions: [Question] = []
    /// Why each shown habit is asked.
    public private(set) var reasons: [UUID: DueReason] = [:]
    /// Due habits beyond the session budget ("More…").
    public private(set) var queuedCount = 0
    /// Every habit that is due today, including ones put off with "Later".
    public private(set) var dueHabitIDs: Set<UUID> = []
    /// Debug "advance day" offset (§13 M2); 0 in normal use.
    public private(set) var dayOffset: Int
    public private(set) var clock: ShiftedClock
    /// Built from `truth.settings`, which is validated before it is stored.
    public private(set) var planner: QuestionPlanner

    @ObservationIgnored let store: TruthStore
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let baseClock: @Sendable (DayCalendar) -> any Clock
    @ObservationIgnored private var laterHabitIDs: Set<UUID> = []
    @ObservationIgnored private var extraBudget = 0
    @ObservationIgnored private var shownQuestions: [UUID: Question] = [:]

    static let dayOffsetKey = "debug.dayOffset"

    /// `baseClock` makes the real clock for a calendar (`SystemClock` in the app, `FixedClock` in tests);
    /// `defaults` holds the debug day offset.
    public init(
        store: TruthStore,
        timeZone: TimeZone,
        defaults: UserDefaults,
        baseClock: @escaping @Sendable (DayCalendar) -> any Clock
    ) throws {
        self.store = store
        self.timeZone = timeZone
        self.defaults = defaults
        self.baseClock = baseClock
        let truth = try store.load()
        let dayOffset = defaults.integer(forKey: Self.dayOffsetKey)
        let clock = try Self.makeClock(
            timeZone: timeZone, settings: truth.settings, dayOffset: dayOffset, baseClock: baseClock
        )
        self.truth = truth
        self.dayOffset = dayOffset
        self.clock = clock
        planner = try QuestionPlanner(settings: truth.settings)
        projected = try Projection.rebuild(truth, clock: clock)
        try refresh()
    }

    public var today: DayKey {
        clock.today()
    }

    // MARK: Session

    /// Re-plans from scratch: "Later" cards come back and "More…" resets.
    public func startSession() throws {
        laterHabitIDs = []
        extraBudget = 0
        try refresh()
    }

    /// Records an answer. A `.delayed` answer also pauses the habit from today (§4.6).
    public func answer(_ question: Question, with value: AnswerValue) throws {
        try record(question, value, delayReason: .manual)
    }

    /// "Delay…" on a card: pauses the habit for `days` days starting today, logged as a `.delayed` answer.
    public func delay(_ question: Question, days: Int, reason: PauseReason) throws {
        try record(question, .delayed(days: days), delayReason: reason)
    }

    private func record(_ question: Question, _ value: AnswerValue, delayReason: PauseReason) throws {
        let answer = Answer(
            questionID: question.id, habitID: question.habitID, covers: question.covers, value: value,
            answeredAt: clock.now(), timezone: timeZone.identifier, channel: .app
        )
        let pause = try Pauses.event(forDelay: answer, reason: delayReason, createdAt: clock.now())
        try store.append(answer)
        truth.answers.append(answer)
        if let pause {
            try store.save(pause, at: clock.now())
            truth.pauses.append(pause)
        }
        shownQuestions[question.habitID] = nil
        try refresh()
    }

    /// "Later": logs the dismissal and hides the habit until the next session (§4.4).
    public func later(_ question: Question) throws {
        var dismissed = question
        dismissed.dismissedAt = clock.now()
        try store.save(dismissed, at: clock.now())
        if let index = truth.questions.firstIndex(where: { $0.id == question.id }) {
            truth.questions[index] = dismissed
        }
        laterHabitIDs.insert(question.habitID)
        shownQuestions[question.habitID] = nil
        try refresh()
    }

    /// "More…": shows another budget's worth of queued questions.
    public func showMore() throws {
        extraBudget += truth.settings.sessionBudget
        try refresh()
    }

    // MARK: Editing

    /// A new, unsaved habit created today.
    public func newHabitDraft() -> Habit {
        Habit(
            name: "", colorHex: HabitPalette.colors[truth.habits.count % HabitPalette.colors.count],
            createdAt: clock.now(), createdDay: today
        )
    }

    /// Creates or edits a habit.
    public func save(_ habit: Habit) throws {
        try save([habit])
    }

    /// Creates or edits several habits, validating the resulting dependency graph before writing any.
    func save(_ edited: [Habit]) throws {
        var habits = truth.habits
        for habit in edited {
            if let index = habits.firstIndex(where: { $0.id == habit.id }) {
                habits[index] = habit
            } else {
                habits.append(habit)
            }
        }
        try edited.forEach { try $0.validate() }
        try Dependencies.validate(habits)
        for habit in edited {
            let revision = try store.save(habit, editedAt: clock.now())
            truth.habitRevisions.append(revision)
        }
        truth.habits = habits
        try refresh()
    }

    public func save(_ settings: Settings) throws {
        let planner = try QuestionPlanner(settings: settings)
        let clock = try Self.makeClock(
            timeZone: timeZone, settings: settings, dayOffset: dayOffset, baseClock: baseClock
        )
        try store.save(settings, at: clock.now())
        truth.settings = settings
        self.planner = planner
        self.clock = clock
        try refresh()
    }

    // MARK: Debug

    /// Moves the clock one day ahead and starts a new session (§13 M2 checkpoint).
    public func advanceDay() throws {
        try setDayOffset(dayOffset + 1)
    }

    /// Deletes all truth and resets the day offset.
    public func eraseAll() throws {
        try store.eraseAll()
        truth = Truth(habits: [])
        shownQuestions = [:]
        try setDayOffset(0)
    }

    private struct SampleHabit {
        let name: String
        let emoji: String
        let importance: Importance
    }

    private static let sampleHabits = [
        SampleHabit(name: "Gym", emoji: "🏋️", importance: .high),
        SampleHabit(name: "Read", emoji: "📚", importance: .normal),
        SampleHabit(name: "Meditate", emoji: "🧘", importance: .low),
    ]

    /// Three sample habits, created today.
    public func addSampleHabits() throws {
        for sample in Self.sampleHabits {
            var habit = newHabitDraft()
            habit.name = sample.name
            habit.emoji = sample.emoji
            habit.importance = sample.importance
            try save(habit)
        }
    }

    private func setDayOffset(_ offset: Int) throws {
        clock = try Self.makeClock(
            timeZone: timeZone, settings: truth.settings, dayOffset: offset, baseClock: baseClock
        )
        dayOffset = offset
        defaults.set(offset, forKey: Self.dayOffsetKey)
        try startSession()
    }

    // MARK: Planning

    /// Re-projects and re-plans; logs newly shown questions to `Truth.questions` (§4.4).
    func refresh() throws {
        projected = try Projection.rebuild(truth, clock: clock)
        let today = clock.today()
        let unavailable = try Set(Pauses.unavailable(on: today, habits: truth.habits, pauses: truth.pauses).keys)
        let due = try planner.rankedDue(
            habits: truth.habits, states: projected.states, records: projected.records, unavailable: unavailable,
            today: today
        )
        var settings = truth.settings
        settings.sessionBudget += extraBudget
        let plan = try QuestionPlanner(settings: settings).session(
            habits: truth.habits, states: projected.states, records: projected.records,
            unavailable: unavailable.union(laterHabitIDs), clock: clock
        )
        var shown: [Question] = []
        for question in plan.questions {
            if let previous = shownQuestions[question.habitID], Self.asksTheSame(previous, question) {
                shown.append(previous)
                continue
            }
            var presented = question
            presented.presentedAt = clock.now()
            try store.save(presented, at: clock.now())
            truth.questions.append(presented)
            shownQuestions[question.habitID] = presented
            shown.append(presented)
        }
        questions = shown
        reasons = Dictionary(uniqueKeysWithValues: plan.presented.map { ($0.habitID, $0.reason) })
        queuedCount = plan.queued.count
        dueHabitIDs = Set(due.map(\.habitID))
    }

    /// Same card content, ignoring ID and timestamps.
    private static func asksTheSame(_ lhs: Question, _ rhs: Question) -> Bool {
        lhs.covers == rhs.covers && lhs.shape == rhs.shape && lhs.parentContext == rhs.parentContext
    }

    private static func makeClock(
        timeZone: TimeZone,
        settings: Settings,
        dayOffset: Int,
        baseClock: (DayCalendar) -> any Clock
    ) throws -> ShiftedClock {
        let calendar = try DayCalendar(timeZone: timeZone, dayStartHour: settings.dayStartHour)
        return ShiftedClock(base: baseClock(calendar), days: dayOffset)
    }
}
