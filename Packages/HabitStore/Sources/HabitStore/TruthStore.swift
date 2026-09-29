import Foundation
import HabitCore
import SwiftData

/// Where the SwiftData store lives.
public enum StoreLocation: Sendable {
    /// The App Group container shared with the widget extension (production). The app and the watch app
    /// sync it with CloudKit; the widget extension doesn't (`syncs: false`): SwiftData always records
    /// persistent history, so the app's CloudKit mirror exports the extension's writes on its next run.
    case appGroup(syncs: Bool)
    /// A store file at a URL (tests that relaunch).
    case file(URL)
    /// Nothing on disk (tests, previews).
    case inMemory
}

public enum StoreError: Error, Equatable {
    case appGroupDefaultsUnavailable(String)
    /// A merged change names a collection this version doesn't know (§7).
    case unknownKind(String)
}

/// Builds the `ModelContainer` (DESIGN.md §10).
public enum StoreContainer {
    public static let appGroupID = "group.ga.emira.spacedhabits"
    public static let cloudKitContainerID = "iCloud.ga.emira.spacedhabits"

    /// The App Group's defaults, shared by the app and its widget extension (the debug day offset, §6).
    public static func sharedDefaults() throws -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            throw StoreError.appGroupDefaultsUnavailable(appGroupID)
        }
        return defaults
    }

    static let schema = Schema([TruthRecord.self])

    public static func make(_ location: StoreLocation) throws -> ModelContainer {
        let configuration = switch location {
        case let .appGroup(syncs):
            ModelConfiguration(
                schema: schema, groupContainer: .identifier(appGroupID),
                cloudKitDatabase: syncs ? .private(cloudKitContainerID) : .none
            )
        case let .file(url):
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        case .inMemory:
            // A unique name keeps in-memory containers in one process from sharing a store.
            ModelConfiguration(
                UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, groupContainer: .none,
                cloudKitDatabase: .none
            )
        }
        return try ModelContainer(for: schema, configurations: configuration)
    }
}

/// Reads and writes `Truth` (DESIGN.md §3.2). Every write validates the value first and saves immediately.
@MainActor
public final class TruthStore {
    /// Settings are one logical record; every device writes it under this ID.
    static let settingsID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))

    /// Retained: a context whose container is released traps on the next fetch.
    private let container: ModelContainer
    let context: ModelContext
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    let decoder = JSONDecoder()

    public init(container: ModelContainer) {
        self.container = container
        context = container.mainContext
    }

    // MARK: Reading

    /// All truth, each collection ordered by last write then ID. Missing settings are `Settings.default`.
    /// Deleted records, and what refers to a deleted habit or cluster, are left out and removed from the
    /// store (`purgeDeleted`). Values naming a habit or cluster that hasn't synced yet are held back
    /// (`Truth.withoutPendingReferences`).
    public func load() throws -> Truth {
        let rows = try context.fetch(FetchDescriptor<TruthRecord>())
        let deletions = try Deletions(rows: rows, decoder: decoder)
        let truth = try decode(latestRows(rows.filter { !deletions.deletes($0) }))
        let kept = truth.removing(habits: deletions.habitIDs(in: truth), clusters: deletions.clusterIDs(in: truth))
        try purgeDeleted(rows, deletions: deletions, cascaded: Self.keys(of: truth).subtracting(Self.keys(of: kept)))
        return kept.withoutPendingReferences()
    }

    /// The latest row per `(kind, id)`, by kind.
    private func latestRows(_ rows: [TruthRecord]) -> [String: [UUID: TruthRecord]] {
        var latest: [String: [UUID: TruthRecord]] = [:]
        for row in rows where latest[row.kind]?[row.id].map({ $0.updatedAt < row.updatedAt }) ?? true {
            latest[row.kind, default: [:]][row.id] = row
        }
        return latest
    }

    private func decode(_ latest: [String: [UUID: TruthRecord]]) throws -> Truth {
        func values<Value: Decodable>(_ kind: TruthKind, as _: Value.Type = Value.self) throws -> [Value] {
            let ordered = (latest[kind.rawValue] ?? [:]).values.sorted {
                ($0.updatedAt, $0.id.uuidString) < ($1.updatedAt, $1.id.uuidString)
            }
            return try ordered.map { try decoder.decode(Value.self, from: $0.payload) }
        }
        return try Truth(
            habits: values(.habit),
            clusters: values(.cluster),
            habitRevisions: values(.habitRevision),
            questions: values(.question),
            answers: values(.answer),
            pauses: values(.pause),
            healthObservations: values(.healthObservation),
            settings: values(.settings, as: Settings.self).last ?? .default
        )
    }

    // MARK: Writing

    /// Creates or edits a habit and appends the `HabitRevision` snapshot (§3.2), which it returns.
    @discardableResult
    public func save(_ habit: Habit, editedAt: Date) throws -> HabitRevision {
        try habit.validate()
        try upsert(.habit, id: habit.id, habit, at: editedAt, save: false)
        let revision = HabitRevision(habit: habit, editedAt: editedAt)
        try upsert(.habitRevision, id: revision.id, revision, at: editedAt)
        return revision
    }

    /// Saves habits moved in the Today list (§5.1), in one save and without revisions: order isn't history.
    public func save(reordered habits: [Habit], at date: Date) throws {
        try habits.forEach { try $0.validate() }
        try upsertAll(.habit, habits, at: date)
        try commit()
    }

    /// Saves clusters moved in the Today list (§5.1), in one save.
    public func save(reordered clusters: [Cluster], at date: Date) throws {
        try clusters.forEach { try $0.validate() }
        try upsertAll(.cluster, clusters, at: date)
        try commit()
    }

    /// Creates or renames a cluster (last writer wins, §10).
    public func save(_ cluster: Cluster, at date: Date) throws {
        try cluster.validate()
        try upsert(.cluster, id: cluster.id, cluster, at: date)
    }

    /// Logs a presented question, or updates it (e.g. `dismissedAt` on "Later").
    public func save(_ question: Question, at date: Date) throws {
        try question.validate()
        try upsert(.question, id: question.id, question, at: date)
    }

    public func append(_ answer: Answer) throws {
        try answer.validate()
        try upsert(.answer, id: answer.id, answer, at: answer.answeredAt)
    }

    public func save(_ pause: PauseEvent, at date: Date) throws {
        try pause.validate()
        try upsert(.pause, id: pause.id, pause, at: date)
    }

    public func save(_ settings: Settings, at date: Date) throws {
        try settings.validate()
        try upsert(.settings, id: Self.settingsID, settings, at: date)
    }

    /// Writes the records of a JSON import as they are (§11), in one save: no new revisions, IDs and values
    /// kept. `date` is the write time, so an imported record also wins on other devices. `changes` must be
    /// validated first (`TruthImport`); its settings are written when `includingSettings`.
    public func save(imported changes: Truth, includingSettings: Bool, at date: Date) throws {
        try upsertAll(.habit, changes.habits, at: date)
        try upsertAll(.cluster, changes.clusters, at: date)
        try upsertAll(.habitRevision, changes.habitRevisions, at: date)
        try upsertAll(.question, changes.questions, at: date)
        try upsertAll(.answer, changes.answers, at: date)
        try upsertAll(.pause, changes.pauses, at: date)
        try upsertAll(.healthObservation, changes.healthObservations, at: date)
        if includingSettings {
            try upsert(.settings, id: Self.settingsID, changes.settings, at: date, save: false)
        }
        try commit()
    }

    // MARK: Changes between devices

    /// Every local write, as the watch bridge sends it to the other device (§7): once per save, with all
    /// its changes (an import saves thousands at once). Not called by `merge`, so merged changes aren't
    /// echoed back.
    public var onChange: (@MainActor ([TruthChange]) -> Void)?
    /// Written but not yet saved; reported once the context saves.
    private var unsaved: [TruthChange] = []

    /// Every stored record, latest per `(kind, id)`: what a newly installed watch is sent (§7).
    public func allChanges() throws -> [TruthChange] {
        var latest: [TruthChange.Key: TruthChange] = [:]
        for row in try context.fetch(FetchDescriptor<TruthRecord>()) {
            let change = TruthChange(kind: row.kind, id: row.id, payload: row.payload, updatedAt: row.updatedAt)
            if latest[change.key].map({ $0.updatedAt < change.updatedAt }) ?? true {
                latest[change.key] = change
            }
        }
        return latest.values.sorted { ($0.updatedAt, $0.id.uuidString) < ($1.updatedAt, $1.id.uuidString) }
    }

    /// Applies another device's writes, latest `updatedAt` wins per `(kind, id)`, so a change delivered
    /// twice (WatchConnectivity and CloudKit) or late is harmless. Each value is decoded and validated like
    /// a local write; references between values aren't checked, since changes can arrive out of order.
    /// Returns whether anything changed.
    @discardableResult
    public func merge(_ changes: [TruthChange]) throws -> Bool {
        var changed = false
        for change in changes {
            guard let kind = TruthKind(rawValue: change.kind) else { throw StoreError.unknownKind(change.kind) }
            try validate(change.payload, as: kind)
            let rawKind = change.kind
            let id = change.id
            let existing = try context.fetch(FetchDescriptor<TruthRecord>(
                predicate: #Predicate { $0.kind == rawKind && $0.id == id }
            ))
            if existing.contains(where: { $0.updatedAt >= change.updatedAt }) {
                continue
            }
            if existing.isEmpty {
                context.insert(TruthRecord(kind: kind, id: id, payload: change.payload, updatedAt: change.updatedAt))
            }
            for row in existing {
                row.payload = change.payload
                row.updatedAt = change.updatedAt
            }
            changed = true
        }
        if changed {
            try context.save()
        }
        return changed
    }

    private func validate(_ payload: Data, as kind: TruthKind) throws {
        switch kind {
        case .habit: try decoder.decode(Habit.self, from: payload).validate()
        case .habitRevision: try decoder.decode(HabitRevision.self, from: payload).habit.validate()
        case .cluster: try decoder.decode(Cluster.self, from: payload).validate()
        case .question: try decoder.decode(Question.self, from: payload).validate()
        case .answer: try decoder.decode(Answer.self, from: payload).validate()
        case .pause: try decoder.decode(PauseEvent.self, from: payload).validate()
        case .healthObservation: _ = try decoder.decode(HealthObservation.self, from: payload)
        case .settings: try decoder.decode(Settings.self, from: payload).validate()
        case .deletion: try Deletions.validate(payload, decoder: decoder)
        }
    }

    /// Deletes all truth. Debug only (Settings → Debug → Erase all data).
    public func eraseAll() throws {
        try context.delete(model: TruthRecord.self)
        try context.save()
    }

    func upsert(_ kind: TruthKind, id: UUID, _ value: some Encodable, at date: Date, save: Bool = true) throws {
        let payload = try encoder.encode(value)
        let rawKind = kind.rawValue
        let existing = try context.fetch(FetchDescriptor<TruthRecord>(
            predicate: #Predicate { $0.kind == rawKind && $0.id == id }
        ))
        if existing.isEmpty {
            context.insert(TruthRecord(kind: kind, id: id, payload: payload, updatedAt: date))
        }
        for row in existing {
            row.payload = payload
            row.updatedAt = date
        }
        unsaved.append(TruthChange(kind: rawKind, id: id, payload: payload, updatedAt: date))
        if save {
            try commit()
        }
    }

    /// Writes without saving.
    private func upsertAll(_ kind: TruthKind, _ values: [some Encodable & Identifiable<UUID>], at date: Date) throws {
        for value in values {
            try upsert(kind, id: value.id, value, at: date, save: false)
        }
    }

    /// Saves the context and reports what was written.
    func commit() throws {
        let saved = unsaved
        unsaved = []
        try context.save()
        if !saved.isEmpty {
            onChange?(saved)
        }
    }
}
