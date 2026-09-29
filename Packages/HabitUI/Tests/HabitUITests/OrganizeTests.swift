import Foundation
import HabitCore
import HabitStore
@testable import HabitUI
import Testing

/// Archiving, deleting and ordering habits and clusters (DESIGN.md §13 M12).
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
}
