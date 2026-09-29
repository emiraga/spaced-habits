import Foundation
import HabitCore
import HabitStore

/// Archiving, deleting and ordering habits and clusters, and undoing an answer (DESIGN.md §5.1, §5.2, §10).
public extension AppModel {
    /// Deletes the last answer and the pause its "Delay…" created, on every device. The question is still
    /// logged and unanswered, so the same card comes back (`reusableQuestion`).
    func undoLastAnswer() throws {
        guard let last = lastAnswered else { return }
        try store.delete([.answer(last.answerID)] + (last.pauseID.map { [.pause($0)] } ?? []), at: clock.now())
        truth.answers.removeAll { $0.id == last.answerID }
        truth.pauses.removeAll { $0.id == last.pauseID }
        lastAnswered = nil
        try refresh()
    }

    /// The undo offer expired.
    func dismissUndo() {
        lastAnswered = nil
    }

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

/// What answering a card wrote, so it can be undone.
public struct AnsweredCard: Equatable, Sendable {
    public let habitID: UUID
    let answerID: UUID
    /// The pause a "Delay…" answer created.
    let pauseID: UUID?
}
