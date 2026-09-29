import HabitCore
import HabitUI
import SwiftUI

/// Ask interval, 30-day adherence, charts (§12), pauses, dependencies and a plain history list (DESIGN.md
/// §5.1).
struct HabitDetailView: View {
    let habitID: UUID
    @Environment(AppModel.self) private var model
    @AppStorage(ChartSettings.includePausedKey) private var includePaused = false
    @State private var editing = false
    @State private var pausing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let habit = model.habit(habitID) {
            List {
                Section { summary(of: habit) }
                Section("Charts") {
                    HabitCharts(
                        insights: model.insights(of: habit, filter: AdherenceFilter(includingPaused: includePaused)),
                        color: Color(hex: habit.colorHex)
                    )
                    Toggle("Include paused days", isOn: $includePaused)
                }
                connections(of: habit)
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
            .navigationTitle(habit.displayName)
            .toolbar {
                Button("Edit") { editing = true }
            }
            .sheet(isPresented: $editing) {
                NavigationStack { HabitEditorView(habit: habit, isNew: false) }
            }
            .sheet(isPresented: $pausing) {
                NavigationStack { PauseSheet(habit: habit, origin: .detail, today: model.today) }
            }
            .onChange(of: habit.isArchived) { _, archived in
                if archived {
                    dismiss()
                }
            }
        } else {
            // Deleted: go back to Today.
            ContentUnavailableView("Habit not found", systemImage: "questionmark")
                .onAppear { dismiss() }
        }
    }

    @ViewBuilder
    private func summary(of habit: Habit) -> some View {
        let state = model.state(of: habitID)
        if let resume = model.resumeDay(of: habitID) {
            Label("Paused · Resumes \(DayFormat.short(resume, today: model.today))", systemImage: "pause.circle.fill")
                .foregroundStyle(Color(hex: habit.colorHex))
                .font(.headline)
        } else if model.todayStatus(of: habitID) == .blocked {
            Label("Blocked while a habit it depends on is paused", systemImage: "nosign")
                .foregroundStyle(Color(hex: habit.colorHex))
                .font(.headline)
        }
        LabeledContent("Check-ins", value: DayFormat.askInterval(state.currentIntervalDays))
        let parents = model.gateParents(of: habitID)
        if parents.isEmpty {
            adherenceRow(String(localized: "Adherence, 30 days"), model.adherence(of: habitID))
        } else {
            // P(habit | parents) is what the scheduler tracks; P(habit) is shown alongside (§4.5).
            let names = parents.map(\.name).formatted(.list(type: .and))
            adherenceRow(String(localized: "On \(names) days, 30 days"), model.adherence(of: habitID))
            adherenceRow(
                String(localized: "All days, 30 days"),
                model.adherence(of: habitID, includingParentMisses: true)
            )
        }
        if model.dueHabitIDs.contains(habitID) {
            LabeledContent("Next check-in", value: "Today")
        } else if let next = model.nextCheckIn(of: habit) {
            LabeledContent("Next check-in", value: DayFormat.short(next, today: model.today))
        }
        LabeledContent("Target", value: DayFormat.percent(habit.targetAdherence))
    }

    private func adherenceRow(_ label: String, _ adherence: (mean: Double, days: Int)?) -> some View {
        LabeledContent(
            label,
            value: adherence.map { String(localized: "\(DayFormat.percent($0.mean)) of \($0.days) answered days") }
                ?? String(localized: "No answers yet")
        )
    }

    /// Cluster, gate parents and gated children (§4.5); parents and children link to their detail.
    @ViewBuilder
    private func connections(of habit: Habit) -> some View {
        let parents = model.gateParents(of: habitID)
        let children = model.gatedChildren(of: habitID)
        let cluster = model.cluster(habit.clusterID)
        if cluster != nil || !parents.isEmpty || !children.isEmpty {
            Section("Connections") {
                if let cluster {
                    LabeledContent("Cluster", value: cluster.name)
                }
                ForEach(parents) { parent in
                    NavigationLink(value: parent.id) { LabeledContent("Depends on", value: parent.name) }
                }
                ForEach(children) { child in
                    NavigationLink(value: child.id) { LabeledContent("Needed by", value: child.name) }
                }
            }
        }
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
