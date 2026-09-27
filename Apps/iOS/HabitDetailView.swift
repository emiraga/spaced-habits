import HabitCore
import HabitUI
import SwiftUI

/// Ask interval, 30-day adherence, pauses and a plain history list (DESIGN.md §5.1; charts arrive in M9).
struct HabitDetailView: View {
    let habitID: UUID
    @Environment(AppModel.self) private var model
    @State private var editing = false
    @State private var pausing = false

    var body: some View {
        if let habit = model.habit(habitID) {
            List {
                Section { summary(of: habit) }
                ForEach(model.pauses(of: habitID)) { pause in
                    PauseSection(pause: pause)
                }
                Section {
                    Button("Pause…") { pausing = true }
                }
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
            .sheet(isPresented: $pausing) {
                NavigationStack { PauseSheet(habit: habit, origin: .detail, today: model.today) }
            }
        } else {
            ContentUnavailableView("Habit not found", systemImage: "questionmark")
        }
    }

    @ViewBuilder
    private func summary(of habit: Habit) -> some View {
        let state = model.state(of: habitID)
        if let resume = model.resumeDay(of: habitID) {
            Label("Paused · Resumes \(DayFormat.short(resume, today: model.today))", systemImage: "pause.circle.fill")
                .foregroundStyle(Color(hex: habit.colorHex))
                .font(.headline)
        }
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

/// One running or scheduled pause: extend or shorten it, or end it now. Vacations are changed from the
/// vacation sheet, since they cover several habits.
private struct PauseSection: View {
    let pause: PauseEvent
    @Environment(AppModel.self) private var model
    @Environment(ErrorPresenter.self) private var errors

    var body: some View {
        let today = model.today
        Section {
            LabeledContent(pause.reason.label, value: DayFormat.range(pause.start, pause.end, today: today))
            if pause.reason != .vacation {
                let earliest = max(pause.start, today)
                DayPicker("Until", day: end, in: earliest ... earliest.adding(days: 365))
                Button(pause.start < today ? "End now" : "Cancel pause", role: .destructive) {
                    errors.attempt { try model.end(pause) }
                }
            }
        } header: {
            Text(pause.start <= today ? "Paused" : "Scheduled pause")
        } footer: {
            if pause.reason == .vacation {
                Text("Change the vacation from the Today screen.")
            }
        }
    }

    private var end: Binding<DayKey> {
        Binding(
            get: { pause.end },
            set: { end in
                var edited = pause
                edited.end = end
                errors.attempt { try model.save(edited) }
            }
        )
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
