import HabitUI
import os
import SwiftUI

/// Today is the root (DESIGN.md §5.1); habit detail (a habit's `UUID`) and Insights push, editor and
/// settings are sheets. Widget taps open `DeepLink`s (§6).
struct RootView: View {
    @State private var path = NavigationPath()
    private let logger = Logger(subsystem: "ga.emira.spacedhabits", category: "app")

    var body: some View {
        NavigationStack(path: $path) {
            TodayView()
                .navigationDestination(for: UUID.self) { HabitDetailView(habitID: $0) }
                .navigationDestination(for: InsightsDestination.self) { _ in InsightsView() }
        }
        .onOpenURL { url in
            switch DeepLink(url: url) {
            case .today: path = NavigationPath()
            case let .habit(id): path = NavigationPath([id])
            case .insights: path = NavigationPath([InsightsDestination()])
            case nil: logger.error("Unknown URL \(url, privacy: .public)")
            }
        }
    }
}

/// The Insights screen's navigation value.
struct InsightsDestination: Hashable {}
