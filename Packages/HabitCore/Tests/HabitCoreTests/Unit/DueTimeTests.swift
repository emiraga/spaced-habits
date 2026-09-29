import Foundation
@testable import HabitCore
import Testing

/// Per-habit due time and ask day (DESIGN.md §4.2).
private func calendar(_ zone: String = "UTC", dayStartHour: Int = 4) throws -> DayCalendar {
    try DayCalendar(timeZone: #require(TimeZone(identifier: zone)), dayStartHour: dayStartHour)
}

private func day(_ string: String) throws -> DayKey {
    try #require(DayKey(string))
}

/// The instant at local `hour:minute` on the civil date `date` in `calendar`'s zone.
private func instant(_ calendar: DayCalendar, _ date: String, _ hour: Int, _ minute: Int = 0) throws -> Date {
    try calendar.date(day(date), at: TimeOfDay(hour: hour, minute: minute))
}

struct AskDayTests {
    @Test func noDueTimeIsAlwaysToday() throws {
        let utc = try calendar()
        for hour in [4, 12, 23, 3] {
            let date = try instant(utc, hour < 4 ? "2026-09-28" : "2026-09-27", hour)
            #expect(utc.askDay(for: date, at: nil) == utc.dayKey(for: date))
        }
    }

    @Test func yesterdayBeforeTheDueTimeTodayFromItOn() throws {
        let utc = try calendar()
        let due = try TimeOfDay(hour: 18, minute: 0)
        let today = try day("2026-09-27")
        #expect(try utc.askDay(for: instant(utc, "2026-09-27", 4), at: due) == today.adding(days: -1))
        #expect(try utc.askDay(for: instant(utc, "2026-09-27", 17, 59), at: due) == today.adding(days: -1))
        #expect(try utc.askDay(for: instant(utc, "2026-09-27", 18), at: due) == today)
        #expect(try utc.askDay(for: instant(utc, "2026-09-27", 23, 30), at: due) == today)
        // 02:00 on the 28th is still habit day 27.
        #expect(try utc.askDay(for: instant(utc, "2026-09-28", 2), at: due) == today)
    }

    @Test func dueTimeBeforeDayStartIsLateThatNight() throws {
        let utc = try calendar()
        let due = try TimeOfDay(hour: 2, minute: 0)
        let today = try day("2026-09-27")
        // Habit day 27 runs 27th 04:00 – 28th 03:59; its due time is 02:00 on the 28th.
        #expect(try utc.askDay(for: instant(utc, "2026-09-27", 23), at: due) == today.adding(days: -1))
        #expect(try utc.askDay(for: instant(utc, "2026-09-28", 1, 59), at: due) == today.adding(days: -1))
        #expect(try utc.askDay(for: instant(utc, "2026-09-28", 2), at: due) == today)
        #expect(try utc.askDay(for: instant(utc, "2026-09-28", 3, 59), at: due) == today)
        #expect(try utc.askDay(for: instant(utc, "2026-09-28", 4), at: due) == today)
    }

    @Test func dueTimeSkippedBySpringForwardPassesAtTheJump() throws {
        // Berlin, 2026-03-29: 02:00 → 03:00. With the day starting at midnight, 02:30 never happens.
        let berlin = try calendar("Europe/Berlin", dayStartHour: 0)
        let due = try TimeOfDay(hour: 2, minute: 30)
        let today = try day("2026-03-29")
        let jump = try instant(berlin, "2026-03-29", 1, 59).addingTimeInterval(60)
        #expect(try berlin.askDay(for: instant(berlin, "2026-03-29", 1, 59), at: due) == today.adding(days: -1))
        #expect(berlin.askDay(for: jump, at: due) == today)
    }

    @Test func dueTimeRepeatedByFallBackStaysPassed() throws {
        // Berlin, 2026-10-25: 03:00 → 02:00, so 02:00–02:59 happens twice.
        let berlin = try calendar("Europe/Berlin", dayStartHour: 0)
        let due = try TimeOfDay(hour: 2, minute: 30)
        let today = try day("2026-10-25")
        let firstDue = try instant(berlin, "2026-10-25", 2, 30)
        #expect(berlin.askDay(for: firstDue.addingTimeInterval(-60), at: due) == today.adding(days: -1))
        #expect(berlin.askDay(for: firstDue, at: due) == today)
        // 45 minutes later the wall clock reads 02:15 again.
        #expect(berlin.askDay(for: firstDue.addingTimeInterval(45 * 60), at: due) == today)
    }

    @Test func clocksReportTheAskDay() throws {
        let utc = try calendar()
        let due = try TimeOfDay(hour: 18, minute: 0)
        let morning = try FixedClock(date: instant(utc, "2026-09-27", 9), calendar: utc)
        #expect(try morning.askDay(dueTime: due) == day("2026-09-26"))
        #expect(morning.askDay(dueTime: nil) == morning.today())
        #expect(try ShiftedClock(base: morning, days: 2).askDay(dueTime: due) == day("2026-09-28"))
    }
}

struct DueTimePlanningTests {
    private let today = DayKey(dayNumber: 20723) // 2026-09-27

    private func clock(_ hour: Int) throws -> FixedClock {
        let utc = try calendar()
        return try FixedClock(date: instant(utc, today.description, hour), calendar: utc)
    }

    private func habit(createdDaysAgo: Int = 30) throws -> Habit {
        try Habit(
            name: "Gym", colorHex: "#00AA00", createdAt: Date(timeIntervalSince1970: 0),
            createdDay: today.adding(days: -createdDaysAgo), dueTime: TimeOfDay(hour: 18, minute: 0)
        )
    }

    /// Uncertain enough to be due whenever something is uncovered.
    private func state(_ habit: Habit, coveredThrough: DayKey) -> SchedulerState {
        SchedulerState(habitID: habit.id, alpha: 2, beta: 2, lastCoveredDay: coveredThrough)
    }

    private func session(_ habit: Habit, _ state: SchedulerState?, at hour: Int) throws -> SessionPlan {
        try QuestionPlanner(settings: .default).session(
            habits: [habit], states: state.map { [habit.id: $0] } ?? [:], records: [:], clock: clock(hour)
        )
    }

    @Test func beforeTheDueTimeAsksAboutYesterday() throws {
        let gym = try habit()
        let plan = try session(gym, state(gym, coveredThrough: today.adding(days: -3)), at: 9)
        let question = try #require(plan.questions.first)
        #expect(question.covers == today.adding(days: -2) ... today.adding(days: -1))
    }

    @Test func yesterdayCoveredIsNotDueUntilTheDueTime() throws {
        let gym = try habit()
        let covered = state(gym, coveredThrough: today.adding(days: -1))
        #expect(try session(gym, covered, at: 17).questions.isEmpty)
        let question = try #require(try session(gym, covered, at: 18).questions.first)
        #expect(question.covers == today ... today)
    }

    @Test func habitCreatedTodayIsNotAskedAboutYesterday() throws {
        let fresh = try habit(createdDaysAgo: 0)
        #expect(try session(fresh, nil, at: 9).questions.isEmpty)
        #expect(try session(fresh, nil, at: 18).questions.first?.covers == today ... today)
    }

    @Test func nextCheckInCanBeToday() throws {
        let gym = try habit()
        var covered = state(gym, coveredThrough: today.adding(days: -1))
        covered.currentIntervalDays = 1
        let askDay = try clock(9).askDay(dueTime: gym.dueTime)
        #expect(try QuestionPlanner(settings: .default)
            .nextCheckIn(habit: gym, state: covered, askDay: askDay) == today)
    }

    @Test func pausedOnTheAskDayIsUnavailable() throws {
        let gym = try habit()
        let yesterdayOnly = PauseEvent(
            habitIDs: [gym.id], start: today.adding(days: -1), end: today.adding(days: -1), reason: .manual,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        #expect(try Pauses.unavailable(habits: [gym], pauses: [yesterdayOnly], clock: clock(9)) == [gym.id])
        #expect(try Pauses.unavailable(habits: [gym], pauses: [yesterdayOnly], clock: clock(18)).isEmpty)
    }

    @Test func blockedByAParentPausedOnTheChildsAskDay() throws {
        var parent = try habit()
        parent.dueTime = nil
        var child = try habit()
        child.dependencies = [Dependency(parentID: parent.id)]
        let yesterdayOnly = PauseEvent(
            habitIDs: [parent.id], start: today.adding(days: -1), end: today.adding(days: -1), reason: .manual,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        #expect(try Pauses.unavailable(habits: [parent, child], pauses: [yesterdayOnly], clock: clock(9)) == [child.id])
    }

    @Test func delayBeforeTheDueTimePausesFromYesterday() throws {
        let gym = try habit()
        let plan = try session(gym, state(gym, coveredThrough: today.adding(days: -2)), at: 9)
        let question = try #require(plan.questions.first)
        let answer = try Answer(
            questionID: question.id, habitID: gym.id, covers: question.covers, value: .delayed(days: 3),
            answeredAt: clock(9).now(), timezone: "UTC", channel: .app
        )
        let pause = try #require(try Pauses.event(forDelay: answer, createdAt: clock(9).now()))
        #expect(pause.start == today.adding(days: -1))
        #expect(pause.end == today.adding(days: 1))
    }

    @Test func dueTimeRoundTripsAndOldPayloadsDecodeWithout() throws {
        let gym = try habit()
        let decoded = try JSONDecoder().decode(Habit.self, from: JSONEncoder().encode(gym))
        #expect(decoded == gym)
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(gym)) as? [String: Any])
        legacy["dueTime"] = nil
        let old = try JSONDecoder().decode(Habit.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(old.dueTime == nil)
    }
}
