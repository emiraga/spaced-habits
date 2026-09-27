import Foundation
import HabitCore
import Testing

/// 2026-09-27.
private let today = DayKey(dayNumber: 20723)
private let noon = Date(timeIntervalSince1970: TimeInterval(today.dayNumber * 86400 + 12 * 3600))

private func habit(
    _ name: String,
    parents: [UUID] = [],
    mode: DependencyMode = .gate,
    archived: Bool = false
) -> Habit {
    Habit(
        name: name,
        colorHex: "#00AA00",
        createdAt: noon,
        createdDay: today.adding(days: -100),
        archivedAt: archived ? noon : nil,
        dependencies: parents.map { Dependency(parentID: $0, mode: mode) }
    )
}

/// Records for `habitID` on `today - daysAgo` with the given values.
private func records(_ habitID: UUID, _ values: [Int: Double], source: DaySource = .observed) -> [DayKey: DayRecord] {
    Dictionary(uniqueKeysWithValues: values.map { daysAgo, value in
        let day = today.adding(days: -daysAgo)
        return (day, DayRecord(habitID: habitID, day: day, value: value, source: source, confidence: 1))
    })
}

/// Parent state with mean 0.9.
private func strongState(_ habitID: UUID) -> SchedulerState {
    SchedulerState(habitID: habitID, alpha: 9, beta: 1, lastCoveredDay: today.adding(days: -1))
}

/// Parent state with mean 0.2.
private func failingState(_ habitID: UUID) -> SchedulerState {
    SchedulerState(habitID: habitID, alpha: 2, beta: 8, lastCoveredDay: today.adding(days: -1))
}

/// Inclusive window of the last `days` days ending today.
private func window(_ days: Int) -> ClosedRange<DayKey> {
    today.adding(days: 1 - days) ... today
}

struct DependenciesValidationTests {
    @Test func sortsParentsBeforeChildren() throws {
        let gym = habit("Gym")
        let shake = habit("Shake", parents: [gym.id])
        let stretch = habit("Stretch", parents: [gym.id])
        let log = habit("Log", parents: [shake.id, stretch.id])
        let sorted = try Dependencies.topologicallySorted([log, shake, gym, stretch])
        #expect(sorted.map(\.name) == ["Gym", "Shake", "Stretch", "Log"])
        try Dependencies.validate([log, shake, gym, stretch])
    }

    @Test func rejectsUnknownParent() {
        let missing = UUID()
        let orphan = habit("Orphan", parents: [missing])
        #expect(throws: Dependencies.ValidationError.unknownParent(habitID: orphan.id, parentID: missing)) {
            try Dependencies.validate([orphan])
        }
    }

    @Test func rejectsDuplicateIDs() {
        let gym = habit("Gym")
        #expect(throws: Dependencies.ValidationError.duplicateHabitID(gym.id)) {
            try Dependencies.validate([gym, gym])
        }
    }

    @Test func rejectsInvalidHabit() {
        var gym = habit("Gym")
        gym.dependencies = [Dependency(parentID: gym.id)]
        #expect(throws: Habit.ValidationError.dependsOnItself) { try Dependencies.validate([gym]) }
    }

    @Test func reportsCyclePathIncludingSequenceEdges() {
        var first = habit("First")
        let second = habit("Second", parents: [first.id])
        let third = habit("Third", parents: [second.id], mode: .sequence)
        first.dependencies = [Dependency(parentID: third.id)]
        #expect(throws: Dependencies.ValidationError.cycle([first.id, third.id, second.id])) {
            try Dependencies.validate([first, second, third])
        }
    }

    @Test func cycleIfAddingReportsTheLoopItWouldClose() {
        let gym = habit("Gym")
        let shake = habit("Shake", parents: [gym.id])
        let log = habit("Log", parents: [shake.id], mode: .sequence)
        let stretch = habit("Stretch")
        let habits = [gym, shake, log, stretch]
        #expect(Dependencies.cycle(ifAdding: shake.id, to: gym.id, in: habits) == [gym.id, shake.id, gym.id])
        #expect(Dependencies.cycle(ifAdding: log.id, to: gym.id, in: habits) == [gym.id, log.id, shake.id, gym.id])
        #expect(Dependencies.cycle(ifAdding: gym.id, to: gym.id, in: habits) == [gym.id, gym.id])
        #expect(Dependencies.cycle(ifAdding: gym.id, to: stretch.id, in: habits) == nil)
        #expect(Dependencies.cycle(ifAdding: gym.id, to: log.id, in: habits) == nil)
        #expect(Dependencies.cycle(ifAdding: UUID(), to: gym.id, in: habits) == nil)
    }
}

struct DependenciesGateTests {
    private let gym = UUID()

    @Test func ungatedWithoutParents() {
        #expect(Dependencies.gate(parentIDs: [], covers: window(1), states: [:], records: [:]) == nil)
    }

    @Test func closedWhenParentMeanBelowHalf() {
        let gate = Dependencies.gate(
            parentIDs: [gym],
            covers: window(1),
            states: [gym: failingState(gym)],
            records: [gym: records(gym, [0: 1])]
        )
        #expect(gate == .closed)
    }

    @Test func singleDayNeedsParentDoneToday() {
        let states = [gym: strongState(gym)]
        let done = Dependencies.gate(
            parentIDs: [gym], covers: window(1), states: states, records: [gym: records(gym, [0: 1])]
        )
        #expect(done == .open(shape: .singleDay, context: ParentContext(parentIDs: [gym], parentDoneDays: 1)))
        // Unanswered today: nothing is known about the parent yet.
        #expect(Dependencies.gate(parentIDs: [gym], covers: window(1), states: states, records: [:]) == .closed)
        let skipped = Dependencies.gate(
            parentIDs: [gym], covers: window(1), states: states, records: [gym: records(gym, [0: 0])]
        )
        #expect(skipped == .closed)
    }

    @Test func perDayListsOnlyParentDoneDays() {
        let gate = Dependencies.gate(
            parentIDs: [gym],
            covers: window(3),
            states: [gym: strongState(gym)],
            records: [gym: records(gym, [2: 1, 1: 0, 0: 1])]
        )
        let shape = QuestionShape.perDay(days: [today.adding(days: -2), today])
        #expect(gate == .open(shape: shape, context: ParentContext(parentIDs: [gym], parentDoneDays: 2)))
    }

    @Test func countTotalIsParentDoneDays() {
        let gate = Dependencies.gate(
            parentIDs: [gym],
            covers: window(6),
            states: [gym: strongState(gym)],
            records: [gym: records(gym, [5: 1, 4: 0, 3: 1, 2: 1, 1: 0, 0: 1])]
        )
        #expect(gate == .open(shape: .count(total: 4), context: ParentContext(parentIDs: [gym], parentDoneDays: 4)))
    }

    @Test func onlyParentEvidenceCounts() {
        var parentRecords = records(gym, [4: 1], source: .paused)
        parentRecords.merge(records(gym, [3: 0.9], source: .inferred)) { $1 }
        parentRecords.merge(records(gym, [2: 1], source: .health)) { $1 }
        parentRecords.merge(records(gym, [1: 1])) { $1 }
        // Paused, inferred and missing (day 0) days count 0; Health and observed days count: 2 known days.
        let gate = Dependencies.gate(
            parentIDs: [gym], covers: window(5), states: [gym: strongState(gym)], records: [gym: parentRecords]
        )
        #expect(gate == .open(shape: .count(total: 2), context: ParentContext(parentIDs: [gym], parentDoneDays: 2)))
        let guessedOnly = Dependencies.gate(
            parentIDs: [gym],
            covers: window(3),
            states: [gym: strongState(gym)],
            records: [gym: records(gym, [2: 0.9, 1: 0.9, 0: 0.9], source: .inferred)]
        )
        #expect(guessedOnly == .closed)
    }

    @Test func perDayFallsBackToCountWhenParentDaysAreAggregated() {
        let gate = Dependencies.gate(
            parentIDs: [gym],
            covers: window(3),
            states: [gym: strongState(gym)],
            records: [gym: records(gym, [2: 2.0 / 3, 1: 2.0 / 3, 0: 2.0 / 3], source: .aggregated)]
        )
        #expect(gate == .open(shape: .count(total: 2), context: ParentContext(parentIDs: [gym], parentDoneDays: 2)))
    }

    @Test func multipleParentsMustAllBeDoneOnTheSameDays() {
        let sleep = UUID()
        let states = [gym: strongState(gym), sleep: strongState(sleep)]
        let overlapping = Dependencies.gate(
            parentIDs: [gym, sleep],
            covers: window(2),
            states: states,
            records: [gym: records(gym, [1: 1, 0: 1]), sleep: records(sleep, [1: 1, 0: 0])]
        )
        let context = ParentContext(parentIDs: [gym, sleep], parentDoneDays: 1)
        #expect(overlapping == .open(shape: .perDay(days: [today.adding(days: -1)]), context: context))
        let disjoint = Dependencies.gate(
            parentIDs: [gym, sleep],
            covers: window(2),
            states: states,
            records: [gym: records(gym, [1: 1, 0: 0]), sleep: records(sleep, [1: 0, 0: 1])]
        )
        #expect(disjoint == .closed)
    }
}

struct QuestionPlannerGatingTests {
    private func clock() throws -> FixedClock {
        let utc = try #require(TimeZone(identifier: "UTC"))
        return try FixedClock(date: noon, calendar: DayCalendar(timeZone: utc))
    }

    private func planner() throws -> QuestionPlanner {
        var settings = Settings.default
        settings.spotCheckRate = 0
        return try QuestionPlanner(settings: settings)
    }

    /// A 6-day-old child of `parent`, never answered, so its window is the last 6 days.
    private func child(of parent: Habit, mode: DependencyMode = .gate) -> Habit {
        var child = habit("Shake", parents: [parent.id], mode: mode)
        child.createdDay = today.adding(days: -5)
        return child
    }

    @Test func failingParentKeepsChildOutOfSession() throws {
        let gym = habit("Gym")
        let shake = child(of: gym)
        let plan = try planner().session(
            habits: [gym, shake],
            states: [gym.id: failingState(gym.id)],
            records: [gym.id: records(gym.id, [0: 0])],
            clock: clock()
        )
        #expect(plan.questions.map(\.habitID) == [gym.id])
        #expect(plan.queued.isEmpty)
    }

    @Test func openGateConditionsTheQuestion() throws {
        let gym = habit("Gym")
        let shake = child(of: gym)
        let plan = try planner().session(
            habits: [gym, shake],
            states: [gym.id: strongState(gym.id)],
            records: [gym.id: records(gym.id, [5: 1, 4: 0, 3: 1, 2: 1, 1: 0, 0: 1])],
            clock: clock()
        )
        let question = try #require(plan.questions.first { $0.habitID == shake.id })
        #expect(question.covers == window(6))
        #expect(question.shape == .count(total: 4))
        #expect(question.parentContext == ParentContext(parentIDs: [gym.id], parentDoneDays: 4))
    }

    @Test func sequenceEdgesAndArchivedParentsDoNotGate() throws {
        let routine = habit("Routine")
        let archived = habit("Old gym", archived: true)
        let follower = child(of: routine, mode: .sequence)
        let orphaned = child(of: archived)
        let plan = try planner().session(
            habits: [routine, archived, follower, orphaned],
            states: [routine.id: failingState(routine.id), archived.id: failingState(archived.id)],
            records: [:],
            clock: clock()
        )
        for id in [follower.id, orphaned.id] {
            let question = try #require(plan.questions.first { $0.habitID == id })
            #expect(question.shape == .count(total: 6))
            #expect(question.parentContext == nil)
        }
    }

    @Test func unknownParentThrows() throws {
        let missing = UUID()
        let orphan = habit("Orphan", parents: [missing])
        #expect(throws: Dependencies.ValidationError.unknownParent(habitID: orphan.id, parentID: missing)) {
            try planner().session(habits: [orphan], states: [:], records: [:], clock: clock())
        }
    }
}
