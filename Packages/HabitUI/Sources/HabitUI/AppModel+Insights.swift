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
