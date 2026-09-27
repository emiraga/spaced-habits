import Foundation
import HabitCore
import Testing

/// 2026-09-27.
private let today = DayKey(dayNumber: 20723)
private let noon = Date(timeIntervalSince1970: TimeInterval(today.dayNumber * 86400 + 12 * 3600))

private func habit(_ name: String, parents: [UUID] = [], mode: DependencyMode = .gate) -> Habit {
    Habit(
        name: name,
        colorHex: "#00AA00",
        createdAt: noon,
        createdDay: today.adding(days: -100),
        dependencies: parents.map { Dependency(parentID: $0, mode: mode) }
    )
}

private func pause(_ habits: [Habit], from start: Int, to end: Int) -> PauseEvent {
    PauseEvent(
        habitIDs: habits.map(\.id),
        start: today.adding(days: start),
        end: today.adding(days: end),
        reason: .vacation,
        createdAt: noon
    )
}

struct PausesDelayTests {
    private func answer(_ value: AnswerValue) -> Answer {
        Answer(
            questionID: UUID(),
            habitID: UUID(),
            covers: today.adding(days: -2) ... today,
            value: value,
            answeredAt: noon,
            timezone: "UTC",
            channel: .app
        )
    }

    @Test func delayPausesFromAnswerDayForNDays() throws {
        let delay = answer(.delayed(days: 3))
        let event = try #require(try Pauses.event(forDelay: delay, createdAt: noon))
        #expect(event.habitIDs == [delay.habitID])
        #expect(event.start == today)
        #expect(event.end == today.adding(days: 2))
        #expect(event.reason == .manual)
        try event.validate()
    }

    @Test func delayCarriesTheChosenReason() throws {
        let event = try #require(try Pauses.event(forDelay: answer(.delayed(days: 1)), reason: .sick, createdAt: noon))
        #expect(event.reason == .sick)
        #expect(event.start == event.end)
    }

    @Test func otherAnswersCreateNoPause() throws {
        #expect(try Pauses.event(forDelay: answer(.done), createdAt: noon) == nil)
    }

    @Test func invalidDelayThrows() {
        #expect(throws: Answer.ValidationError.delayNotPositive(0)) {
            try Pauses.event(forDelay: answer(.delayed(days: 0)), createdAt: noon)
        }
    }
}

struct PausesAvailabilityTests {
    @Test func pauseRangeIsInclusive() throws {
        let gym = habit("Gym")
        let pauses = [pause([gym], from: -2, to: 0)]
        for offset in -3 ... 1 {
            let expected: [UUID: Unavailability] = (-2 ... 0).contains(offset) ? [gym.id: .paused] : [:]
            #expect(try Pauses.unavailable(on: today.adding(days: offset), habits: [gym], pauses: pauses) == expected)
        }
    }

    @Test func blockingIsTransitiveOverGateEdges() throws {
        let gym = habit("Gym")
        let shake = habit("Shake", parents: [gym.id])
        let log = habit("Log", parents: [shake.id])
        let follower = habit("Stretch", parents: [gym.id], mode: .sequence)
        let unavailable = try Pauses.unavailable(
            on: today,
            habits: [log, follower, shake, gym],
            pauses: [pause([gym], from: 0, to: 0)]
        )
        #expect(unavailable == [gym.id: .paused, shake.id: .blocked, log.id: .blocked])
    }

    @Test func ownPauseWinsOverBlocked() throws {
        let gym = habit("Gym")
        let shake = habit("Shake", parents: [gym.id])
        let unavailable = try Pauses.unavailable(
            on: today,
            habits: [gym, shake],
            pauses: [pause([gym, shake], from: 0, to: 0)]
        )
        #expect(unavailable == [gym.id: .paused, shake.id: .paused])
        #expect(Unavailability.blocked.source == .blocked)
    }

    @Test func archivedParentDoesNotBlock() throws {
        var gym = habit("Gym")
        gym.archivedAt = noon
        let shake = habit("Shake", parents: [gym.id])
        let unavailable = try Pauses.unavailable(
            on: today,
            habits: [gym, shake],
            pauses: [pause([gym], from: 0, to: 0)]
        )
        #expect(unavailable == [gym.id: .paused])
    }
}

struct PausesEndEarlyTests {
    private let gym = habit("Gym")

    @Test func runningPauseEndsYesterday() {
        let ended = pause([gym], from: -3, to: 4).endedEarly(today: today, at: noon)
        #expect(ended.end == today.adding(days: -1))
        #expect(!ended.isCancelled)
        #expect(!ended.pauses(gym.id, on: today))
        #expect(ended.pauses(gym.id, on: today.adding(days: -1)))
    }

    @Test func pauseStartingTodayOrLaterIsCancelledAndPausesNothing() {
        for start in [0, 5] {
            let ended = pause([gym], from: start, to: start + 3).endedEarly(today: today, at: noon)
            #expect(ended.cancelledAt == noon)
            #expect(ended.start == today.adding(days: start))
            #expect((start ... start + 3).allSatisfy { !ended.pauses(gym.id, on: today.adding(days: $0)) })
        }
    }

    @Test func finishedOrCancelledPauseIsUnchanged() {
        let finished = pause([gym], from: -5, to: -1)
        #expect(finished.endedEarly(today: today, at: noon) == finished)
        var cancelled = pause([gym], from: 2, to: 3)
        cancelled.cancelledAt = noon.addingTimeInterval(-60)
        #expect(cancelled.endedEarly(today: today, at: noon) == cancelled)
    }

    @Test func cancelledPauseMakesNothingUnavailable() throws {
        var cancelled = pause([gym], from: 0, to: 0)
        cancelled.cancelledAt = noon
        #expect(try Pauses.unavailable(on: today, habits: [gym], pauses: [cancelled]).isEmpty)
    }
}

struct PausesQueryTests {
    private let gym = habit("Gym")
    private let read = habit("Read")

    @Test func resumeDayIsTheFirstUnpausedDay() {
        let pauses = [pause([gym], from: -1, to: 2)]
        #expect(Pauses.resumeDay(of: gym.id, today: today, pauses: pauses) == today.adding(days: 3))
        #expect(Pauses.resumeDay(of: read.id, today: today, pauses: pauses) == nil)
        #expect(Pauses.resumeDay(of: gym.id, today: today.adding(days: 3), pauses: pauses) == nil)
    }

    @Test func resumeDaySpansBackToBackAndOverlappingPauses() {
        let pauses = [pause([gym], from: 0, to: 2), pause([gym, read], from: 3, to: 5), pause([gym], from: 4, to: 8)]
        #expect(Pauses.resumeDay(of: gym.id, today: today, pauses: pauses) == today.adding(days: 9))
    }

    @Test func resumeDayIgnoresCancelledPauses() {
        var cancelled = pause([gym], from: 3, to: 9)
        cancelled.cancelledAt = noon
        let pauses = [pause([gym], from: 0, to: 2), cancelled]
        #expect(Pauses.resumeDay(of: gym.id, today: today, pauses: pauses) == today.adding(days: 3))
    }

    @Test func currentListsRunningAndScheduledPausesSoonestFirst() {
        let running = pause([gym], from: -1, to: 1)
        let scheduled = pause([gym], from: 10, to: 12)
        var cancelled = pause([gym], from: 4, to: 5)
        cancelled.cancelledAt = noon
        let pauses = [scheduled, pause([gym], from: -9, to: -2), cancelled, running, pause([read], from: 0, to: 0)]
        #expect(Pauses.current(of: gym.id, today: today, pauses: pauses) == [running, scheduled])
    }
}

struct PausesDelayInsightTests {
    private let gym = habit("Gym")
    private let read = habit("Read")

    private func delay(_ habit: Habit, daysAgo: Int, reason: PauseReason = .manual) -> PauseEvent {
        PauseEvent(
            habitIDs: [habit.id], start: today.adding(days: -daysAgo), end: today.adding(days: 2 - daysAgo),
            reason: reason, createdAt: noon
        )
    }

    @Test func threeManualDelaysInSixtyDaysFlagAHabit() {
        let pauses = [delay(gym, daysAgo: 0), delay(gym, daysAgo: 30), delay(gym, daysAgo: 59), delay(read, daysAgo: 1)]
        #expect(Pauses.frequentlyDelayedHabitIDs(pauses: pauses, today: today) == [gym.id])
    }

    @Test func oldCancelledAndNonManualPausesDontCount() {
        var cancelled = delay(gym, daysAgo: 2)
        cancelled.cancelledAt = noon
        let pauses = [
            delay(gym, daysAgo: 0), delay(gym, daysAgo: 60), cancelled,
            delay(gym, daysAgo: 3, reason: .sick), delay(gym, daysAgo: 4, reason: .vacation),
        ]
        #expect(Pauses.frequentlyDelayedHabitIDs(pauses: pauses, today: today).isEmpty)
    }
}
