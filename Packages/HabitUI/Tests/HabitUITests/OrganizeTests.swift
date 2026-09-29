import Foundation
import HabitCore
import HabitStore
@testable import HabitUI
import Testing

/// Archiving, deleting and ordering habits and clusters (DESIGN.md §5.1, §10).
@MainActor
struct OrganizeTests {
    @Test func archivingHidesAHabitAndRestoringBringsItBackWithItsHistory() throws {
        let model = try Harness().model()
        let gym = try addHabit(model, "Gym")
        let question = try #require(model.questions.first)
        try model.answer(question, with: .done)

        try model.archive(gym.id)
        #expect(model.activeHabits.isEmpty)
        #expect(model.archivedHabits.map(\.id) == [gym.id])
        #expect(model.dueHabitIDs.isEmpty)

        try model.restore(gym.id)
        #expect(model.activeHabits.map(\.id) == [gym.id])
        #expect(model.archivedHabits.isEmpty)
        #expect(model.truth.answers.map(\.habitID) == [gym.id])
        #expect(model.history(of: gym.id).first?.source == .observed)
    }

    @Test func deletingAHabitRemovesItsHistoryAndFreesItsChildren() throws {
        let harness = try Harness()
        let model = try harness.model()
        let gym = try addHabit(model, "Gym")
        var shake = try addHabit(model, "Shake")
        shake.dependencies = [Dependency(parentID: gym.id)]
        try model.save(shake)
        for question in model.questions {
            try model.answer(question, with: .done)
        }

        try model.delete(gym.id)
        #expect(model.activeHabits.map(\.name) == ["Shake"])
        #expect(model.gateParents(of: shake.id).isEmpty)
        #expect(!model.truth.answers.contains { $0.habitID == gym.id })
        #expect(!model.truth.habitRevisions.contains { $0.habit.id == gym.id })
        // A relaunch loads the same truth (records written at the same instant load in ID order).
        let relaunched = try harness.model().truth
        #expect(relaunched.habits == model.truth.habits)
        #expect(relaunched.answers == model.truth.answers)
        #expect(Set(relaunched.questions) == Set(model.truth.questions))
        #expect(Set(relaunched.habitRevisions) == Set(model.truth.habitRevisions))
    }

    @Test func draggingAHabitReordersItsGroupOnlyAndPersistsWithoutRevisions() throws {
        let harness = try Harness()
        let model = try harness.model()
        let morning = Cluster(name: "Morning", colorHex: "#FF9900")
        try model.save(morning)
        var gym = try addHabit(model, "Gym")
        gym.clusterID = morning.id
        try model.save(gym)
        for name in ["A", "B", "C"] {
            _ = try addHabit(model, name)
        }
        let ids = Dictionary(uniqueKeysWithValues: model.activeHabits.map { ($0.name, $0.id) })
        let revisions = model.truth.habitRevisions.count

        try model.move(habit: #require(ids["C"]), to: #require(ids["A"]))
        #expect(model.activeHabits.map(\.name) == ["Gym", "C", "A", "B"])
        try model.move(habit: #require(ids["C"]), to: #require(ids["B"]))
        #expect(model.activeHabits.map(\.name) == ["Gym", "A", "B", "C"])
        // Another group: nothing moves.
        try model.move(habit: #require(ids["A"]), to: gym.id)
        #expect(model.activeHabits.map(\.name) == ["Gym", "A", "B", "C"])
        #expect(model.truth.habitRevisions.count == revisions)
        #expect(try harness.model().activeHabits.map(\.name) == ["Gym", "A", "B", "C"])
    }

    @Test func draggingAClusterReordersTheGroups() throws {
        let harness = try Harness()
        let model = try harness.model()
        for name in ["Evening", "Morning"] {
            var habit = try addHabit(model, name)
            let cluster = Cluster(name: name, colorHex: "#FF9900")
            try model.save(cluster)
            habit.clusterID = cluster.id
            try model.save(habit)
        }
        _ = try addHabit(model, "Loose")
        #expect(model.habitsByCluster.map(\.cluster?.name) == ["Evening", "Morning", nil])
        let evening = try #require(model.clusters.first)
        let morning = try #require(model.clusters.last)

        try model.move(cluster: morning.id, to: evening.id)
        #expect(model.habitsByCluster.map(\.cluster?.name) == ["Morning", "Evening", nil])
        #expect(model.activeHabits.map(\.name) == ["Morning", "Evening", "Loose"])
        #expect(try harness.model().clusters.map(\.name) == ["Morning", "Evening"])
    }

    @Test func movingRenumbersOnlyWhatChanged() throws {
        let habits = (0 ..< 4).map { (index: Int) in
            Habit(name: "\(index)", colorHex: "#000000", createdAt: noon, createdDay: start, listOrder: index)
        }
        let moved = try #require(ListOrder.moving(habits[3].id, to: habits[1].id, in: habits))
        #expect(moved.map(\.name) == ["3", "1", "2"])
        #expect(moved.map(\.listOrder) == [1, 2, 3])
        #expect(ListOrder.moving(habits[0].id, to: habits[0].id, in: habits) == nil)
        #expect(ListOrder.moving(UUID(), to: habits[0].id, in: habits) == nil)
    }

    @Test func deletingAClusterMovesItsHabitsToNoCluster() throws {
        let harness = try Harness()
        let model = try harness.model()
        let morning = Cluster(name: "Morning", colorHex: "#FF9900")
        try model.save(morning)
        var gym = try addHabit(model, "Gym")
        gym.clusterID = morning.id
        try model.save(gym)
        _ = try addHabit(model, "Read")

        try model.deleteCluster(morning.id)
        #expect(model.clusters.isEmpty)
        #expect(model.habitsByCluster.map(\.cluster) == [nil])
        #expect(model.activeHabits.map(\.name) == ["Gym", "Read"])
        #expect(try harness.model().habit(gym.id)?.clusterID == nil)
    }

    @Test func undoingAnAnswerBringsTheSameCardBack() throws {
        let harness = try Harness()
        let model = try harness.model()
        let gym = try addHabit(model, "Gym")
        let question = try #require(model.questions.first)
        try model.answer(question, with: .done)
        #expect(model.questions.isEmpty)
        #expect(model.lastAnswered?.habitID == gym.id)

        try model.undoLastAnswer()
        #expect(model.questions == [question])
        #expect(model.truth.answers.isEmpty)
        #expect(model.lastAnswered == nil)
        #expect(model.todayStatus(of: gym.id) == .due)
        let relaunched = try harness.model()
        #expect(relaunched.truth.answers.isEmpty)
        #expect(relaunched.questions.map(\.id) == [question.id])
    }

    @Test func undoingADelayEndsItsPause() throws {
        let model = try Harness().model()
        let gym = try addHabit(model, "Gym")
        let question = try #require(model.questions.first)
        try model.delay(question, days: 3, reason: .manual)
        #expect(model.resumeDay(of: gym.id) != nil)

        try model.undoLastAnswer()
        #expect(model.truth.pauses.isEmpty)
        #expect(model.resumeDay(of: gym.id) == nil)
        #expect(model.questions.map(\.id) == [question.id])
    }
}
