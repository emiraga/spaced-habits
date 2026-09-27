import Foundation

/// A JSON import merged into local truth (DESIGN.md §11): by UUID, never deleting. An imported record that
/// is new, or differs from the local one with its ID, replaces it; settings are replaced when they differ.
/// Both sides are compared at export precision, so importing a device's own export changes nothing.
public struct TruthImport: Sendable {
    /// Local truth with the import applied; validated, dependency DAG included.
    public let merged: Truth
    /// The imported records to write: new or changed ones. `settings` are the imported settings.
    public let changes: Truth
    public let settingsChanged: Bool
    /// Records whose ID wasn't known locally.
    public let added: Int
    /// Records that replaced a different local version.
    public let updated: Int

    /// Throws when the merged result is invalid: a bad value, a reference to a habit or cluster neither side
    /// has, or a dependency cycle between imported and local habits (`Dependencies.ValidationError.cycle`).
    /// An import may name local records, so only the merged result is validated.
    public init(_ imported: Truth, into local: Truth) throws {
        let local = try ExportCodec.roundTripped(local)
        var merged = local
        var changes = Truth(habits: [], settings: imported.settings)
        var added = 0
        var updated = 0
        func merge<Value: Identifiable & Hashable>(
            _ keyPath: WritableKeyPath<Truth, [Value]>
        ) where Value.ID == UUID {
            var index = Dictionary(merged[keyPath: keyPath].enumerated().map { ($1.id, $0) }, uniquingKeysWith: { $1 })
            for value in imported[keyPath: keyPath] {
                if let position = index[value.id] {
                    guard merged[keyPath: keyPath][position] != value else { continue }
                    merged[keyPath: keyPath][position] = value
                    updated += 1
                } else {
                    index[value.id] = merged[keyPath: keyPath].count
                    merged[keyPath: keyPath].append(value)
                    added += 1
                }
                changes[keyPath: keyPath].append(value)
            }
        }
        merge(\.habits)
        merge(\.clusters)
        merge(\.habitRevisions)
        merge(\.questions)
        merge(\.answers)
        merge(\.pauses)
        merge(\.healthObservations)
        settingsChanged = local.settings != imported.settings
        merged.settings = imported.settings
        try merged.validate()
        self.merged = merged
        self.changes = changes
        self.added = added
        self.updated = updated
    }
}
