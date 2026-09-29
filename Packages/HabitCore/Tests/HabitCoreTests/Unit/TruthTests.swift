import Foundation
import HabitCore
import Testing

/// 2026-09-27.
private let today = DayKey(dayNumber: 20723)
private let noon = Date(timeIntervalSince1970: TimeInterval(today.dayNumber * 86400 + 12 * 3600))

private func clock() throws -> FixedClock {
    let utc = try #require(TimeZone(identifier: "UTC"))
    return try FixedClock(date: noon, calendar: DayCalendar(timeZone: utc))
}

private func day(_ offset: Int) -> DayKey {
    today.adding(days: offset)
}

private func habit(_ name: String, clusterID: UUID? = nil) -> Habit {
    Habit(name: name, colorHex: "#00AA00", createdAt: noon, createdDay: day(-10), clusterID: clusterID)
}

private func question(_ habit: Habit, _ first: Int, _ shape: QuestionShape) -> Question {
    Question(habitID: habit.id, covers: day(first) ... today, shape: shape, createdAt: noon, presentedAt: noon)
}

struct QuestionValidationTests {
    @Test func acceptsEveryPlannerShape() throws {
        let gym = habit("Gym")
        for first in -6 ... 0 {
            try question(gym, first, QuestionPlanner.shape(for: day(first) ... today)).validate()
        }
        try question(gym, -3, .perDay(days: [day(-3), day(-1)])).validate()
        try question(gym, -5, .count(total: 2)).validate()
    }

    @Test func rejectsShapesInconsistentWithCovers() {
        let gym = habit("Gym")
        #expect(throws: Question.ValidationError.singleDayCoversSeveralDays(2)) {
            try question(gym, -1, .singleDay).validate()
        }
        #expect(throws: Question.ValidationError.perDayEmpty) { try question(gym, -1, .perDay(days: [])).validate() }
        #expect(throws: Question.ValidationError.perDayOutsideCovers(day(-2))) {
            try question(gym, -1, .perDay(days: [day(-2)])).validate()
        }
        #expect(throws: Question.ValidationError.countOutOfRange(total: 5, coverDays: 4)) {
            try question(gym, -3, .count(total: 5)).validate()
        }
        #expect(throws: Question.ValidationError.countOutOfRange(total: 0, coverDays: 4)) {
            try question(gym, -3, .count(total: 0)).validate()
        }
        var gated = question(gym, 0, .singleDay)
        gated.parentContext = ParentContext(parentIDs: [UUID()], parentDoneDays: -1)
        #expect(throws: Question.ValidationError.negativeParentDoneDays(-1)) { try gated.validate() }
    }
}

struct TruthRecordKeepingTests {
    @Test func rejectsReferencesToUnknownHabitsAndClusters() {
        let gym = habit("Gym")
        let stray = habit("Stray")
        #expect(throws: Truth.ValidationError.unknownHabit(stray.id)) {
            try Truth(habits: [gym], questions: [question(stray, 0, .singleDay)]).validate()
        }
        #expect(throws: Truth.ValidationError.unknownHabit(stray.id)) {
            try Truth(habits: [gym], habitRevisions: [HabitRevision(habit: stray, editedAt: noon)]).validate()
        }
        let orphan = UUID()
        #expect(throws: Truth.ValidationError.unknownCluster(orphan)) {
            try Truth(habits: [habit("Shake", clusterID: orphan)]).validate()
        }
        #expect(throws: Cluster.ValidationError.emptyName) {
            try Truth(habits: [gym], clusters: [Cluster(name: " ", colorHex: "#000000")]).validate()
        }
        var badRevision = gym
        badRevision.name = ""
        #expect(throws: Habit.ValidationError.emptyName) {
            try Truth(habits: [gym], habitRevisions: [HabitRevision(habit: badRevision, editedAt: noon)]).validate()
        }
    }

    /// Clusters, revisions and questions are for history and export; the scheduler never reads them.
    @Test func recordKeepingRoundTripsAndDoesNotChangeProjection() throws {
        let routine = Cluster(name: "Morning", colorHex: "#FFAA00")
        var gym = habit("Gym", clusterID: routine.id)
        let original = HabitRevision(habit: gym, editedAt: noon.addingTimeInterval(-86400 * 10))
        gym.targetAdherence = 0.9
        let edit = HabitRevision(habit: gym, editedAt: noon.addingTimeInterval(-86400))
        var dismissed = question(gym, -1, .perDay(days: [day(-1), today]))
        dismissed.dismissedAt = noon
        let answer = Answer(
            questionID: UUID(), habitID: gym.id, covers: day(-2) ... day(-2), value: .done,
            answeredAt: noon.addingTimeInterval(-86400 * 2), timezone: "UTC", channel: .app
        )
        let bare = Truth(habits: [gym], clusters: [routine], answers: [answer])
        var full = bare
        full.habitRevisions = [original, edit]
        full.questions = [dismissed]

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(try JSONDecoder().decode(Truth.self, from: encoder.encode(full)) == full)
        #expect(try Projection.rebuild(full, clock: clock()) == Projection.rebuild(bare, clock: clock()))
    }

    /// Sync delivers records out of order (§10): whatever names a missing habit, cluster or parent waits.
    @Test func pendingReferencesAreHeldBackUntilTheyResolve() throws {
        let routine = Cluster(name: "Morning", colorHex: "#FFAA00")
        let gym = habit("Gym")
        let stray = habit("Stray")
        let clustered = habit("Stretch", clusterID: routine.id)
        var shake = habit("Shake")
        shake.dependencies = [Dependency(parentID: stray.id)]
        var smoothie = habit("Smoothie")
        smoothie.dependencies = [Dependency(parentID: shake.id)]
        let pending = Truth(
            habits: [gym, clustered, shake, smoothie],
            habitRevisions: [HabitRevision(habit: stray, editedAt: noon), HabitRevision(habit: gym, editedAt: noon)],
            questions: [question(stray, 0, .singleDay), question(gym, 0, .singleDay)],
            answers: [
                Answer(
                    questionID: UUID(), habitID: smoothie.id, covers: today ... today, value: .done,
                    answeredAt: noon, timezone: "UTC", channel: .watch
                ),
            ],
            pauses: [
                PauseEvent(habitIDs: [gym.id, stray.id], start: today, end: today, reason: .manual, createdAt: noon),
            ],
            healthObservations: [HealthObservation(habitID: stray.id, day: today, sampleID: "s")]
        )

        let held = pending.withoutPendingReferences()
        #expect(held.habits == [gym])
        #expect(held.habitRevisions.map(\.habit.id) == [gym.id])
        #expect(held.questions.map(\.habitID) == [gym.id])
        #expect(held.answers.isEmpty)
        #expect(held.pauses.isEmpty)
        #expect(held.healthObservations.isEmpty)
        try held.validate()

        var arrived = pending
        arrived.habits.append(stray)
        arrived.clusters.append(routine)
        #expect(arrived.withoutPendingReferences() == arrived)
        try arrived.validate()
    }

    /// A deleted habit takes its records along and leaves shared pauses and its children (§10).
    @Test func removingDeletedHabitsAndClustersCascades() throws {
        let routine = Cluster(name: "Morning", colorHex: "#FFAA00")
        let gym = habit("Gym", clusterID: routine.id)
        let read = habit("Read")
        var shake = habit("Shake", clusterID: routine.id)
        shake.dependencies = [Dependency(parentID: gym.id)]
        func answer(_ habit: Habit) -> Answer {
            Answer(
                questionID: UUID(), habitID: habit.id, covers: today ... today, value: .done, answeredAt: noon,
                timezone: "UTC", channel: .app
            )
        }
        let vacation = PauseEvent(
            habitIDs: [gym.id, read.id],
            start: today,
            end: today,
            reason: .vacation,
            createdAt: noon
        )
        let truth = Truth(
            habits: [gym, read, shake],
            clusters: [routine],
            habitRevisions: [HabitRevision(habit: gym, editedAt: noon), HabitRevision(habit: read, editedAt: noon)],
            questions: [question(gym, 0, .singleDay), question(read, 0, .singleDay)],
            answers: [answer(gym), answer(read)],
            pauses: [
                vacation,
                PauseEvent(habitIDs: [gym.id], start: today, end: today, reason: .manual, createdAt: noon),
            ],
            healthObservations: [HealthObservation(habitID: gym.id, day: today, sampleID: "s")]
        )

        let removed = truth.removing(habits: [gym.id], clusters: [routine.id])
        #expect(removed.habits.map(\.name) == ["Read", "Shake"])
        #expect(removed.habits.allSatisfy { $0.dependencies.isEmpty && $0.clusterID == nil })
        #expect(removed.clusters.isEmpty)
        #expect(removed.habitRevisions.map(\.habit.id) == [read.id])
        #expect(removed.questions.map(\.habitID) == [read.id])
        #expect(removed.answers.map(\.habitID) == [read.id])
        #expect(removed.pauses.map(\.id) == [vacation.id])
        #expect(removed.pauses.first?.habitIDs == [read.id])
        #expect(removed.healthObservations.isEmpty)
        try removed.validate()
        #expect(truth.removing(habits: [], clusters: []) == truth)
    }
}
