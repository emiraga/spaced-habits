import Foundation
import HabitCore

/// Chart data for habit detail and the Insights screen (DESIGN.md §12), from the current projection.
public extension AppModel {
    func insights(of habit: Habit, filter: AdherenceFilter) -> HabitInsights {
        HabitInsights(habit: habit, projected: projected, pauses: truth.pauses, today: today, filter: filter)
    }

    func overview(filter: AdherenceFilter) -> Overview {
        Overview(truth: truth, projected: projected, today: today, filter: filter)
    }

    /// One entry per cluster with active members, clusters by name.
    func clusterInsights(filter: AdherenceFilter) -> [(cluster: Cluster, insights: ClusterInsights)] {
        habitsByCluster.compactMap { group in
            group.cluster.map { cluster in
                let insights = ClusterInsights(
                    clusterID: cluster.id, members: group.habits, records: projected.records, today: today,
                    filter: filter
                )
                return (cluster, insights)
            }
        }
    }
}

#if DEBUG
    public enum FixtureError: Error, Equatable {
        /// The store has no write for Health observations yet (M8, deferred).
        case healthObservationsUnsupported
    }

    public extension AppModel {
        /// Writes a `Truth` JSON file into the store, as `simulate --json` exports it: the M9 checkpoint
        /// charts a simulated history. Debug only; M10's JSON import is the real path.
        func importFixture(at url: URL) throws {
            let fixture = try JSONDecoder().decode(Truth.self, from: Data(contentsOf: url))
            try fixture.validate()
            guard fixture.healthObservations.isEmpty else { throw FixtureError.healthObservationsUnsupported }
            try store.save(fixture.settings, at: clock.now())
            for cluster in fixture.clusters {
                try store.save(cluster, at: clock.now())
            }
            for habit in fixture.habits {
                try store.save(habit, editedAt: habit.createdAt)
            }
            for question in fixture.questions {
                try store.save(question, at: question.presentedAt ?? question.createdAt)
            }
            for answer in fixture.answers {
                try store.append(answer)
            }
            for pause in fixture.pauses {
                try store.save(pause, at: pause.createdAt)
            }
            try reload()
        }
    }
#endif
