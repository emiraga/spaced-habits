import HabitCore
import HabitUI
import SwiftUI
import UniformTypeIdentifiers

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

/// A habit row or cluster header being dragged on Today (DESIGN.md §5.1). A private type, declared in
/// `project.yml`, so a row doesn't drop into other apps as text.
struct TodayDrag: Codable, Transferable {
    enum Kind: String, Codable {
        case habit, cluster
    }

    let kind: Kind
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .todayRow)
    }
}

extension UTType {
    static let todayRow = UTType(exportedAs: "ga.emira.spacedhabits.today-row")
}

extension View {
    /// Long-press and drag to move onto another item of the same kind; `onDrop` gets the dragged item's ID.
    func reorderable(_ drag: TodayDrag, onDrop: @escaping (UUID) -> Void) -> some View {
        modifier(Reorderable(drag: drag, onDrop: onDrop))
    }
}

private struct Reorderable: ViewModifier {
    let drag: TodayDrag
    let onDrop: (UUID) -> Void
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .background(targeted ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .draggable(drag)
            .dropDestination(for: TodayDrag.self) { items, _ in
                guard let item = items.first, item.kind == drag.kind, item.id != drag.id else { return false }
                withAnimation { onDrop(item.id) }
                return true
            } isTargeted: { targeted = $0 }
    }
}

/// Long-press actions for a habit on Today (DESIGN.md §5.1); dragging from the press still reorders.
struct HabitMenu: View {
    let habit: Habit
    let onEdit: () -> Void
    let onPause: () -> Void
    let onDelete: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(ErrorPresenter.self) private var errors

    var body: some View {
        DoneTodayButton(habitID: habit.id)
        Button("Edit", systemImage: "pencil", action: onEdit)
        Button("Pause…", systemImage: "pause.circle", action: onPause)
        Button("Archive", systemImage: "archivebox") {
            withAnimation { _ = errors.attempt { try model.archive(habit.id) } }
        }
        Divider()
        Button("Delete…", systemImage: "trash", role: .destructive, action: onDelete)
    }
}

/// "Done today" on habit detail and in a habit's long-press menu (DESIGN.md §5.1): Yes for today even before
/// the habit is due. Hidden once today is done, or while the habit is paused or blocked.
struct DoneTodayButton: View {
    let habitID: UUID
    @Environment(AppModel.self) private var model
    @Environment(ErrorPresenter.self) private var errors

    var body: some View {
        if model.canLogDoneToday(habitID) {
            Button("Done today", systemImage: "checkmark.circle") {
                withAnimation { _ = errors.attempt { try model.logDoneToday(habitID) } }
            }
        }
    }
}
