import Foundation
import HabitCore
import SwiftData

/// A record to delete (DESIGN.md §10).
public enum TruthDeletionTarget: Sendable, Hashable {
    /// Takes along its revisions, questions, answers, Health observations and the pauses of no other habit,
    /// and leaves shared pauses and its children's dependencies (`Truth.removing`).
    case habit(UUID)
    /// Its habits are in no cluster.
    case cluster(UUID)
    case answer(UUID)
    case pause(UUID)

    var kind: TruthKind {
        switch self {
        case .habit: .habit
        case .cluster: .cluster
        case .answer: .answer
        case .pause: .pause
        }
    }

    var id: UUID {
        switch self {
        case let .habit(id), let .cluster(id), let .answer(id), let .pause(id): id
        }
    }
}

public extension TruthStore {
    /// Writes a deletion record per target, in one save. A deletion is a write like any other (last writer
    /// wins, §10): every device that loads it removes the rows written at or before it, so it syncs through
    /// CloudKit and the watch bridge, and a later write (a JSON import) brings the record back.
    func delete(_ targets: [TruthDeletionTarget], at date: Date) throws {
        for target in targets {
            try upsert(.deletion, id: target.id, TruthDeletion(kind: target.kind.rawValue), at: date, save: false)
        }
        try commit()
    }
}

extension TruthStore {
    /// Removes deleted rows and `cascaded` ones (records of a deleted habit) from the store. Not reported
    /// to `onChange`: every device applies the deletion records itself.
    func purgeDeleted(_ rows: [TruthRecord], deletions: Deletions, cascaded: Set<TruthChange.Key>) throws {
        var purged = false
        for row in rows where deletions.deletes(row) || cascaded.contains(TruthChange.Key(kind: row.kind, id: row.id)) {
            context.delete(row)
            purged = true
        }
        if purged {
            try context.save()
        }
    }

    /// The `(kind, id)` of every record in `truth` except settings.
    static func keys(of truth: Truth) -> Set<TruthChange.Key> {
        func keys(_ kind: TruthKind, _ ids: [UUID]) -> [TruthChange.Key] {
            ids.map { TruthChange.Key(kind: kind.rawValue, id: $0) }
        }
        return Set(
            keys(.habit, truth.habits.map(\.id)) + keys(.cluster, truth.clusters.map(\.id))
                + keys(.habitRevision, truth.habitRevisions.map(\.id)) + keys(.question, truth.questions.map(\.id))
                + keys(.answer, truth.answers.map(\.id)) + keys(.pause, truth.pauses.map(\.id))
                + keys(.healthObservation, truth.healthObservations.map(\.id))
        )
    }
}

/// The deletion records in the store, and which rows they delete.
struct Deletions {
    /// The latest deletion of each `(kind, id)`.
    private let dates: [TruthChange.Key: Date]

    static let deletableKinds: Set<TruthKind> = [.habit, .cluster, .answer, .pause]

    init(rows: [TruthRecord], decoder: JSONDecoder) throws {
        var dates: [TruthChange.Key: Date] = [:]
        for row in rows where row.kind == TruthKind.deletion.rawValue {
            let key = try TruthChange.Key(kind: decoder.decode(TruthDeletion.self, from: row.payload).kind, id: row.id)
            dates[key] = max(dates[key] ?? .distantPast, row.updatedAt)
        }
        self.dates = dates
    }

    /// Whether `row` was written at or before its record's deletion.
    func deletes(_ row: TruthRecord) -> Bool {
        dates[TruthChange.Key(kind: row.kind, id: row.id)].map { row.updatedAt <= $0 } ?? false
    }

    /// Deleted habits that no later write brought back into `truth`.
    func habitIDs(in truth: Truth) -> Set<UUID> {
        ids(of: .habit).subtracting(truth.habits.map(\.id))
    }

    /// Deleted clusters that no later write brought back into `truth`.
    func clusterIDs(in truth: Truth) -> Set<UUID> {
        ids(of: .cluster).subtracting(truth.clusters.map(\.id))
    }

    private func ids(of kind: TruthKind) -> Set<UUID> {
        Set(dates.keys.filter { $0.kind == kind.rawValue }.map(\.id))
    }

    /// Accepts a deletion payload naming a kind that can be deleted.
    static func validate(_ payload: Data, decoder: JSONDecoder) throws {
        let kind = try decoder.decode(TruthDeletion.self, from: payload).kind
        guard let deleted = TruthKind(rawValue: kind), deletableKinds.contains(deleted) else {
            throw StoreError.unknownKind(kind)
        }
    }
}
