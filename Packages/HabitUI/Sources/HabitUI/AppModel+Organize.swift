import Foundation
import HabitCore
import HabitStore

/// Archiving, deleting and ordering habits and clusters (DESIGN.md §5.1, §10).
public extension AppModel {
    /// Archived habits, most recently archived first (Settings → Archived habits).
    var archivedHabits: [Habit] {
        truth.habits.filter(\.isArchived).sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
    }

    /// Hides the habit from Today, the planner and the watch; its history is kept.
    func archive(_ habitID: UUID) throws {
        guard var habit = habit(habitID) else { return }
        habit.archivedAt = clock.now()
        try save(habit)
    }

    func restore(_ habitID: UUID) throws {
        guard var habit = habit(habitID) else { return }
        habit.archivedAt = nil
        try save(habit)
    }

    /// Deletes the habit and its history on every device (`Truth.removing`).
    func delete(_ habitID: UUID) throws {
        try store.delete([.habit(habitID)], at: clock.now())
        truth = truth.removing(habits: [habitID], clusters: [])
        try refresh()
    }

    /// Deletes the cluster on every device; its habits are in no cluster (`Truth.removing`).
    func deleteCluster(_ clusterID: UUID) throws {
        try store.delete([.cluster(clusterID)], at: clock.now())
        truth = truth.removing(habits: [], clusters: [clusterID])
        try refresh()
    }

    /// Drag and drop on Today: `habitID` takes `targetID`'s place in their group. A drop on another group
    /// does nothing.
    func move(habit habitID: UUID, to targetID: UUID) throws {
        guard let group = habitsByCluster.map(\.habits).first(where: { $0.contains { $0.id == habitID } }),
              let order = ListOrder.moving(habitID, to: targetID, in: group)
        else { return }
        try store.save(reordered: order, at: clock.now())
        try replace(\.habits, with: order)
    }

    /// Drag and drop on Today: cluster `clusterID` takes `targetID`'s place among the groups.
    func move(cluster clusterID: UUID, to targetID: UUID) throws {
        guard let order = ListOrder.moving(clusterID, to: targetID, in: clusters) else { return }
        try store.save(reordered: order, at: clock.now())
        try replace(\.clusters, with: order)
    }

    /// Replaces the stored values of `items` in memory and re-plans.
    private func replace<Item: Identifiable<UUID>>(
        _ keyPath: WritableKeyPath<Truth, [Item]>,
        with items: [Item]
    ) throws {
        for item in items {
            if let index = truth[keyPath: keyPath].firstIndex(where: { $0.id == item.id }) {
                truth[keyPath: keyPath][index] = item
            }
        }
        try refresh()
    }
}

/// Renumbering a list after a move.
enum ListOrder {
    /// The items whose `listOrder` changed when `moved` takes `target`'s place in `items` (after it when
    /// moving down, before it when moving up) and all are renumbered from 0. Nil when either is missing or
    /// they are the same item.
    static func moving<Item: ListOrdered>(_ moved: UUID, to target: UUID, in items: [Item]) -> [Item]? {
        guard moved != target, let source = items.firstIndex(where: { $0.id == moved }),
              let destination = items.firstIndex(where: { $0.id == target })
        else { return nil }
        var items = items
        items.insert(items.remove(at: source), at: destination)
        return items.enumerated().compactMap { index, item in
            guard item.listOrder != index else { return nil }
            var item = item
            item.listOrder = index
            return item
        }
    }
}

protocol ListOrdered: Identifiable<UUID> {
    var listOrder: Int? { get set }
}

extension Habit: ListOrdered {}
extension Cluster: ListOrdered {}
