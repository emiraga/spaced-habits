import HabitCore
import HabitUI
import SwiftUI

extension View {
    /// Asks before deleting `habit` and its history on every device (DESIGN.md §10); `onDeleted` runs after
    /// a successful delete. Setting `habit` presents the dialog.
    func confirmingDeletion(of habit: Binding<Habit?>, onDeleted: @escaping () -> Void = {}) -> some View {
        modifier(DeleteHabitConfirmation(habit: habit, onDeleted: onDeleted))
    }
}

private struct DeleteHabitConfirmation: ViewModifier {
    @Binding var habit: Habit?
    let onDeleted: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(ErrorPresenter.self) private var errors

    func body(content: Content) -> some View {
        content.confirmationDialog(
            habit.map { String(localized: "Delete “\($0.name)”?") } ?? "",
            isPresented: Binding(get: { habit != nil }, set: {
                if !$0 {
                    habit = nil
                }
            }),
            titleVisibility: .visible,
            presenting: habit
        ) { habit in
            Button("Delete habit", role: .destructive) {
                if errors.attempt({ try model.delete(habit.id) }) {
                    onDeleted()
                }
            }
        } message: { _ in
            Text("Its history is deleted on all your devices. To keep it, archive the habit instead.")
        }
    }
}

/// Settings → Archived habits: restore or delete (DESIGN.md §5.1).
struct ArchivedHabitsView: View {
    @Environment(AppModel.self) private var model
    @Environment(ErrorPresenter.self) private var errors
    @State private var deleting: Habit?

    var body: some View {
        List(model.archivedHabits) { habit in
            HStack {
                VStack(alignment: .leading) {
                    Text(habit.displayName)
                    if let archivedAt = habit.archivedAt {
                        Text("Archived \(archivedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Restore") { restore(habit) }
                    .buttonStyle(.borderless)
            }
            .swipeActions {
                Button("Delete", role: .destructive) { deleting = habit }
            }
        }
        .overlay {
            if model.archivedHabits.isEmpty {
                ContentUnavailableView("No archived habits", systemImage: "archivebox")
            }
        }
        .navigationTitle("Archived habits")
        .confirmingDeletion(of: $deleting)
    }

    private func restore(_ habit: Habit) {
        withAnimation { _ = errors.attempt { try model.restore(habit.id) } }
    }
}
