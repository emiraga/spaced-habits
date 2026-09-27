import Foundation
import HabitCore
@testable import HabitUI
import Testing

/// Adds "Protein", gated by `gym`.
@MainActor
private func addProtein(_ model: AppModel, after gym: Habit) throws -> Habit {
    var protein = model.newHabitDraft()
    protein.name = "Protein"
    protein.dependencies = [Dependency(parentID: gym.id)]
    try model.save(protein)
    return protein
}

/// The §13 M4 checkpoint, driven through `AppModel` and the debug "advance day" control.
@MainActor
struct DependencyTests {
    /// Gym "no" for a week: Protein is never asked, and its days are "not done (parent not done)".
    @Test func checkpointFailingParentNeverAsksChild() throws {
        let model = try Harness().model()
        let gym = try addHabit(model, "Gym")
        let protein = try addProtein(model, after: gym)
        for day in 0 ..< 7 {
            if day > 0 {
                try model.advanceDay()
            }
            #expect(model.questions.map(\.habitID) == [gym.id])
            #expect(!model.dueHabitIDs.contains(protein.id))
            try model.answer(#require(model.questions.first), with: .notDone)
            #expect(model.questions.isEmpty)
        }
        let history = model.history(of: protein.id)
        #expect(history.count == 7)
        #expect(history.allSatisfy { $0.source == .observed && $0.value == 0 && $0.conditionalDenominatorExcluded })
        #expect(model.adherence(of: protein.id) == nil)
        #expect(model.adherence(of: protein.id, includingParentMisses: true)?.days == 7)
    }

    /// Gym 4 of 6: the Protein card follows in the same session and asks about "those 4".
    @Test func checkpointChildCardAsksAboutParentDoneDays() throws {
        let model = try Harness().model()
        let gym = try addHabit(model, "Gym")
        let protein = try addProtein(model, after: gym)
        for _ in 0 ..< 5 {
            try model.advanceDay()
        }
        let gymQuestion = try #require(model.questions.first)
        #expect(model.questions.map(\.habitID) == [gym.id])
        #expect(gymQuestion.shape == .count(total: 6))
        try model.answer(gymQuestion, with: .count(done: 4, total: 6))

        let question = try #require(model.questions.first)
        #expect(question.habitID == protein.id)
        #expect(question.shape == .count(total: 4))
        #expect(question.parentContext == ParentContext(parentIDs: [gym.id], parentDoneDays: 4))
        #expect(model.parentNames(for: question) == ["Gym"])
        let context = try #require(question.parentContext)
        #expect(
            QuestionCard.contextLine(parentNames: ["Gym"], context: context, coverDays: question.covers.count)
                == "You did Gym on 4 of the last 6 days."
        )
        #expect(QuestionCard.prompt(for: question) == "On how many of those 4?")
    }

    /// Per-day toggles list only the days Gym was done, when each is exactly known.
    @Test func childPerDayTogglesOnlyParentDoneDays() throws {
        let model = try Harness().model()
        let gym = try addHabit(model, "Gym")
        let protein = try addProtein(model, after: gym)
        try model.advanceDay()
        try model.advanceDay()
        let days = Array(model.today.adding(days: -2) ... model.today)
        try model.answer(
            #require(model.questions.first { $0.habitID == gym.id }),
            with: .perDay([days[0]: true, days[1]: false, days[2]: true])
        )
        let question = try #require(model.questions.first { $0.habitID == protein.id })
        #expect(question.shape == .perDay(days: [days[0], days[2]]))
        #expect(QuestionCard.prompt(for: question) == "Which of those days?")
    }

    /// Pausing Gym blocks Protein: not asked, and its history shows blocked, not paused.
    @Test func checkpointPausedParentBlocksChild() throws {
        let model = try Harness().model()
        let gym = try addHabit(model, "Gym")
        let protein = try addProtein(model, after: gym)
        try model.pause(gym.id, from: model.today, through: model.today.adding(days: 1), reason: .manual)
        #expect(model.questions.isEmpty)
        #expect(model.todayStatus(of: protein.id) == .blocked)
        try model.advanceDay()
        try model.advanceDay()
        #expect(model.history(of: protein.id).dropFirst().map(\.source) == [.blocked, .blocked])
        #expect(model.history(of: gym.id).dropFirst().map(\.source) == [.paused, .paused])
    }

    /// A → B → A is refused with a readable message, both when picked and on save.
    @Test func checkpointEditorRefusesCycles() throws {
        let model = try Harness().model()
        let gym = try addHabit(model, "Gym")
        let protein = try addProtein(model, after: gym)
        var edited = try #require(model.habit(gym.id))
        #expect(model.parentCandidates(for: edited).map(\.id) == [protein.id])

        let expected = DependencyCycleError(names: ["Gym", "Protein", "Gym"])
        #expect(throws: expected) { try model.checkDependency(on: protein.id, for: edited) }
        #expect(
            expected.errorDescription
                == "Gym can't depend on Protein: that would make a loop (Gym would need Protein, which needs Gym)."
        )
        edited.dependencies = [Dependency(parentID: protein.id)]
        let revisions = model.truth.habitRevisions.count
        #expect(throws: expected) { try model.save(edited) }
        #expect(model.habit(gym.id)?.dependencies == [])
        #expect(model.truth.habitRevisions.count == revisions)

        let stretch = try addHabit(model, "Stretch")
        try model.checkDependency(on: gym.id, for: stretch)
    }

    @Test func gateParentsAndChildrenIgnoreSequenceEdges() throws {
        let model = try Harness().model()
        let gym = try addHabit(model, "Gym")
        let protein = try addProtein(model, after: gym)
        var stretch = model.newHabitDraft()
        stretch.name = "Stretch"
        stretch.dependencies = [Dependency(parentID: gym.id, mode: .sequence)]
        try model.save(stretch)
        #expect(model.gateParents(of: protein.id).map(\.id) == [gym.id])
        #expect(model.gateParents(of: stretch.id).isEmpty)
        #expect(model.gatedChildren(of: gym.id).map(\.id) == [protein.id])
    }

    @Test func clustersGroupTheHabitList() throws {
        let model = try Harness().model()
        try model.addSampleHabits()
        var morning = model.newClusterDraft()
        morning.name = "Morning"
        try model.save(morning)
        var gym = try #require(model.activeHabits.first { $0.name == "Gym" })
        gym.clusterID = morning.id
        try model.save(gym)
        morning.name = "Mornings"
        try model.save(morning)

        #expect(model.clusters.map(\.name) == ["Mornings"])
        #expect(model.cluster(gym.clusterID) == morning)
        #expect(model.habitsByCluster.map(\.cluster?.name) == ["Mornings", nil])
        #expect(model.habitsByCluster.map { $0.habits.map(\.name) } == [["Gym"], ["Meditate", "Read"]])
        #expect(try Harness(location: .inMemory).model().clusters.isEmpty)
        try model.truth.validate()
    }
}
