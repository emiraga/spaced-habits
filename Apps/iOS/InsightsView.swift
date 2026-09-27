import HabitCore
import HabitUI
import SwiftUI

/// Insight cards, the overall charts and each cluster's charts (DESIGN.md §5.1 screen 6, §12). A lazy list:
/// sections below the fold are drawn as they scroll in.
struct InsightsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(ChartSettings.includePausedKey) private var includePaused = false

    var body: some View {
        let filter = AdherenceFilter(includingPaused: includePaused)
        let overview = model.overview(filter: filter)
        let habits = model.activeHabits
        List {
            Section {
                Toggle("Include paused days", isOn: $includePaused)
            } footer: {
                Text("When on, paused days count as not done.")
            }
            let cards = InsightCard.cards(overview)
            if !cards.isEmpty {
                Section {
                    ForEach(cards) { card in
                        if let habitID = card.habitID {
                            NavigationLink(value: habitID) {
                                InsightCardView(card: card, habitName: model.habit(habitID)?.name ?? "")
                            }
                        } else {
                            InsightCardView(card: card, habitName: "")
                        }
                    }
                }
            }
            Section("All habits") {
                OverviewCharts(overview: overview, habits: habits)
            }
            ForEach(model.clusterInsights(filter: filter), id: \.cluster.id) { group in
                Section(group.cluster.name) {
                    ClusterCharts(insights: group.insights, habits: model.truth.habits)
                }
            }
        }
        .navigationTitle("Insights")
        .overlay {
            if habits.isEmpty {
                ContentUnavailableView(
                    "No habits yet", systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Insights appear once you've tracked a habit for a week.")
                )
            }
        }
    }
}

/// Shared by Insights and habit detail, so the toggle holds on both.
enum ChartSettings {
    static let includePausedKey = "charts.includePaused"
}
