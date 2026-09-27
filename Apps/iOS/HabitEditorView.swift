import HabitCore
import HabitUI
import SwiftUI

/// Name, emoji, color, importance, vacation behavior, target and recall gap (DESIGN.md §5.1, M3 subset).
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
                Toggle("Keep asking during vacation", isOn: keepOnVacation)
            } footer: {
                Text(
                    "Vacation mode pauses every habit that isn't kept. You can still change this when you start a vacation."
                )
            }
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
