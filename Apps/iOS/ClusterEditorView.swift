import HabitCore
import HabitUI
import SwiftUI

/// Creates, renames or deletes a cluster ("Morning routine", DESIGN.md §5.1 screen 3). `onSave` gets the
/// saved cluster, so the habit editor can put the habit in a cluster it just created; `onDelete` lets it
/// take the habit out of a deleted one.
struct ClusterEditorView: View {
    let isNew: Bool
    let onSave: (Cluster) -> Void
    let onDelete: () -> Void
    @State private var draft: Cluster
    @State private var confirmingDelete = false
    @Environment(AppModel.self) private var model
    @Environment(ErrorPresenter.self) private var errors
    @Environment(\.dismiss) private var dismiss

    init(
        cluster: Cluster,
        isNew: Bool,
        onSave: @escaping (Cluster) -> Void = { _ in },
        onDelete: @escaping () -> Void = {}
    ) {
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: cluster)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name)
            } footer: {
                Text("Group habits you do together, like a morning routine.")
            }
            Section("Color") {
                PaletteRow(selection: $draft.colorHex)
            }
            if !isNew {
                Section {
                    Button("Delete cluster…", role: .destructive) { confirmingDelete = true }
                } footer: {
                    Text("Its habits stay, in no cluster.")
                }
            }
        }
        .confirmationDialog(
            String(localized: "Delete “\(draft.name)”?"),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete cluster", role: .destructive) {
                if errors.attempt({ try model.deleteCluster(draft.id) }) {
                    onDelete()
                    dismiss()
                }
            }
        }
        .navigationTitle(isNew ? "New cluster" : "Edit cluster")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if errors.attempt({ try model.save(draft) }) {
                        onSave(draft)
                        dismiss()
                    }
                }
            }
        }
        .errorAlert(errors)
    }
}

/// One tappable swatch per `HabitPalette` color; the selected one has a checkmark.
struct PaletteRow: View {
    @Binding var selection: String

    var body: some View {
        HStack {
            ForEach(HabitPalette.colors, id: \.self) { hex in
                Button { selection = hex } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 30, height: 30)
                        .overlay {
                            if selection == hex {
                                Image(systemName: "checkmark").foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hex)
                .accessibilityAddTraits(selection == hex ? .isSelected : [])
            }
        }
    }
}
