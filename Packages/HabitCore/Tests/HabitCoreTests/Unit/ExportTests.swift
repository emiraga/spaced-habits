import Foundation
@testable import HabitCore
@testable import HabitSimulation
import Testing

struct ExportGoldenTests {
    @Test func jsonMatchesGolden() throws {
        try ExportSample.expectGolden(ExportSample.export().json(), "export.json")
    }

    @Test func csvFilesMatchGoldens() throws {
        let files = try ExportSample.export().csvFiles()
        #expect(files.map(\.name) == [
            "days.csv", "habits.csv", "habit_revisions.csv", "answers.csv", "questions.csv", "pauses.csv",
            "clusters.csv", "dependencies.csv", "health_observations.csv",
        ])
        for file in files {
            try ExportSample.expectGolden(Data(file.contents.utf8), file.name)
        }
    }
}

struct ExportDocumentTests {
    @Test func exportImportExportIsByteIdentical() throws {
        let first = try ExportSample.export().json()
        let document = try ExportCodec.decodeDocument(first)
        #expect(document.exportedAt == ExportDate.date(from: "2026-09-27T12:00:00.123Z"))
        #expect(document.dayRecords == nil)
        let second = try ExportSample.export(document.truth).json()
        #expect(first == second)
    }

    @Test func orderDoesNotDependOnStoreOrder() throws {
        var shuffled = try ExportSample.truth()
        shuffled.habits.reverse()
        shuffled.answers.reverse()
        shuffled.questions.reverse()
        shuffled.pauses.reverse()
        shuffled.habitRevisions.reverse()
        #expect(try ExportSample.export(shuffled).json() == ExportSample.export().json())
    }

    @Test func includeProjectionAddsEveryDayRecord() throws {
        let export = try ExportSample.export()
        let document = try ExportCodec.decodeDocument(export.json(includeProjection: true))
        let records = try #require(document.dayRecords)
        #expect(records.count == export.projected.records.values.map(\.count).reduce(0, +))
        #expect(records.first?.habitID == export.truth.habits.first?.id)
    }

    @Test func refusesOtherSchemaVersions() throws {
        let json = try #require(try String(bytes: ExportSample.export().json(), encoding: .utf8))
        let future = Data(json.replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 2").utf8)
        #expect(throws: ImportError.unsupportedSchemaVersion(2)) { try ExportCodec.decodeDocument(future) }
        let bare = try ExportCodec.encode(ExportSample.truth())
        #expect(throws: ImportError.invalidDocument("schemaVersion: missing")) { try ExportCodec.decodeDocument(bare) }
    }

    @Test func unknownDependencyModeFailsWithItsPath() throws {
        let json = try #require(try String(bytes: ExportSample.export().json(), encoding: .utf8))
        let chained = Data(json.replacingOccurrences(of: "\"mode\" : \"sequence\"", with: "\"mode\" : \"chain\"").utf8)
        do {
            _ = try ExportCodec.decodeDocument(chained)
            Issue.record("Decoded an unknown mode")
        } catch let ImportError.invalidDocument(detail) {
            // Canonical order: Gym, Old, Shake, Stretch.
            #expect(detail.hasPrefix("habits[3].dependencies[0].mode: "))
            #expect(detail.contains("chain"))
        }
    }
}

struct ExportDateTests {
    @Test func formatsUTCWithMilliseconds() {
        #expect(ExportDate.string(from: ExportSample.noon) == "2026-09-27T12:00:00.000Z")
        #expect(ExportDate.string(from: ExportSample.noon.addingTimeInterval(0.0015)) == "2026-09-27T12:00:00.002Z")
        #expect(ExportDate.string(from: Date(timeIntervalSince1970: -0.5)) == "1969-12-31T23:59:59.500Z")
    }

    @Test func parsedDatesFormatBackToTheSameString() {
        var random = SeededRandomSource(seed: 3)
        for _ in 0 ..< 10000 {
            let date = Date(timeIntervalSince1970: random.nextUnit() * 4_000_000_000)
            let string = ExportDate.string(from: date)
            let parsed = ExportDate.date(from: string)
            #expect(parsed.map(ExportDate.string) == string)
        }
    }

    @Test func parsesOptionalFractionsAndRejectsTheRest() {
        #expect(ExportDate.date(from: "2026-09-27T12:00:00Z") == ExportSample.noon)
        #expect(ExportDate.date(from: "2026-09-27T12:00:00.5Z") == ExportSample.noon.addingTimeInterval(0.5))
        for bad in [
            "2026-09-27 12:00:00Z", "2026-09-27T12:00:00", "2026-09-27T24:00:00Z", "2026-02-30T12:00:00Z",
            "2026-09-27T12:00:00.1234Z", "2026-09-27T+1:00:00Z", "2026-09-27T12:00:00.-1Z",
        ] {
            #expect(ExportDate.date(from: bad) == nil, "\(bad)")
        }
    }
}

struct TruthImportTests {
    @Test func importsEverythingIntoAnEmptyStoreThenNothingTwice() throws {
        let imported = try ExportCodec.decodeDocument(ExportSample.export().json()).truth
        let first = try TruthImport(imported, into: Truth(habits: []))
        #expect(first.added == 4 + 1 + 4 + 3 + 6 + 4 + 1)
        #expect(first.updated == 0)
        #expect(first.settingsChanged)
        #expect(first.merged == imported)
        let second = try TruthImport(imported, into: first.merged)
        #expect(second.added == 0 && second.updated == 0 && !second.settingsChanged)
        #expect(second.changes == Truth(habits: [], settings: imported.settings))
    }

    /// Local copies differ from their export only below a millisecond: importing a device's own export
    /// changes nothing.
    @Test func localSubMillisecondDatesAreNotChanges() throws {
        let local = try ExportSample.truth()
        let imported = try ExportCodec.decodeDocument(ExportSample.export().json()).truth
        let result = try TruthImport(imported, into: local)
        #expect(result.added == 0 && result.updated == 0 && !result.settingsChanged)
    }

    @Test func updatesByIDAndNeverDeletes() throws {
        let local = try ExportSample.truth()
        var imported = Truth(habits: [local.habits[0]], settings: local.settings)
        imported.habits[0].name = "Gym (renamed)"
        let extra = Cluster(id: ExportSample.id(2), name: "Evening", colorHex: "#000000")
        imported.clusters = [extra]
        let result = try TruthImport(imported, into: local)
        #expect(result.added == 1 && result.updated == 1)
        #expect(result.changes.habits.map(\.name) == ["Gym (renamed)"])
        #expect(result.merged.habits.count == local.habits.count)
        #expect(result.merged.answers.count == local.answers.count)
        #expect(result.merged.clusters.map(\.id) == [ExportSample.id(1), ExportSample.id(2)])
    }

    @Test func rejectsACycleBetweenImportedAndLocalHabits() throws {
        let local = try ExportSample.truth()
        // Locally Shake gates on Gym; the import makes Gym gate on Shake.
        var gym = local.habits[0]
        gym.dependencies = [Dependency(parentID: local.habits[1].id)]
        let imported = Truth(habits: [gym, local.habits[1]], clusters: local.clusters, settings: local.settings)
        #expect(throws: Dependencies.ValidationError.self) { try TruthImport(imported, into: local) }
    }

    @Test func rejectsAnImportNamingUnknownHabits() throws {
        let local = try ExportSample.truth()
        let answer = local.answers[0]
        let stray = Answer(
            id: answer.id, questionID: answer.questionID, habitID: ExportSample.id(99), covers: answer.covers,
            value: answer.value,
            answeredAt: answer.answeredAt, timezone: answer.timezone, channel: answer.channel
        )
        let imported = Truth(habits: [], answers: [stray])
        #expect(throws: Truth.ValidationError.unknownHabit(ExportSample.id(99))) {
            try TruthImport(imported, into: local)
        }
    }

    @Test func simulatorFixturesCarryCreationRevisionsAndImport() throws {
        let run = try Simulator.run(.dependentPair())
        #expect(run.log.habitRevisions.map(\.habit) == run.log.habits)
        let json = try DataExport(truth: run.log, projected: run.projected, exportedAt: ExportSample.noon).json()
        let result = try TruthImport(ExportCodec.decodeDocument(json).truth, into: Truth(habits: []))
        #expect(result.merged.answers.count == run.log.answers.count)
    }
}
