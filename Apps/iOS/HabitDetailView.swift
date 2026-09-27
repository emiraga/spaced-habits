import HabitCore
import HabitUI
import SwiftUI

/// Ask interval, 30-day adherence and a plain history list (DESIGN.md §5.1; charts arrive in M9).
struct HabitDetailView: View {
    let habitID: UUID
    @Environment(AppModel.self) private var model
    @State private var editing = false

    var body: some View {
        if let habit = model.habit(habitID) {
            List {
                Section { summary(of: habit) }
                Section("History") {
                    ForEach(model.history(of: habitID), id: \.day) { record in
                        HistoryRow(record: record, today: model.today)
                    }
                }
            }
            .navigationTitle([habit.emoji, habit.name].compactMap(\.self).joined(separator: " "))
            .toolbar {
                Button("Edit") { editing = true }
            }
            .sheet(isPresented: $editing) {
                NavigationStack { HabitEditorView(habit: habit, isNew: false) }
            }
        } else {
            ContentUnavailableView("Habit not found", systemImage: "questionmark")
        }
    }

    @ViewBuilder
    private func summary(of habit: Habit) -> some View {
        let state = model.state(of: habitID)
        LabeledContent("Check-ins", value: DayFormat.askInterval(state.currentIntervalDays))
        if let adherence = model.adherence(of: habitID) {
            LabeledContent(
                "Adherence, 30 days",
                value: "\(DayFormat.percent(adherence.mean)) of \(adherence.days) answered days"
            )
        } else {
            LabeledContent("Adherence, 30 days", value: "No answers yet")
        }
        if model.dueHabitIDs.contains(habitID) {
            LabeledContent("Next check-in", value: "Today")
        } else if let next = model.nextCheckIn(of: habit) {
            LabeledContent("Next check-in", value: DayFormat.short(next, today: model.today))
        }
        LabeledContent("Target", value: DayFormat.percent(habit.targetAdherence))
    }
}

private struct HistoryRow: View {
    let record: DayRecord
    let today: DayKey

    var body: some View {
        let status = DayStatus(record: record)
        HStack {
            Text(status.glyph)
                .frame(width: 28)
            Text(DayFormat.short(record.day, today: today))
            Spacer()
            Text(DayStatus.historyText(record))
                .foregroundStyle(status == .inferred || status == .unknown ? .secondary : .primary)
        }
        .accessibilityElement(children: .combine)
    }
}
