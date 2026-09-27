import Foundation
import HabitCore

/// What a JSON import wrote (DESIGN.md §11).
public struct ImportSummary: Equatable, Sendable {
    /// Records whose ID wasn't known.
    public let added: Int
    /// Records that replaced a different local version.
    public let updated: Int
    public let settingsChanged: Bool

    public var changedNothing: Bool {
        added == 0 && updated == 0 && !settingsChanged
    }
}

/// Export and import (DESIGN.md §11).
public extension AppModel {
    /// Everything loaded now, for JSON and CSV export. Encoding can run off the main actor.
    func dataExport() -> DataExport {
        DataExport(truth: truth, projected: projected, exportedAt: clock.now())
    }

    /// Merges an export by UUID, never deleting, then re-reads and re-projects (a new session). Throws,
    /// writing nothing, on an unreadable file, an unknown schema version or value, or a dependency cycle.
    @discardableResult
    func importJSON(_ data: Data) throws -> ImportSummary {
        let document = try ExportCodec.decodeDocument(data)
        let habits = truth.habits + document.truth.habits
        let result = try describingCycles(in: habits) { try TruthImport(document.truth, into: truth) }
        try store.save(imported: result.changes, includingSettings: result.settingsChanged, at: clock.now())
        try reload()
        return ImportSummary(added: result.added, updated: result.updated, settingsChanged: result.settingsChanged)
    }
}
