import Foundation
import HabitCore
@testable import HabitUI
import Testing

/// The §13 M3 checkpoint, driven through `AppModel` and the debug "advance day" control.
@MainActor
struct PauseTests {
    /// Delay 3 days: no questions and `.paused` history while paused, then exactly one re-entry question
    /// on the resume day, covering only that day.
    @Test func checkpointDelayThreeDays() throws {
        let model = try Harness().model()
        let gym = try addHabit(model, "Gym")
        try model.delay(#require(model.questions.first), days: 3, reason: .manual)
        #expect(model.truth.answers.map(\.value) == [.delayed(days: 3)])

        for day in 0 ..< 3 {
            #expect(model.dayOffset == day)
            #expect(model.questions.isEmpty)
            #expect(model.todayStatus(of: gym.id) == .paused)
            #expect(model.resumeDay(of: gym.id) == start.adding(days: 3))
            #expect(model.nextCheckIn(of: gym) == start.adding(days: 3))
            try model.advanceDay()
        }

        let reentry = try #require(model.questions.first)
        #expect(model.questions.count == 1)
        #expect(reentry.covers == model.today ... model.today)
        #expect(model.reasons[gym.id] == .reentry)
        #expect(model.resumeDay(of: gym.id) == nil)
        #expect(model.history(of: gym.id).dropFirst().map(\.source) == [.paused, .paused, .paused])
    }

    @Test func checkpointBackdatedPauseFlipsAnsweredDays() throws {
        let model = try Harness().model()
        let gym = try addHabit(model, "Gym")
        for day in 0 ... 3 {
            if day > 0 {
                try model.advanceDay()
            }
            try model.answer(#require(model.questions.first), with: .notDone)
        }
        #expect(model.history(of: gym.id).map(\.source) == Array(repeating: .observed, count: 4))

        try model.pause(gym.id, from: start.adding(days: 1), through: start.adding(days: 2), reason: .sick)
        #expect(model.history(of: gym.id).map(\.source) == [.observed, .paused, .paused, .observed])
        #expect(model.truth.answers.count == 4)
    }

    /// One kept habit is the only one asked; ending and re-planning vacation remembers the kept set.
    @Test func checkpointVacationKeepsOnlyCheckedHabitsAndRemembers() throws {
        let model = try Harness().model()
        try model.addSampleHabits()
        let gym = try #require(model.activeHabits.first { $0.name == "Gym" })
        #expect(Vacation.defaultKept(model.truth.habits).isEmpty)

        try model.startVacation(
            Vacation.Plan(
                start: model.today,
                end: model.today.adding(days: 6),
                kept: [gym.id],
                quietAllNotifications: true
            ),
            rememberChoices: true
        )
        #expect(model.questions.map(\.habitID) == [gym.id])
        #expect(model.currentVacation?.habitIDs.count == 2)
        #expect(model.activeHabits.filter { model.todayStatus(of: $0.id) == .paused }.count == 2)

        try model.end(#require(model.currentVacation))
        #expect(model.currentVacation == nil)
        #expect(model.questions.count == 3)
        #expect(Vacation.defaultKept(model.truth.habits) == [gym.id])
        #expect(model.habit(gym.id)?.vacationBehavior == .keep)
    }

    @Test func vacationWithoutRememberingLeavesHabitsAlone() throws {
        let model = try Harness().model()
        try model.addSampleHabits()
        let revisions = model.truth.habitRevisions.count
        let gym = try #require(model.activeHabits.first { $0.name == "Gym" })
        try model.startVacation(
            Vacation.Plan(start: model.today, end: model.today, kept: [gym.id], quietAllNotifications: false),
            rememberChoices: false
        )
        #expect(Vacation.defaultKept(model.truth.habits).isEmpty)
        #expect(model.truth.habitRevisions.count == revisions)
    }

    @Test func invalidVacationWritesNothing() throws {
        let model = try Harness().model()
        let gym = try addHabit(model, "Gym")
        #expect(throws: Vacation.ValidationError.nothingToPause) {
            try model.startVacation(
                Vacation.Plan(start: model.today, end: model.today, kept: [gym.id], quietAllNotifications: false),
                rememberChoices: true
            )
        }
        #expect(model.truth.pauses.isEmpty)
        #expect(model.habit(gym.id)?.vacationBehavior == .pause)
    }

    @Test func scheduledVacationStartsLater() throws {
        let model = try Harness().model()
        let gym = try addHabit(model, "Gym")
        _ = try addHabit(model, "Read")
        try model.startVacation(
            Vacation.Plan(
                start: model.today.adding(days: 2),
                end: model.today.adding(days: 3),
                kept: [],
                quietAllNotifications: false
            ),
            rememberChoices: true
        )
        #expect(model.questions.count == 2)
        #expect(model.currentVacation?.start == start.adding(days: 2))
        try model.advanceDay()
        try model.advanceDay()
        #expect(model.questions.isEmpty)
        #expect(model.resumeDay(of: gym.id) == start.adding(days: 4))
    }

    @Test func endingAPauseEarlyAsksTheReentryCheckToday() throws {
        let model = try Harness().model()
        let gym = try addHabit(model, "Gym")
        try model.answer(#require(model.questions.first), with: .done)
        try model.advanceDay()
        try model.pause(gym.id, from: start, through: start.adding(days: 9), reason: .manual)
        #expect(model.questions.isEmpty)

        try model.end(#require(model.pauses(of: gym.id).first))
        #expect(model.pauses(of: gym.id).isEmpty)
        #expect(model.reasons[gym.id] == .reentry)
        #expect(model.questions.first?.covers == model.today ... model.today)
    }

    @Test func extendingMovesTheResumeDayAndCancellingScheduledPauseKeepsIt() throws {
        let model = try Harness().model()
        let gym = try addHabit(model, "Gym")
        try model.delay(#require(model.questions.first), days: 1, reason: .sick)
        var pause = try #require(model.pauses(of: gym.id).first)
        #expect(pause.reason == .sick)
        pause.end = start.adding(days: 4)
        try model.save(pause)
        #expect(model.resumeDay(of: gym.id) == start.adding(days: 5))
        #expect(model.truth.pauses.count == 1)

        try model.pause(gym.id, from: start.adding(days: 10), through: start.adding(days: 12), reason: .manual)
        let scheduled = try #require(model.pauses(of: gym.id).last)
        try model.end(scheduled)
        #expect(model.pauses(of: gym.id).map(\.id) == [pause.id])
        #expect(model.truth.pauses.first { $0.id == scheduled.id }?.cancelledAt == noon)
    }
}
