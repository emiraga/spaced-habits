import HabitCore
import HabitUI
import SwiftUI

/// Creates or renames a cluster ("Morning routine", DESIGN.md §5.1 screen 3). `onSave` gets the saved
/// cluster, so the habit editor can put the habit in a cluster it just created.
struct ClusterEditorView: View {
    let isNew: Bool
    let onSave: (Cluster) -> Void
    @State private var draft: Cluster
    @Environment(AppModel.self) private var model
    @Environment(ErrorPresenter.self) private var errors
    @Environment(\.dismiss) private var dismiss

    init(cluster: Cluster, isNew: Bool, onSave: @escaping (Cluster) -> Void = { _ in }) {
        self.isNew = isNew
        self.onSave = onSave
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
