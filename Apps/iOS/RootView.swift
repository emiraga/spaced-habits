import HabitUI
import os
import SwiftUI

/// Today is the root (DESIGN.md §5.1); detail pushes, editor and settings are sheets. Widget taps open
/// `DeepLink`s (§6).
struct RootView: View {
    @State private var path: [UUID] = []
    private let logger = Logger(subsystem: "ga.emira.spacedhabits", category: "app")

    var body: some View {
        NavigationStack(path: $path) {
            TodayView()
                .navigationDestination(for: UUID.self) { HabitDetailView(habitID: $0) }
        }
        .onOpenURL { url in
            switch DeepLink(url: url) {
            case .today: path = []
            case let .habit(id): path = [id]
            case nil: logger.error("Unknown URL \(url, privacy: .public)")
            }
        }
    }
}
