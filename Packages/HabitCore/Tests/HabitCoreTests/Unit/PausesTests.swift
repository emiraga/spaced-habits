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
