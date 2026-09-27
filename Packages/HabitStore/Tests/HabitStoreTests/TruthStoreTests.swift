import Foundation
import HabitCore
@testable import HabitStore
import SwiftData
import Testing

@MainActor
struct TruthStoreTests {
    private let day = DayKey(dayNumber: 20723)
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func habit(_ name: String, dependencies: [Dependency] = []) -> Habit {
        Habit(
            name: name, emoji: "🏋️", colorHex: "#3366CC", createdAt: now, createdDay: day,
            dependencies: dependencies, healthBinding: .workout(minMinutes: 20)
        )
    }

    /// One of every truth type, with the enum cases SwiftData composites would have struggled with.
    private func sampleTruth() throws -> Truth {
        let gym = habit("Gym")
        let stretch = habit("Stretch", dependencies: [Dependency(parentID: gym.id, mode: .sequence)])
        let covers = day.adding(days: -2) ... day
        let question = Question(
            habitID: gym.id, covers: covers, shape: .perDay(days: Array(covers)), createdAt: now,
            presentedAt: now, parentContext: ParentContext(parentIDs: [gym.id], parentDoneDays: 2)
        )
        func answer(_ value: AnswerValue, offset: TimeInterval) -> Answer {
            Answer(
                questionID: question.id, habitID: gym.id, covers: covers, value: value,
                answeredAt: now.addingTimeInterval(offset), timezone: "Europe/Sarajevo", channel: .app
            )
        }
        var settings = Settings.default
        settings.sessionBudget = 5
        settings.notifications.quietHours = try QuietHours(startHour: 22, endHour: 7)
        return Truth(
            habits: [gym, stretch],
            clusters: [Cluster(name: "Morning", colorHex: "#FF9900")],
            habitRevisions: [HabitRevision(habit: gym, editedAt: now)],
            questions: [question],
            answers: [
                answer(.perDay([day: true, day.adding(days: -1): false]), offset: 1),
                answer(.count(done: 2, total: 3), offset: 2),
                answer(.dontRemember, offset: 3),
                answer(.delayed(days: 3), offset: 4),
            ],
            pauses: [PauseEvent(
                habitIDs: [gym.id],
                start: day,
                end: day.adding(days: 2),
                reason: .other("Flu"),
                createdAt: now
            )],
            healthObservations: [HealthObservation(habitID: gym.id, day: day, sampleID: "HK-1")],
            settings: settings
        )
    }

    private func write(_ truth: Truth, to store: TruthStore) throws {
        for (offset, habit) in truth.habits.enumerated() {
            try store.save(habit, editedAt: now.addingTimeInterval(TimeInterval(offset)))
        }
        try truth.questions.forEach { try store.save($0, at: now) }
        try truth.answers.forEach(store.append)
        try truth.pauses.forEach { try store.save($0, at: now) }
        try store.save(truth.settings, at: now)
    }

    @Test func emptyStoreLoadsDefaultSettings() throws {
        let truth = try TruthStore(container: StoreContainer.make(.inMemory)).load()
        #expect(truth == Truth(habits: []))
    }

    @Test func roundTripsEveryWrittenType() throws {
        let store = try TruthStore(container: StoreContainer.make(.inMemory))
        let truth = try sampleTruth()
        try write(truth, to: store)
        let loaded = try store.load()
        #expect(loaded.habits == truth.habits)
        #expect(loaded.questions == truth.questions)
        #expect(loaded.answers == truth.answers)
        #expect(loaded.pauses == truth.pauses)
        #expect(loaded.settings == truth.settings)
        // One revision per saved habit, snapshotting it (§3.2).
        #expect(loaded.habitRevisions.map(\.habit) == truth.habits)
        try loaded.validate()
    }

    /// §10: a `.sequence` edge must survive the store unchanged, not be coerced to `.gate`.
    @Test func sequenceEdgeSurvivesStore() throws {
        let store = try TruthStore(container: StoreContainer.make(.inMemory))
        let truth = try sampleTruth()
        try write(truth, to: store)
        let stretch = try #require(store.load().habits.first { $0.name == "Stretch" })
        #expect(stretch.dependencies.map(\.mode) == [.sequence])
        #expect(stretch.gateParentIDs.isEmpty)
    }

    @Test func editingAHabitUpdatesItInPlaceAndAppendsARevision() throws {
        let store = try TruthStore(container: StoreContainer.make(.inMemory))
        var gym = habit("Gym")
        try store.save(gym, editedAt: now)
        gym.name = "Gym (weights)"
        gym.importance = .high
        try store.save(gym, editedAt: now.addingTimeInterval(60))
        let loaded = try store.load()
        #expect(loaded.habits == [gym])
        #expect(loaded.habitRevisions.map(\.habit.name) == ["Gym", "Gym (weights)"])
    }

    @Test func dismissingAQuestionUpdatesTheLoggedQuestion() throws {
        let store = try TruthStore(container: StoreContainer.make(.inMemory))
        let gym = habit("Gym")
        try store.save(gym, editedAt: now)
        var question = Question(
            habitID: gym.id,
            covers: day ... day,
            shape: .singleDay,
            createdAt: now,
            presentedAt: now
        )
        try store.save(question, at: now)
        question.dismissedAt = now.addingTimeInterval(5)
        try store.save(question, at: now.addingTimeInterval(5))
        #expect(try store.load().questions == [question])
    }

    @Test func latestSettingsWin() throws {
        let store = try TruthStore(container: StoreContainer.make(.inMemory))
        var settings = Settings.default
        settings.dayStartHour = 5
        try store.save(settings, at: now)
        settings.dayStartHour = 6
        try store.save(settings, at: now.addingTimeInterval(1))
        #expect(try store.load().settings.dayStartHour == 6)
    }

    @Test func invalidValuesAreRejectedAndNotStored() throws {
        let store = try TruthStore(container: StoreContainer.make(.inMemory))
        #expect(throws: Habit.ValidationError.emptyName) {
            try store.save(habit("  "), editedAt: now)
        }
        var settings = Settings.default
        settings.sessionBudget = 0
        #expect(throws: Settings.ValidationError.sessionBudgetOutOfRange(0)) {
            try store.save(settings, at: now)
        }
        let answer = Answer(
            questionID: UUID(), habitID: UUID(), covers: day ... day, value: .count(done: 4, total: 3),
            answeredAt: now, timezone: "UTC", channel: .app
        )
        #expect(throws: Answer.ValidationError.countOutOfRange(done: 4, total: 3)) {
            try store.append(answer)
        }
        #expect(try store.load() == Truth(habits: []))
    }

    /// Kill and relaunch (M2 checkpoint): a new container on the same file sees everything.
    @Test func truthPersistsAcrossContainers() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("store")
        defer { try? FileManager.default.removeItem(at: url) }
        let truth = try sampleTruth()
        try write(truth, to: TruthStore(container: StoreContainer.make(.file(url))))
        let reloaded = try TruthStore(container: StoreContainer.make(.file(url))).load()
        #expect(reloaded.habits == truth.habits)
        #expect(reloaded.answers == truth.answers)
    }

    @Test func eraseAllRemovesEverything() throws {
        let store = try TruthStore(container: StoreContainer.make(.inMemory))
        try write(sampleTruth(), to: store)
        try store.eraseAll()
        #expect(try store.load() == Truth(habits: []))
    }

    /// §10 CloudKit constraints, checked on the schema so a new property can't slip past review.
    @Test func schemaMeetsCloudKitConstraints() {
        for entity in StoreContainer.schema.entities {
            #expect(entity.uniquenessConstraints.isEmpty, "\(entity.name) has uniqueness constraints")
            let requiredRelationships = entity.relationships.filter { !$0.isOptional }.map(\.name)
            #expect(requiredRelationships.isEmpty, "\(entity.name) has required relationships")
            for attribute in entity.attributes {
                #expect(!attribute.isUnique, "\(entity.name).\(attribute.name) is unique")
                #expect(
                    attribute.isOptional || attribute.defaultValue != nil,
                    "\(entity.name).\(attribute.name) has no default"
                )
            }
        }
    }
}
