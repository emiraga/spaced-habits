import HabitCore
import HabitUI
import SwiftUI

/// Name, emoji, color, importance, vacation behavior, depends-on, cluster, target and recall gap
/// (DESIGN.md §5.1 screen 3).
struct HabitEditorView: View {
    let isNew: Bool
    @State private var draft: Habit
    /// Why the last picked parent was refused (a dependency loop).
    @State private var refusal: String?
    /// A new cluster, or the selected one being renamed.
    @State private var editingCluster: Cluster?
    @State private var deleting: Habit?
    @Environment(AppModel.self) private var model
    @Environment(ErrorPresenter.self) private var errors
    @Environment(\.dismiss) private var dismiss

    init(habit: Habit, isNew: Bool) {
        self.isNew = isNew
        _draft = State(initialValue: habit)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name)
                TextField("Emoji (optional)", text: emoji)
            }
            Section("Color") {
                PaletteRow(selection: $draft.colorHex)
            }
            Section {
                Picker("Importance", selection: $draft.importance) {
                    ForEach(Importance.allCases, id: \.self) { Text(QuestionCard.importanceLabel($0).capitalized) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Importance")
            } footer: {
                Text("More important habits are asked first when several are due.")
            }
            Section {
                Toggle("Keep asking during vacation", isOn: keepOnVacation)
            } footer: {
                Text(
                    "Vacation mode pauses every habit that isn't kept. You can still change this when you start a vacation."
                )
            }
            dependsOnSection
            clusterSection
            Section {
                DisclosureGroup("Advanced") {
                    VStack(alignment: .leading) {
                        Text("Target: \(DayFormat.percent(draft.targetAdherence)) of days")
                        Slider(value: $draft.targetAdherence, in: 0.1 ... 1, step: 0.05)
                        explanation(
                            "How often you aim to do this habit. While you're below the target, you'll get a check-in every day. Once you're above it, check-ins become less frequent."
                        )
                    }
                    VStack(alignment: .leading) {
                        Stepper(
                            "Look back up to \(draft.maxRecallGapDays) days",
                            value: $draft.maxRecallGapDays,
                            in: 1 ... 14
                        )
                        explanation(
                            "If you haven't answered for a while, the next check-in asks about at most this many recent days. Earlier days aren't asked about; they're estimated from your history."
                        )
                    }
                }
            }
            if !isNew {
                removeSection
            }
        }
        .navigationTitle(isNew ? "New habit" : "Edit habit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if errors.attempt({ try model.save(draft) }) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(item: $editingCluster) { cluster in
            NavigationStack {
                ClusterEditorView(
                    cluster: cluster,
                    isNew: model.cluster(cluster.id) == nil,
                    onSave: { draft.clusterID = $0.id },
                    onDelete: { draft.clusterID = nil }
                )
            }
        }
        .confirmingDeletion(of: $deleting) { dismiss() }
        .errorAlert(errors)
    }

    /// Archive keeps the history; delete doesn't. Both act on the stored habit, not the unsaved draft.
    private var removeSection: some View {
        Section {
            Button("Archive habit") {
                if errors.attempt({ try model.archive(draft.id) }) {
                    dismiss()
                }
            }
            Button("Delete habit…", role: .destructive) { deleting = model.habit(draft.id) }
        } footer: {
            Text("Archived habits stop being asked about and keep their history. Restore them in Settings.")
        }
    }

    /// Parents are `.gate` edges; the mode is not exposed (§4.5). A pick that would close a loop is refused.
    @ViewBuilder private var dependsOnSection: some View {
        let candidates = model.parentCandidates(for: draft)
        if !candidates.isEmpty {
            Section {
                ForEach(candidates) { parent in
                    let selected = draft.gateParentIDs.contains(parent.id)
                    Button { toggleParent(parent) } label: {
                        HStack {
                            Text(parent.displayName)
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .tint(.primary)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            } header: {
                Text("Depends on")
            } footer: {
                if let refusal {
                    Text(refusal).foregroundStyle(.red)
                } else {
                    Text(
                        "Only asked about on days you did these habits, and its adherence counts only those days. Pausing one of them pauses this too."
                    )
                }
            }
        }
    }

    private func toggleParent(_ parent: Habit) {
        refusal = nil
        if draft.gateParentIDs.contains(parent.id) {
            draft.dependencies.removeAll { $0.parentID == parent.id }
            return
        }
        do {
            try model.checkDependency(on: parent.id, for: draft)
            draft.dependencies.removeAll { $0.parentID == parent.id }
            draft.dependencies.append(Dependency(parentID: parent.id, mode: .gate))
        } catch {
            refusal = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private var clusterSection: some View {
        Section {
            Picker("Cluster", selection: $draft.clusterID) {
                Text("None").tag(UUID?.none)
                ForEach(model.clusters) { cluster in
                    Text(cluster.name).tag(Optional(cluster.id))
                }
            }
            if let cluster = model.cluster(draft.clusterID) {
                Button("Edit “\(cluster.name)”…") { editingCluster = cluster }
            }
            Button("New cluster…") { editingCluster = model.newClusterDraft() }
        } footer: {
            Text("Habits in a cluster are listed together on the Today screen.")
        }
    }

    private func explanation(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.footnote).foregroundStyle(.secondary)
    }

    private var keepOnVacation: Binding<Bool> {
        Binding(
            get: { draft.vacationBehavior == .keep },
            set: { draft.vacationBehavior = $0 ? .keep : .pause }
        )
    }

    /// Keeps the last character typed, so the field holds one emoji; empty clears it.
    private var emoji: Binding<String> {
        Binding(
            get: { draft.emoji ?? "" },
            set: { text in
                let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last.map(String.init)
                draft.emoji = last
            }
        )
    }
}
