import Foundation
import HabitCore
import Testing

/// 2026-09-27.
private let today = DayKey(dayNumber: 20723)
private let noon = Date(timeIntervalSince1970: TimeInterval(today.dayNumber * 86400 + 12 * 3600))

private func habit(_ name: String, parents: [UUID] = [], behavior: VacationBehavior = .pause) -> Habit {
    Habit(
        name: name,
        colorHex: "#00AA00",
        createdAt: noon,
        createdDay: today.adding(days: -30),
        vacationBehavior: behavior,
        dependencies: parents.map { Dependency(parentID: $0) }
    )
}

struct VacationTests {
    private let gym = habit("Gym")
    private let read = habit("Read", behavior: .keep)
    private var archived: Habit {
        var archived = habit("Old", behavior: .keep)
        archived.archivedAt = noon
        return archived
    }

    @Test func defaultKeptComesFromVacationBehaviorOfActiveHabits() {
        #expect(Vacation.defaultKept([gym, read, archived]) == [read.id])
    }

    @Test func eventPausesEveryActiveHabitNotKept() throws {
        let meditate = habit("Meditate")
        let plan = Vacation.Plan(
            start: today.adding(days: 3), end: today.adding(days: 9), kept: [read.id], quietAllNotifications: true
        )
        let event = try Vacation.event(for: plan, habits: [gym, read, archived, meditate], createdAt: noon)
        #expect(event.habitIDs == [gym.id, meditate.id])
        #expect(event.reason == .vacation)
        #expect(event.start == today.adding(days: 3))
        #expect(event.quietAllNotifications)
    }

    @Test func eventRejectsKeepingEverythingAndInvertedDates() {
        #expect(throws: Vacation.ValidationError.nothingToPause) {
            try Vacation.event(
                for: Vacation.Plan(start: today, end: today, kept: [gym.id, read.id]), habits: [gym, read],
                createdAt: noon
            )
        }
        #expect(throws: PauseEvent.ValidationError.endBeforeStart(start: today, end: today.adding(days: -1))) {
            try Vacation.event(
                for: Vacation.Plan(start: today, end: today.adding(days: -1), kept: []), habits: [gym],
                createdAt: noon
            )
        }
    }

    @Test func rememberingChoicesUpdatesOnlyChangedActiveHabits() {
        let changed = Vacation.rememberingChoices(habits: [gym, read, archived], kept: [gym.id, read.id])
        #expect(changed.map(\.id) == [gym.id])
        #expect(changed.first?.vacationBehavior == .keep)
        #expect(Vacation.rememberingChoices(habits: [gym, read], kept: [read.id]).isEmpty)
    }

    @Test func keptChildOfPausedParentIsBlockedUntilParentsAreKept() throws {
        let shake = habit("Shake", parents: [gym.id])
        let log = habit("Log", parents: [shake.id])
        let habits = [gym, shake, log, read]
        #expect(try Vacation.blockedKept(habits: habits, kept: [log.id, read.id]) == [log.id])
        let resolved = try Vacation.keepingParents(habits: habits, kept: [log.id, read.id])
        #expect(resolved == [gym.id, shake.id, log.id, read.id])
        #expect(try Vacation.blockedKept(habits: habits, kept: resolved).isEmpty)
    }

    @Test func archivedAndSequenceParentsNeverBlock() throws {
        var oldParent = habit("Old")
        oldParent.archivedAt = noon
        var follower = habit("Stretch")
        follower.dependencies = [Dependency(parentID: gym.id, mode: .sequence)]
        let child = habit("Child", parents: [oldParent.id])
        let habits = [gym, oldParent, follower, child]
        #expect(try Vacation.blockedKept(habits: habits, kept: [follower.id, child.id]).isEmpty)
        #expect(try Vacation.keepingParents(habits: habits, kept: [follower.id, child.id]) == [follower.id, child.id])
    }

    @Test func currentIsTheRunningOrNextScheduledVacation() {
        func vacation(_ start: Int, _ end: Int) -> PauseEvent {
            PauseEvent(
                habitIDs: [gym.id], start: today.adding(days: start), end: today.adding(days: end),
                reason: .vacation, createdAt: noon
            )
        }
        let past = vacation(-9, -2)
        let next = vacation(5, 8)
        let later = vacation(20, 25)
        var cancelled = vacation(1, 2)
        cancelled.cancelledAt = noon
        let manual = PauseEvent(habitIDs: [gym.id], start: today, end: today, reason: .manual, createdAt: noon)
        #expect(Vacation.current(pauses: [later, past, cancelled, manual, next], today: today) == next)
        #expect(Vacation.current(pauses: [past], today: today) == nil)
        #expect(Vacation.current(pauses: [vacation(-2, 0), next], today: today)?.end == today)
    }

    @Test func quietOnlyWhileAQuietVacationRuns() {
        var quiet = PauseEvent(
            habitIDs: [gym.id], start: today, end: today.adding(days: 2), reason: .vacation, createdAt: noon,
            quietAllNotifications: true
        )
        #expect(Vacation.quietsNotifications(on: today, pauses: [quiet]))
        #expect(!Vacation.quietsNotifications(on: today.adding(days: 3), pauses: [quiet]))
        quiet.cancelledAt = noon
        #expect(!Vacation.quietsNotifications(on: today, pauses: [quiet]))
    }
}
