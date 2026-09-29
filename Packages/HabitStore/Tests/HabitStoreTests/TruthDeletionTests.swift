import Foundation
import HabitCore
@testable import HabitStore
import SwiftData
import Testing

/// Deletion records (DESIGN.md §10): a deletion is a write that removes older rows on every device.
@MainActor
struct TruthDeletionTests {
    private let day = DayKey(dayNumber: 20723)
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func store() throws -> TruthStore {
        try TruthStore(container: StoreContainer.make(.inMemory))
    }

    private func habit(_ name: String, parent: Habit? = nil, cluster: Cluster? = nil) -> Habit {
        Habit(
            name: name, colorHex: "#3366CC", createdAt: now, createdDay: day,
            dependencies: parent.map { [Dependency(parentID: $0.id)] } ?? [], clusterID: cluster?.id
        )
    }

    private func answer(_ habit: Habit, at date: Date) -> Answer {
        Answer(
            questionID: UUID(), habitID: habit.id, covers: day ... day, value: .done, answeredAt: date,
            timezone: "UTC", channel: .app
        )
    }

    private func pause(_ habits: Habit...) -> PauseEvent {
        PauseEvent(habitIDs: habits.map(\.id), start: day, end: day, reason: .vacation, createdAt: now)
    }

    private func rowCount(_ store: TruthStore) throws -> Int {
        try store.context.fetchCount(FetchDescriptor<TruthRecord>())
    }

    @Test func deletingAHabitRemovesItsRecordsAndReferences() throws {
        let store = try store()
        let gym = habit("Gym")
        let read = habit("Read")
        let shake = habit("Shake", parent: gym)
        let vacation = pause(gym, read)
        for saved in [gym, read, shake] {
            try store.save(saved, editedAt: now)
        }
        try store.append(answer(gym, at: now))
        try store.append(answer(read, at: now))
        try store.save(vacation, at: now)
        try store.save(pause(gym), at: now)

        try store.delete([.habit(gym.id)], at: now.addingTimeInterval(60))
        let loaded = try store.load()
        #expect(Set(loaded.habits.map(\.name)) == ["Read", "Shake"])
        #expect(loaded.habits.flatMap(\.dependencies).isEmpty)
        #expect(Set(loaded.habitRevisions.map(\.habit.name)) == ["Read", "Shake"])
        #expect(loaded.answers.map(\.habitID) == [read.id])
        #expect(loaded.pauses.map(\.id) == [vacation.id])
        #expect(loaded.pauses.first?.habitIDs == [read.id])
        try loaded.validate()
        // Gym, its revision, answer and own pause are gone; the deletion record stays.
        #expect(try rowCount(store) == 2 + 2 + 1 + 1 + 1)
    }

    @Test func deletingAClusterLeavesItsHabitsInNoCluster() throws {
        let store = try store()
        let morning = Cluster(name: "Morning", colorHex: "#FF9900")
        try store.save(morning, at: now)
        try store.save(habit("Gym", cluster: morning), editedAt: now)
        try store.delete([.cluster(morning.id)], at: now.addingTimeInterval(60))
        let loaded = try store.load()
        #expect(loaded.clusters.isEmpty)
        #expect(loaded.habits.map(\.clusterID) == [nil])
    }

    @Test func deletingAnAnswerAndItsPauseKeepsTheRest() throws {
        let store = try store()
        let gym = habit("Gym")
        try store.save(gym, editedAt: now)
        let kept = answer(gym, at: now)
        let undone = answer(gym, at: now.addingTimeInterval(1))
        let delay = pause(gym)
        try store.append(kept)
        try store.append(undone)
        try store.save(delay, at: now)
        try store.delete([.answer(undone.id), .pause(delay.id)], at: now.addingTimeInterval(2))
        let loaded = try store.load()
        #expect(loaded.answers == [kept])
        #expect(loaded.pauses.isEmpty)
        #expect(loaded.habits == [gym])
    }

    /// An offline device's answer arriving after the habit was deleted stays deleted; a later write of the
    /// habit itself (a JSON import) brings it back.
    @Test func lateWritesAreDeletedUnlessNewerThanTheDeletion() throws {
        let phone = try store()
        var changes: [TruthChange] = []
        phone.onChange = { changes.append(contentsOf: $0) }
        let gym = habit("Gym")
        try phone.save(gym, editedAt: now)
        try phone.delete([.habit(gym.id)], at: now.addingTimeInterval(60))
        #expect(changes.last?.kind == "deletion")

        let watch = try store()
        try watch.merge(changes)
        #expect(try watch.load().habits.isEmpty)
        let late = try TruthChange(
            kind: "answer", id: UUID(),
            payload: JSONEncoder().encode(answer(gym, at: now.addingTimeInterval(30))),
            updatedAt: now.addingTimeInterval(30)
        )
        #expect(try watch.merge([late]))
        #expect(try watch.load().answers.isEmpty)

        try watch.save(imported: Truth(habits: [gym]), includingSettings: false, at: now.addingTimeInterval(120))
        #expect(try watch.load().habits == [gym])
    }

    @Test func mergeRefusesDeletionsOfUndeletableKinds() throws {
        let store = try store()
        let change = try TruthChange(
            kind: "deletion", id: UUID(), payload: JSONEncoder().encode(TruthDeletion(kind: "settings")),
            updatedAt: now
        )
        #expect(throws: StoreError.unknownKind("settings")) { try store.merge([change]) }
    }
}
