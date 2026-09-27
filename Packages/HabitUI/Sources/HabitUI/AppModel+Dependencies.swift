import Foundation
import HabitCore

/// A dependency the editor refuses because it would close a loop (DESIGN.md §4.5).
public struct DependencyCycleError: LocalizedError, Equatable {
    /// Habit names along the loop, starting and ending at the edited habit; each needs the next.
    public let names: [String]

    public var errorDescription: String? {
        guard names.count > 2, let first = names.first else {
            return "A habit can't depend on itself."
        }
        let rest = names.dropFirst().dropLast().map { "\($0), which needs" }.joined(separator: " ")
        return "\(first) can't depend on \(names[1]): that would make a loop (\(first) would need \(rest) \(first))."
    }
}

/// Dependencies and clusters (DESIGN.md §4.5, §5.1 screen 3). Parents are always read through
/// `gateParentIDs`; `allParentIDs` is only for cycle checks.
public extension AppModel {
    // MARK: Dependencies

    /// Throws `DependencyCycleError` if `draft` depending on `parentID` would close a loop. The editor
    /// calls this before adding the edge, so it can refuse with a message instead of failing on save.
    func checkDependency(on parentID: UUID, for draft: Habit) throws {
        var habits = truth.habits.filter { $0.id != draft.id }
        habits.append(draft)
        if let loop = Dependencies.cycle(ifAdding: parentID, to: draft.id, in: habits) {
            throw DependencyCycleError(names: loop.map { name(of: $0, in: habits) })
        }
    }

    /// Habits `draft` may pick as parents: every other unarchived habit, by creation order. Picking one
    /// that closes a loop is refused by `checkDependency`, not hidden, so the user learns why.
    func parentCandidates(for draft: Habit) -> [Habit] {
        activeHabits.filter { $0.id != draft.id }
    }

    /// The habits that gate `habitID` (§4.5).
    func gateParents(of habitID: UUID) -> [Habit] {
        (habit(habitID)?.gateParentIDs ?? []).compactMap(habit)
    }

    /// Unarchived habits gated by `habitID`.
    func gatedChildren(of habitID: UUID) -> [Habit] {
        activeHabits.filter { $0.gateParentIDs.contains(habitID) }
    }

    /// Names of the parents in a gated question's context line, in the context's order.
    func parentNames(for question: Question) -> [String] {
        (question.parentContext?.parentIDs ?? []).compactMap { habit($0)?.name }
    }

    /// Maps a cycle from `Dependencies.validate` to the editor's message.
    /// `habits` name the cycle's members: the current habits unless the action adds some (an import).
    internal func describingCycles<Value>(in habits: [Habit]? = nil, _ action: () throws -> Value) throws -> Value {
        do {
            return try action()
        } catch let Dependencies.ValidationError.cycle(ids) {
            // Each ID is a parent of the one before it, so the loop reads forward as "needs".
            throw DependencyCycleError(names: (ids + ids.prefix(1)).map { name(of: $0, in: habits ?? truth.habits) })
        }
    }

    private func name(of id: UUID, in habits: [Habit]) -> String {
        habits.first { $0.id == id }?.name ?? "Unknown habit"
    }

    // MARK: Clusters

    /// Clusters by name.
    var clusters: [Cluster] {
        truth.clusters.sorted { ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString) }
    }

    func cluster(_ id: UUID?) -> Cluster? {
        id.flatMap { id in truth.clusters.first { $0.id == id } }
    }

    /// Creates or renames a cluster.
    func save(_ cluster: Cluster) throws {
        try store.save(cluster, at: clock.now())
        if let index = truth.clusters.firstIndex(where: { $0.id == cluster.id }) {
            truth.clusters[index] = cluster
        } else {
            truth.clusters.append(cluster)
        }
        try refresh()
    }

    /// A new, unsaved cluster.
    func newClusterDraft() -> Cluster {
        Cluster(name: "", colorHex: HabitPalette.colors[truth.clusters.count % HabitPalette.colors.count])
    }

    /// Active habits grouped for the Today list: clusters by name (empty ones left out), then habits in no
    /// cluster under a nil cluster.
    var habitsByCluster: [(cluster: Cluster?, habits: [Habit])] {
        let habits = activeHabits
        let grouped: [(cluster: Cluster?, habits: [Habit])] = clusters.map { cluster in
            (cluster, habits.filter { $0.clusterID == cluster.id })
        }
        let loose = habits.filter { cluster($0.clusterID) == nil }
        return (grouped + [(nil, loose)]).filter { !$0.habits.isEmpty }
    }
}
