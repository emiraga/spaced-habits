import HabitCore
import HabitUI
import SwiftUI

/// Name, emoji, color, importance, target and recall gap (DESIGN.md §5.1, M2 subset).
struct HabitEditorView: View {
    let isNew: Bool
    @State private var draft: Habit
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
                HStack {
                    ForEach(HabitPalette.colors, id: \.self) { hex in
                        Button { draft.colorHex = hex } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if draft.colorHex == hex {
                                        Image(systemName: "checkmark").foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(hex)
                        .accessibilityAddTraits(draft.colorHex == hex ? .isSelected : [])
                    }
                }
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
                VStack(alignment: .leading) {
                    Text("Target: \(DayFormat.percent(draft.targetAdherence)) of days")
                    Slider(value: $draft.targetAdherence, in: 0.1 ... 1, step: 0.05)
                }
                Stepper(
                    "Ask about at most \(draft.maxRecallGapDays) days",
                    value: $draft.maxRecallGapDays,
                    in: 1 ... 14
                )
            } footer: {
                Text(
                    "Below the target you'll be asked daily. After a gap, questions cover at most this many days; earlier days are estimated."
                )
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
        .errorAlert(errors)
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
