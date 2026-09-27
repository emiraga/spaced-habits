import Foundation
import SwiftData

/// Which `Truth` collection a `TruthRecord` belongs to.
enum TruthKind: String, CaseIterable {
    case habit, habitRevision, cluster, question, answer, pause, healthObservation, settings
}

/// One truth value, stored as its `HabitCore` JSON (DESIGN.md §10).
///
/// A single table rather than one `@Model` per type: SwiftData's composite attributes mishandle enums with
/// associated values (`AnswerValue`, `QuestionShape`, `PauseReason`, `HealthBinding`), JSON is already the
/// export format (§11) so one codec maps every type, and `@Model` classes can't share a base class on
/// iOS 17. CloudKit rules: no unique attributes, every property has a default, no relationships.
@Model final class TruthRecord {
    /// `TruthKind` raw value.
    var kind = ""
    /// The value's UUID. Not unique in the store (CloudKit forbids it): `TruthStore` upserts by
    /// `(kind, id)` and, if sync ever yields duplicates, loads the latest `updatedAt`.
    var id = UUID()
    var payload = Data()
    var updatedAt = Date.distantPast

    init(kind: TruthKind, id: UUID, payload: Data, updatedAt: Date) {
        self.kind = kind.rawValue
        self.id = id
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

/// One written `TruthRecord`, as it travels between the phone and the watch (DESIGN.md §7).
public struct TruthChange: Codable, Sendable, Hashable {
    struct Key: Hashable {
        let kind: String
        let id: UUID
    }

    /// `TruthKind` raw value; a `String` so a newer device's kinds decode and are refused by `merge`.
    public let kind: String
    public let id: UUID
    /// The value's `HabitCore` JSON.
    public let payload: Data
    public let updatedAt: Date

    var key: Key {
        Key(kind: kind, id: id)
    }
}
