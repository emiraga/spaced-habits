import Foundation
import HabitCore
import Testing

/// 2026-09-27.
private let today = DayKey(dayNumber: 20723)

private func noon(_ day: DayKey) -> Date {
    Date(timeIntervalSince1970: TimeInterval(day.dayNumber * 86400 + 12 * 3600))
}

private let calendar: DayCalendar = {
    do {
        return try DayCalendar(timeZone: .gmt)
    } catch {
        preconditionFailure("GMT calendar: \(error)")
    }
}()

private func time(_ hour: Int, _ minute: Int = 0) throws -> TimeOfDay {
    try TimeOfDay(hour: hour, minute: minute)
}

private func habit(_ name: String = "Gym", createdDaysAgo: Int = 0) -> Habit {
    Habit(name: name, colorHex: "#00AA00", createdAt: noon(today), createdDay: today.adding(days: -createdDaysAgo))
}

private func yes(_ habit: Habit, on day: DayKey) -> Answer {
    Answer(
        questionID: UUID(), habitID: habit.id, covers: day ... day, value: .done, answeredAt: noon(day),
        timezone: "GMT", channel: .app
    )
}

private func truth(
    _ habits: [Habit],
    answers: [Answer] = [],
    pauses: [PauseEvent] = [],
    cadence: NotificationSettings.Cadence? = nil,
    quietHours: QuietHours? = nil,
    nudgeAfterSilentDays: Int? = nil,
    onlyWhenQuestionsDue: Bool = true
) throws -> Truth {
    var settings = Settings.default
    settings.spotCheckRate = 0
    settings.notifications = try NotificationSettings(
        cadence: cadence ?? .timesPerDay([time(8), time(20)]),
        quietHours: quietHours,
        nudgeAfterSilentDays: nudgeAfterSilentDays,
        onlyWhenQuestionsDue: onlyWhenQuestionsDue
    )
    return Truth(habits: habits, answers: answers, pauses: pauses, settings: settings)
}

private func plan(_ truth: Truth, now: Date = noon(today)) throws -> [PlannedNotification] {
    try NotificationPlanner.plan(truth: truth, calendar: calendar, now: now)
}

private func question(_ notification: PlannedNotification) -> (Question, Int)? {
    guard case let .question(question, dueCount) = notification.kind else { return nil }
    return (question, dueCount)
}

struct NotificationPlannerTests {
    @Test func twoTimesPerDayNotifyAtEachSlotWhileDue() throws {
        let gym = habit()
        let planned = try plan(truth([gym]))
        // 20:00 today, then 08:00 and 20:00 on each of the next 7 days.
        #expect(planned.count == 15)
        #expect(planned.first?.fireAt == noon(today).addingTimeInterval(8 * 3600))
        #expect(planned.last?.day == today.adding(days: NotificationPlanner.horizonDays))
        let (first, dueCount) = try #require(planned.first.flatMap(question))
        #expect(first.habitID == gym.id)
        #expect(first.covers == today ... today)
        #expect(dueCount == 1)
        // Unanswered, tomorrow's question covers both days.
        let (tomorrow, _) = try #require(question(planned[1]))
        #expect(tomorrow.covers == today ... today.adding(days: 1))
    }

    /// Answered today: nothing until the habit is due again, and the first notification lands on the day
    /// the Today screen promises as the next check-in.
    @Test func onlyNotifiesWhenSomethingIsDue() throws {
        let gym = habit(createdDaysAgo: 30)
        let answers = (0 ... 30).map { yes(gym, on: today.adding(days: -$0)) }
        let truth = try truth([gym], answers: answers)
        let planned = try plan(truth)

        let projected = try Projection.rebuild(truth, clock: FixedClock(date: noon(today), calendar: calendar))
        let state = try #require(projected.states[gym.id])
        let next = try QuestionPlanner(settings: truth.settings).nextCheckIn(habit: gym, state: state, today: today)
        #expect(next > today.adding(days: 1))
        let expected = next <= today.adding(days: NotificationPlanner.horizonDays) ? next : nil
        #expect(planned.first?.day == expected)
    }

    @Test func remindersWhenNotOnlyWhenDue() throws {
        let gym = habit()
        let quiet = try plan(truth([gym], answers: [yes(gym, on: today)]))
        #expect(quiet.first?.day == today.adding(days: 1))

        let always = try plan(truth([gym], answers: [yes(gym, on: today)], onlyWhenQuestionsDue: false))
        #expect(always.first?.day == today)
        #expect(always.first?.kind == .reminder)
    }

    @Test func quietHoursSkipSlots() throws {
        let planned = try plan(truth([habit()], quietHours: QuietHours(startHour: 19, endHour: 7)))
        #expect(planned.count == 7)
        let eight = try time(8)
        #expect(planned.allSatisfy { calendar.date($0.day, at: eight) == $0.fireAt })
        #expect(planned.first?.day == today.adding(days: 1))
    }

    @Test func groupsDueHabitsIntoOneNotificationPerSlot() throws {
        let habits = [habit("Gym"), habit("Read"), habit("Meditate")]
        let planned = try plan(truth(habits))
        #expect(planned.count == 15)
        #expect(planned.compactMap(question).allSatisfy { $0.1 == 3 })
    }

    @Test func everyNDaysCountsFromTheLastAnswer() throws {
        let gym = habit()
        let planned = try plan(truth([gym], answers: [yes(gym, on: today)], cadence: .everyNDays(3, time: time(20))))
        #expect(planned.map(\.day) == [today.adding(days: 3), today.adding(days: 6)])
    }

    @Test func pausedHabitsAreNeverNotified() throws {
        let gym = habit()
        let pause = PauseEvent(
            habitIDs: [gym.id], start: today, end: today.adding(days: 2), reason: .manual, createdAt: noon(today)
        )
        let planned = try plan(truth([gym], pauses: [pause]))
        #expect(planned.first?.day == today.adding(days: 3))
        let (reentry, _) = try #require(planned.first.flatMap(question))
        #expect(reentry.covers == today.adding(days: 3) ... today.adding(days: 3))
    }

    @Test func vacationQuietSilencesKeptHabitsToo() throws {
        let (gym, read) = (habit("Gym"), habit("Read"))
        func vacation(quiet: Bool) -> PauseEvent {
            PauseEvent(
                habitIDs: [gym.id], start: today.adding(days: 1), end: today.adding(days: 2), reason: .vacation,
                createdAt: noon(today), quietAllNotifications: quiet
            )
        }
        let vacationDays: Set = [today.adding(days: 1), today.adding(days: 2)]
        let loud = try plan(truth([gym, read], pauses: [vacation(quiet: false)]))
        #expect(vacationDays.isSubset(of: Set(loud.map(\.day))))
        #expect(loud.filter { vacationDays.contains($0.day) }.compactMap(question)
            .allSatisfy { $0.0.habitID == read.id })

        let quiet = try plan(truth([gym, read], pauses: [vacation(quiet: true)]))
        #expect(Set(quiet.map(\.day)).isDisjoint(with: vacationDays))
    }

    @Test func silenceNudgeReplacesTheFirstSlotOfItsDay() throws {
        let gym = habit(createdDaysAgo: 10)
        let planned = try plan(truth([gym], answers: [yes(gym, on: today.adding(days: -1))], nudgeAfterSilentDays: 3))
        let nudges = planned.filter { $0.kind == .silenceNudge(lastActiveDay: today.adding(days: -1)) }
        #expect(nudges.map(\.day) == [today.adding(days: 2)])
        #expect(try nudges.first?.fireAt == calendar.date(today.adding(days: 2), at: time(8)))
        #expect(planned.count(where: { $0.fireAt == nudges.first?.fireAt }) == 1)
    }

    @Test func noSilenceNudgeDuringAPauseOrWhenItsDayHasPassed() throws {
        let gym = habit(createdDaysAgo: 10)
        let answered = [yes(gym, on: today.adding(days: -1))]
        let pause = PauseEvent(
            habitIDs: [gym.id], start: today.adding(days: 2), end: today.adding(days: 2), reason: .sick,
            createdAt: noon(today)
        )
        let paused = try plan(truth([gym], answers: answered, pauses: [pause], nudgeAfterSilentDays: 3))
        #expect(!paused.contains {
            if case .silenceNudge = $0.kind {
                true
            } else {
                false
            }
        })

        // Silent since 3 days ago, nudge after 1 day: that was 2 days ago; it fired then or never.
        let passed = try plan(truth([gym], answers: [yes(gym, on: today.adding(days: -3))], nudgeAfterSilentDays: 1))
        #expect(!passed.contains {
            if case .silenceNudge = $0.kind {
                true
            } else {
                false
            }
        })
    }

    @Test func capsPendingNotificationsAndKeepsTheNudge() throws {
        let hourly = try (0 ..< 24).map { try time($0) }
        let gym = habit(createdDaysAgo: 10)
        let planned = try plan(truth(
            [gym], answers: [yes(gym, on: today.adding(days: -1))], cadence: .timesPerDay(hourly),
            nudgeAfterSilentDays: 7
        ))
        #expect(planned.count == NotificationPlanner.maxNotifications)
        #expect(planned.last?.kind == .silenceNudge(lastActiveDay: today.adding(days: -1)))
        #expect(planned.map(\.fireAt) == planned.map(\.fireAt).sorted())
    }

    @Test func timesBeforeDayStartBelongToThePreviousHabitDay() throws {
        let planned = try plan(truth([habit()], cadence: .timesPerDay([time(1)])))
        // 01:00 on the 28th is still habit day 27 (the day starts at 04:00).
        #expect(planned.first?.day == today)
        #expect(try planned.first?.fireAt == calendar.date(today.adding(days: 1), at: time(1)))
    }

    @Test func nothingWithoutActiveHabits() throws {
        var archived = habit()
        archived.archivedAt = noon(today)
        #expect(try plan(truth([])).isEmpty)
        #expect(try plan(truth([archived])).isEmpty)
    }
}
