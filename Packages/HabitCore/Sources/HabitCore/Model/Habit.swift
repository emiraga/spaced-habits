import Foundation

/// A habit definition (DESIGN.md §3.3). Truth: synced, edited in place (last writer wins).
public struct Habit: Identifiable, Codable, Sendable, Hashable {
    public static let defaultTargetAdherence = 0.8
    public static let defaultMaxRecallGapDays = 7

    public let id: UUID
    public var name: String
    public var emoji: String?
    public var colorHex: String
    public var createdAt: Date
    /// The habit day it was created on, fixed at creation by `DayCalendar` (§3.1). First day of its history.
    public var createdDay: DayKey
    public var archivedAt: Date?
    public var kind: HabitKind
    /// Weights question priority (§4.4).
    public var importance: Importance
    /// 0...1. Below this mean the scheduler asks daily (§4.2 rule 2).
    public var targetAdherence: Double
    /// ≥ 1. Questions never cover more than this many days (§4.3).
    public var maxRecallGapDays: Int
    /// Persisted and remembered by the vacation sheet (§4.6).
    public var vacationBehavior: VacationBehavior
    /// Parent edges. Parent IDs (all modes) must form a DAG; see `Dependencies.validate`.
    public var dependencies: [Dependency]
    public var clusterID: UUID?
    public var healthBinding: HealthBinding?
    public var notes: String?

    public enum ValidationError: Error, Equatable {
        case emptyName
        case targetAdherenceOutOfRange(Double)
        case maxRecallGapDaysOutOfRange(Int)
        case dependsOnItself
        case duplicateParent(UUID)
    }

    public init(
        id: UUID = UUID(),
        name: String,
        emoji: String? = nil,
        colorHex: String,
        createdAt: Date,
        createdDay: DayKey,
        archivedAt: Date? = nil,
        kind: HabitKind = .boolean,
        importance: Importance = .normal,
        targetAdherence: Double = Habit.defaultTargetAdherence,
        maxRecallGapDays: Int = Habit.defaultMaxRecallGapDays,
        vacationBehavior: VacationBehavior = .pause,
        dependencies: [Dependency] = [],
        clusterID: UUID? = nil,
        healthBinding: HealthBinding? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.createdDay = createdDay
        self.archivedAt = archivedAt
        self.kind = kind
        self.importance = importance
        self.targetAdherence = targetAdherence
        self.maxRecallGapDays = maxRecallGapDays
        self.vacationBehavior = vacationBehavior
        self.dependencies = dependencies
        self.clusterID = clusterID
        self.healthBinding = healthBinding
        self.notes = notes
    }

    /// Parents that gate this habit (§4.5). Planner, projection and UI read parents only through this.
    public var gateParentIDs: [UUID] {
        dependencies.filter { $0.mode == .gate }.map(\.parentID)
    }

    /// All parents regardless of mode. For DAG validation only.
    public var allParentIDs: [UUID] {
        dependencies.map(\.parentID)
    }

    public var isArchived: Bool {
        archivedAt != nil
    }

    /// Checks the invariants that don't need other habits. Cycles are checked by `Dependencies.validate`.
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyName
        }
        guard (0 ... 1).contains(targetAdherence) else {
            throw ValidationError.targetAdherenceOutOfRange(targetAdherence)
        }
        guard maxRecallGapDays >= 1 else {
            throw ValidationError.maxRecallGapDaysOutOfRange(maxRecallGapDays)
        }
        var seen = Set<UUID>()
        for parentID in allParentIDs {
            guard parentID != id else { throw ValidationError.dependsOnItself }
            guard seen.insert(parentID).inserted else { throw ValidationError.duplicateParent(parentID) }
        }
    }
}

/// v1 habits are boolean per day (§1.2). `quantity(unit:target:)` is reserved.
public enum HabitKind: String, Codable, Sendable, Hashable {
    case boolean
}

public enum Importance: Int, Codable, Sendable, Hashable, CaseIterable {
    case low = 1
    case normal = 2
    case high = 3
}

public enum VacationBehavior: String, Codable, Sendable, Hashable {
    case pause
    case keep
}

/// One edge from a habit to a parent habit (§4.5).
public struct Dependency: Codable, Sendable, Hashable {
    public let parentID: UUID
    public var mode: DependencyMode

    public init(parentID: UUID, mode: DependencyMode = .gate) {
        self.parentID = parentID
        self.mode = mode
    }
}

/// v1 creates `.gate` only. `.sequence` is reserved for habit stacking and must round-trip through
/// store, sync and export without the planner or projection acting on it.
public enum DependencyMode: String, Codable, Sendable, Hashable {
    /// Child is measured as P(child | parent) and not asked while the parent fails.
    case gate
    /// Child merely follows the parent in a routine: no gating, no conditional metric.
    case sequence
}

/// Optional grouping ("Morning routine").
public struct Cluster: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public var colorHex: String

    public init(id: UUID = UUID(), name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

/// Health data that auto-completes a habit day (§9). Read-only.
public enum HealthBinding: Codable, Sendable, Hashable {
    case workout(minMinutes: Int)
    case steps(min: Int)
    case sleep(minHours: Double)
    case mindfulMinutes(min: Int)
}
