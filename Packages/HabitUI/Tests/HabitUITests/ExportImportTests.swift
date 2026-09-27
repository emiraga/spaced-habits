import Foundation
import HabitCore
import HabitSimulation
@testable import HabitUI
import Testing

/// Export and import through the app model (DESIGN.md §11, §13 M10).
@MainActor
struct ExportImportTests {
    /// A history with everything the app writes: a simulated gated pair ending today, then a cluster, an
    /// edit, answered and "Later" cards, a pause, a cancelled vacation and changed settings.
    private func populatedModel() throws -> AppModel {
        let run = try Simulator.run(.dependentPair(), start: start.adding(days: 1 - Scenario.dependentPair().days))
        let model = try Harness().model()
        try model.importJSON(DataExport(truth: run.log, projected: run.projected, exportedAt: noon).json())
        var cluster = model.newClusterDraft()
        cluster.name = "Morning"
        try model.save(cluster)
        var parent = try #require(model.truth.habits.first { $0.dependencies.isEmpty })
        parent.clusterID = cluster.id
        parent.notes = "Before work, \"always\""
        try model.save(parent)
        let reading = try addHabit(model, "Read")
        try model.pause(reading.id, from: start.adding(days: 3), through: start.adding(days: 5), reason: .sick)
        var settings = model.truth.settings
        settings.sessionBudget = 5
        try model.save(settings)
        try model.startSession()
        if let first = model.questions.first {
            try model.answer(first, with: allDone(first))
        }
        if let later = model.questions.first {
            try model.later(later)
        }
        return model
    }

    /// §13 M10 checkpoint: export → wipe → import shows the same state, and re-exporting is byte-identical.
    @Test func checkpointExportWipeImportReexportIsIdentical() throws {
        let original = try populatedModel()
        let exported = try original.dataExport().json()

        let restored = try Harness().model()
        let summary = try restored.importJSON(exported)
        #expect(summary.updated == 0 && summary.added > 0 && summary.settingsChanged)

        #expect(try restored.dataExport().json() == exported)
        #expect(restored.projected == original.projected)
        #expect(restored.activeHabits == original.activeHabits)
        #expect(restored.clusters == original.clusters)
        // The same cards (a fresh session also brings back the "Later" one, as a relaunch would).
        try original.startSession()
        #expect(restored.questions.map(\.covers) == original.questions.map(\.covers))
        #expect(restored.questions.map(\.habitID) == original.questions.map(\.habitID))
        #expect(restored.dueHabitIDs == original.dueHabitIDs)

        // Importing the same file again changes nothing.
        #expect(try restored.importJSON(exported).changedNothing)
        #expect(try restored.dataExport().json() == exported)
    }

    /// A relaunch shows the open card it logged before instead of logging a second question.
    @Test func relaunchReusesOpenLoggedQuestions() throws {
        let harness = try Harness()
        let model = try harness.model()
        _ = try addHabit(model, "Gym")
        let logged = model.truth.questions
        #expect(logged.count == 1)
        let relaunched = try harness.model()
        #expect(relaunched.truth.questions == logged)
        #expect(relaunched.questions.map(\.id) == logged.map(\.id))
    }

    @Test func importIntoAnotherHistoryAddsAndNeverDeletes() throws {
        let other = try Harness().model()
        _ = try addHabit(other, "Gym")
        let exported = try other.dataExport().json()

        let model = try Harness().model()
        _ = try addHabit(model, "Read")
        let summary = try model.importJSON(exported)
        #expect(summary.added == 3) // habit, revision, question
        #expect(Set(model.activeHabits.map(\.name)) == ["Gym", "Read"])
    }

    /// Locally Shake gates on Gym; the file makes Gym gate on Shake. Neither side has a cycle, the merge does.
    @Test func importRejectsACycleByNameAndWritesNothing() throws {
        let model = try Harness().model()
        var gym = try addHabit(model, "Gym")
        var shake = try addHabit(model, "Shake")
        shake.dependencies = [Dependency(parentID: gym.id)]
        try model.save(shake)
        gym.dependencies = [Dependency(parentID: shake.id)]
        let file = try ExportCodec.encode(ExportDocument(
            truth: Truth(habits: [gym], settings: model.truth.settings), exportedAt: noon
        ))
        let before = try model.store.load()
        #expect(throws: DependencyCycleError(names: ["Gym", "Shake", "Gym"])) { try model.importJSON(file) }
        #expect(try model.store.load() == before)
    }

    @Test func importRefusesAnUnknownSchemaVersion() throws {
        let model = try Harness().model()
        let json = try #require(String(bytes: model.dataExport().json(), encoding: .utf8))
            .replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 9")
        #expect(throws: ImportError.unsupportedSchemaVersion(9)) { try model.importJSON(Data(json.utf8)) }
    }
}
