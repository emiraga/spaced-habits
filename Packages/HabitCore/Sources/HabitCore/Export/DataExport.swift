import Foundation

/// Everything the user can export (DESIGN.md §11), from one snapshot of truth and its projection. A
/// `Sendable` value, so the share sheet can encode it off the main actor.
public struct DataExport: Sendable {
    public let truth: Truth
    public let projected: Projected
    public let exportedAt: Date

    public init(truth: Truth, projected: Projected, exportedAt: Date) {
        self.truth = truth.canonicallyOrdered()
        self.projected = projected
        self.exportedAt = exportedAt
    }

    /// The full truth; `includeProjection` adds the derived `dayRecords`.
    public func json(includeProjection: Bool = false) throws -> Data {
        try ExportCodec.encode(ExportDocument(
            truth: truth, exportedAt: exportedAt, projection: includeProjection ? projected : nil
        ))
    }

    /// The CSV files, zipped (stored, no compression).
    public func csvArchive() throws -> Data {
        try ZipArchive.stored(csvFiles().map { ($0.name, Data($0.contents.utf8)) })
    }

    public func csvFiles() -> [CSVFile] {
        let names = Dictionary(truth.habits.map { ($0.id, $0.name) }, uniquingKeysWith: { $1 })
        var dependencies = CSVTable(["habit_id", "parent_id", "mode"])
        for habit in truth.habits {
            for dependency in habit.dependencies {
                dependencies.append([id(habit.id), id(dependency.parentID), dependency.mode.rawValue])
            }
        }
        return [
            days(names: names).file("days.csv"),
            table(CSVColumns.habit, truth.habits) { [id($0.id)] + CSVColumns.values(of: $0) }.file("habits.csv"),
            table(
                ["revision_id", "habit_id", "edited_at"] + CSVColumns.habit.dropFirst() + ["dependencies"],
                truth.habitRevisions
            ) { revision in
                [id(revision.id), id(revision.habit.id), CSVColumns.date(revision.editedAt)]
                    + CSVColumns.values(of: revision.habit)
                    +
                    [revision.habit.dependencies.map { "\(id($0.parentID)):\($0.mode.rawValue)" }
                        .joined(separator: ";")]
            }.file("habit_revisions.csv"),
            table(CSVColumns.answer, truth.answers, CSVColumns.values).file("answers.csv"),
            table(CSVColumns.question, truth.questions, CSVColumns.values).file("questions.csv"),
            table(CSVColumns.pause, truth.pauses, CSVColumns.values).file("pauses.csv"),
            table(["id", "name", "color_hex"], truth.clusters) { [id($0.id), $0.name, $0.colorHex] }
                .file("clusters.csv"),
            dependencies.file("dependencies.csv"),
            table(["id", "habit_id", "day", "sample_id"], truth.healthObservations) {
                [id($0.id), id($0.habitID), $0.day.description, $0.sampleID]
            }.file("health_observations.csv"),
        ]
    }

    /// One row per habit per day it has existed, every one with a `source` (§13 M10).
    private func days(names: [UUID: String]) -> CSVTable {
        var table = CSVTable([
            "habit_id", "habit_name", "day", "value", "source", "confidence", "conditional_denominator_excluded",
            "question_id",
        ])
        for habit in truth.habits {
            for record in (projected.records[habit.id] ?? [:]).values.sorted(by: { $0.day < $1.day }) {
                table.append([
                    id(habit.id), names[habit.id] ?? "", record.day.description, String(record.value),
                    record.source.rawValue, String(record.confidence),
                    String(record.conditionalDenominatorExcluded), record.questionID.map(id) ?? "",
                ])
            }
        }
        return table
    }

    private func table<Value>(_ header: [String], _ values: [Value], _ row: (Value) -> [String]) -> CSVTable {
        var table = CSVTable(header)
        values.forEach { table.append(row($0)) }
        return table
    }

    private func id(_ id: UUID) -> String {
        id.uuidString
    }
}

/// One file of the CSV export.
public struct CSVFile: Sendable, Hashable {
    public let name: String
    public let contents: String
}

/// RFC 4180 fields: quoted when they hold a comma, quote or line break; `\n` line ends.
struct CSVTable {
    private var lines: [String]

    init(_ header: [String]) {
        lines = [Self.line(header)]
    }

    mutating func append(_ row: [String]) {
        lines.append(Self.line(row))
    }

    func file(_ name: String) -> CSVFile {
        CSVFile(name: name, contents: lines.map { $0 + "\n" }.joined())
    }

    private static func line(_ fields: [String]) -> String {
        fields.map { field in
            field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline })
                ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                : field
        }.joined(separator: ",")
    }
}
