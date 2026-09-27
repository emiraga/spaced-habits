import Foundation
import HabitCore
import Testing

private func day(_ string: String) throws -> DayKey {
    try #require(DayKey(string))
}

private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try JSONDecoder().decode(T.self, from: encoder.encode(value))
}

private func json(_ value: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try #require(String(bytes: encoder.encode(value), encoding: .utf8))
}

private func makeHabit(id: UUID = UUID(), dependencies: [Dependency] = []) throws -> Habit {
    try Habit(
        id: id,
        name: "Gym",
        emoji: "🏋️",
        colorHex: "#FF8800",
        createdAt: Date(timeIntervalSince1970: 1_790_000_000),
        createdDay: day("2026-09-21"),
        importance: .high,
        dependencies: dependencies,
        healthBinding: .workout(minMinutes: 20)
    )
}

struct HabitTests {
    @Test func defaultsMatchDesign() throws {
        let habit = try makeHabit()
        #expect(habit.kind == .boolean)
        #expect(habit.targetAdherence == 0.8)
        #expect(habit.maxRecallGapDays == 7)
        #expect(habit.vacationBehavior == .pause)
        #expect(!habit.isArchived)
        try habit.validate()
    }

    @Test func gateParentsIgnoreSequenceEdges() throws {
        let gym = UUID(), coffee = UUID()
        let habit = try makeHabit(dependencies: [
            Dependency(parentID: gym),
            Dependency(parentID: coffee, mode: .sequence),
        ])
        #expect(habit.gateParentIDs == [gym])
        #expect(habit.allParentIDs == [gym, coffee])
    }

    @Test func codableRoundTripPreservesSequenceMode() throws {
        let habit = try makeHabit(dependencies: [Dependency(parentID: UUID(), mode: .sequence)])
        #expect(try roundTrip(habit) == habit)
        #expect(try json(habit).contains(#""mode":"sequence""#))
    }

    @Test func validationRejectsBadFields() throws {
        var habit = try makeHabit()
        habit.name = "  \n"
        #expect(throws: Habit.ValidationError.emptyName) { try habit.validate() }

        habit = try makeHabit()
        habit.targetAdherence = 1.2
        #expect(throws: Habit.ValidationError.targetAdherenceOutOfRange(1.2)) { try habit.validate() }

        habit = try makeHabit()
        habit.maxRecallGapDays = 0
        #expect(throws: Habit.ValidationError.maxRecallGapDaysOutOfRange(0)) { try habit.validate() }

        let id = UUID()
        habit = try makeHabit(id: id, dependencies: [Dependency(parentID: id)])
        #expect(throws: Habit.ValidationError.dependsOnItself) { try habit.validate() }

        let parent = UUID()
        habit = try makeHabit(dependencies: [
            Dependency(parentID: parent),
            Dependency(parentID: parent, mode: .sequence),
        ])
        #expect(throws: Habit.ValidationError.duplicateParent(parent)) { try habit.validate() }
    }
}

struct AnswerTests {
    private func answer(_ value: AnswerValue, covers: ClosedRange<DayKey>) -> Answer {
        Answer(
            questionID: UUID(),
            habitID: UUID(),
            covers: covers,
            value: value,
            answeredAt: Date(timeIntervalSince1970: 1_790_000_000),
            timezone: "Europe/Sarajevo",
            channel: .widget
        )
    }

    @Test func perDayEncodesAsObjectKeyedByDay() throws {
        let covers = try day("2026-09-25") ... day("2026-09-26")
        let value = try AnswerValue.perDay([day("2026-09-25"): true, day("2026-09-26"): false])
        let encoded = try json(answer(value, covers: covers))
        #expect(encoded.contains(#"{"2026-09-25":true,"2026-09-26":false}"#))
        #expect(encoded.contains(#""covers":["2026-09-25","2026-09-26"]"#))
    }

    @Test(arguments: [
        AnswerValue.done, .notDone, .dontRemember, .count(done: 3, total: 5), .count(done: 0, total: 5),
        .delayed(days: 3),
    ])
    func validValuesRoundTrip(_ value: AnswerValue) throws {
        let original = try answer(value, covers: day("2026-09-21") ... day("2026-09-25"))
        try original.validate()
        #expect(try roundTrip(original) == original)
    }

    @Test func validationRejectsInconsistentValues() throws {
        let covers = try day("2026-09-25") ... day("2026-09-26")
        #expect(throws: Answer.ValidationError.countOutOfRange(done: 6, total: 5)) {
            try answer(.count(done: 6, total: 5), covers: covers).validate()
        }
        #expect(throws: Answer.ValidationError.countOutOfRange(done: 0, total: 0)) {
            try answer(.count(done: 0, total: 0), covers: covers).validate()
        }
        #expect(throws: Answer.ValidationError.delayNotPositive(0)) {
            try answer(.delayed(days: 0), covers: covers).validate()
        }
        #expect(throws: Answer.ValidationError.perDayEmpty) {
            try answer(.perDay([:]), covers: covers).validate()
        }
        let outside = try day("2026-09-27")
        #expect(throws: Answer.ValidationError.perDayOutsideCovers(outside)) {
            try answer(.perDay([outside: true]), covers: covers).validate()
        }
    }
}

struct PauseEventTests {
    @Test func pausesOnlyListedHabitsWithinInclusiveRange() throws {
        let gym = UUID()
        let pause = try PauseEvent(
            habitIDs: [gym],
            start: day("2026-09-20"),
            end: day("2026-09-22"),
            reason: .other("travel"),
            createdAt: Date(timeIntervalSince1970: 0)
        )
        try pause.validate()
        #expect(try !pause.pauses(gym, on: day("2026-09-19")))
        #expect(try pause.pauses(gym, on: day("2026-09-20")))
        #expect(try pause.pauses(gym, on: day("2026-09-22")))
        #expect(try !pause.pauses(gym, on: day("2026-09-23")))
        #expect(try !pause.pauses(UUID(), on: day("2026-09-21")))
        #expect(try roundTrip(pause) == pause)
    }

    @Test func validationRejectsEmptyAndInverted() throws {
        let start = try day("2026-09-22"), end = try day("2026-09-20")
        let inverted = PauseEvent(habitIDs: [UUID()], start: start, end: end, reason: .sick, createdAt: Date())
        #expect(throws: PauseEvent.ValidationError.endBeforeStart(start: start, end: end)) { try inverted.validate() }
        let empty = PauseEvent(habitIDs: [], start: end, end: start, reason: .manual, createdAt: Date())
        #expect(throws: PauseEvent.ValidationError.noHabits) { try empty.validate() }
    }
}

struct DerivedTypeTests {
    @Test func onlyObservedAggregatedAndHealthFeedTheModel() {
        let feeding = DaySource.allCases.filter(\.feedsModel)
        #expect(feeding == [.observed, .aggregated, .health])
    }

    @Test func questionAndRecordsRoundTrip() throws {
        let question = try Question(
            habitID: UUID(),
            covers: day("2026-09-21") ... day("2026-09-26"),
            shape: .count(total: 4),
            createdAt: Date(timeIntervalSince1970: 1_790_000_000),
            parentContext: ParentContext(parentIDs: [UUID()], parentDoneDays: 4)
        )
        #expect(try roundTrip(question) == question)
        let perDay = try Question(
            habitID: UUID(),
            covers: day("2026-09-25") ... day("2026-09-26"),
            shape: .perDay(days: [day("2026-09-25"), day("2026-09-26")]),
            createdAt: Date(timeIntervalSince1970: 0)
        )
        #expect(try roundTrip(perDay) == perDay)
        let record = try DayRecord(habitID: UUID(), day: day("2026-09-26"), value: 0, source: .observed, confidence: 1)
        #expect(!record.conditionalDenominatorExcluded)
        #expect(try roundTrip(record) == record)
        let state = try SchedulerState(habitID: UUID(), alpha: 3.5, beta: 1.2, lastCoveredDay: day("2026-09-26"))
        #expect(try roundTrip(state) == state)
        let observation = try HealthObservation(habitID: UUID(), day: day("2026-09-26"), sampleID: "abc")
        #expect(try roundTrip(observation) == observation)
    }
}

struct SettingsTests {
    @Test func defaultsMatchDesignAndValidate() throws {
        let settings = Settings.default
        #expect(settings.sessionBudget == 3)
        #expect(settings.dayStartHour == 4)
        #expect(settings.spotCheckRate == 0.05)
        #expect(settings.uncertaintyThreshold == 0.15)
        #expect(settings.decayPerDay == 0.92)
        #expect(settings.maxIntervalDays == 30)
        #expect(settings.notifications.onlyWhenQuestionsDue)
        try settings.validate()
        #expect(try roundTrip(settings) == settings)
    }

    @Test func validationRejectsOutOfRange() {
        var settings = Settings.default
        settings.uncertaintyThreshold = 0.5
        #expect(throws: Settings.ValidationError.uncertaintyThresholdOutOfRange(0.5)) { try settings.validate() }
        settings = .default
        settings.decayPerDay = 0
        #expect(throws: Settings.ValidationError.decayPerDayOutOfRange(0)) { try settings.validate() }
        settings = .default
        settings.notifications.cadence = .timesPerDay([])
        #expect(throws: NotificationSettings.ValidationError.noTimes) { try settings.validate() }
    }

    @Test func quietHoursWrapPastMidnight() throws {
        let night = try QuietHours(startHour: 22, endHour: 7)
        #expect(night.contains(hour: 22))
        #expect(night.contains(hour: 0))
        #expect(night.contains(hour: 6))
        #expect(!night.contains(hour: 7))
        #expect(!night.contains(hour: 21))
        let afternoon = try QuietHours(startHour: 13, endHour: 15)
        #expect(afternoon.contains(hour: 14))
        #expect(!afternoon.contains(hour: 15))
        #expect(throws: QuietHours.ValidationError.empty) { try QuietHours(startHour: 5, endHour: 5) }
        #expect(throws: QuietHours.ValidationError.hourOutOfRange(24)) { try QuietHours(startHour: 22, endHour: 24) }
    }

    @Test func decodingRejectsOutOfRangeTimes() throws {
        #expect(try roundTrip(TimeOfDay(hour: 23, minute: 59)) == TimeOfDay(hour: 23, minute: 59))
        #expect(throws: TimeOfDay.ValidationError.outOfRange(hour: 24, minute: 0)) {
            try JSONDecoder().decode(TimeOfDay.self, from: Data(#"{"hour":24,"minute":0}"#.utf8))
        }
        #expect(throws: QuietHours.ValidationError.empty) {
            try JSONDecoder().decode(QuietHours.self, from: Data(#"{"startHour":3,"endHour":3}"#.utf8))
        }
    }
}
