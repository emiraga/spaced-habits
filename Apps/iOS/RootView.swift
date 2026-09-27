import HabitUI
import SwiftUI

/// Today is the root (DESIGN.md §5.1); detail pushes, editor and settings are sheets.
struct RootView: View {
    var body: some View {
        NavigationStack {
            TodayView()
                .navigationDestination(for: UUID.self) { HabitDetailView(habitID: $0) }
        }
    }
}
