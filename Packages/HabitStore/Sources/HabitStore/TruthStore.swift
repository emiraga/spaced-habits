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
    private let context: ModelContext
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    private let decoder = JSONDecoder()

    public init(container: ModelContainer) {
        self.container = container
        context = container.mainContext
    }

    // MARK: Reading

    /// All truth, each collection ordered by last write then ID. Missing settings are `Settings.default`.
    public func load() throws -> Truth {
        let rows = try context.fetch(FetchDescriptor<TruthRecord>())
        var latest: [String: [UUID: TruthRecord]] = [:]
        for row in rows where latest[row.kind]?[row.id].map({ $0.updatedAt < row.updatedAt }) ?? true {
            latest[row.kind, default: [:]][row.id] = row
        }
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

    /// Deletes all truth. Debug only (Settings → Debug → Erase all data).
    public func eraseAll() throws {
        try context.delete(model: TruthRecord.self)
        try context.save()
    }

    private func upsert(_ kind: TruthKind, id: UUID, _ value: some Encodable, at date: Date, save: Bool = true) throws {
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
        if save {
            try context.save()
        }
    }
}
