import HabitCore
import HabitUI
import SwiftUI

/// Vacation mode (DESIGN.md §5.1 screen 5, §4.6): plan one, or change or end the running/scheduled one.
struct VacationSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let vacation = model.currentVacation {
                ManageVacationView(vacation: vacation)
            } else {
                PlanVacationView(plan: model.vacationDraft())
            }
        }
        .navigationTitle("Vacation")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Dates, the checklist of habits to keep (pre-filled from `vacationBehavior`), the parent resolver and
/// the notification and remember toggles.
private struct PlanVacationView: View {
    @Environment(AppModel.self) private var model
    @Environment(ErrorPresenter.self) private var errors
    @Environment(\.dismiss) private var dismiss
    @State private var plan: Vacation.Plan
    @State private var remember = true

    init(plan: Vacation.Plan) {
        _plan = State(initialValue: plan)
    }

    private var pausesSomething: Bool {
        model.activeHabits.contains { !plan.kept.contains($0.id) }
    }

    var body: some View {
        Form {
            Section("Dates") {
                DayPicker(
                    "Starts",
                    day: $plan.start,
                    in: model.today.adding(days: -30) ... model.today.adding(days: 365)
                )
                DayPicker("Ends", day: $plan.end, in: plan.start ... plan.start.adding(days: 365))
            }
            Section {
                ForEach(model.activeHabits) { habit in
                    Toggle([habit.emoji, habit.name].compactMap(\.self).joined(separator: " "), isOn: keep(habit.id))
                }
            } header: {
                Text("Keep asking")
            } footer: {
                Text(pausesSomething
                    ? "Unchecked habits are paused: no questions, and those days don't count against them."
                    : "Uncheck at least one habit to pause.")
            }
            dependencySection
            Section {
                Toggle("Quiet all notifications", isOn: $plan.quietAllNotifications)
                Toggle("Remember choices for next time", isOn: $remember)
            }
        }
        .onChange(of: plan.start) { _, start in
            plan.end = max(plan.end, start)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(plan.start > model.today ? "Schedule" : "Start") {
                    let started = errors.attempt { try model.startVacation(plan, rememberChoices: remember) }
                    if started {
                        dismiss()
                    }
                }
                .disabled(!pausesSomething)
            }
        }
        .errorAlert(errors)
    }

    /// "Also keep parents" when a kept habit depends on a habit that will be paused (§4.6).
    @ViewBuilder private var dependencySection: some View {
        switch Result(catching: { try Vacation.blockedKept(habits: model.truth.habits, kept: plan.kept) }) {
        case let .success(blocked) where !blocked.isEmpty:
            Section {
                Text("Blocked while a habit they depend on is paused: \(names(blocked)).")
                Button("Also keep parents") {
                    errors
                        .attempt { plan.kept = try Vacation.keepingParents(habits: model.truth.habits, kept: plan.kept)
                        }
                }
            } header: {
                Text("Dependencies")
            } footer: {
                Text("Or leave them blocked: they resume with their parents.")
            }
        case .success:
            EmptyView()
        case let .failure(error):
            Section { Text(String(describing: error)).foregroundStyle(.red) }
        }
    }

    private func names(_ ids: Set<UUID>) -> String {
        model.activeHabits.filter { ids.contains($0.id) }.map(\.name).formatted(.list(type: .and))
    }

    private func keep(_ habitID: UUID) -> Binding<Bool> {
        Binding(
            get: { plan.kept.contains(habitID) },
            set: { isKept in
                if isKept {
                    plan.kept.insert(habitID)
                } else {
                    plan.kept.remove(habitID)
                }
            }
        )
    }
}

/// The running or scheduled vacation: move its end, or end / cancel it.
private struct ManageVacationView: View {
    let vacation: PauseEvent
    @Environment(AppModel.self) private var model
    @Environment(ErrorPresenter.self) private var errors
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let today = model.today
        let started = vacation.start <= today
        Form {
            Section {
                LabeledContent("Starts", value: DayFormat.short(vacation.start, today: today))
                DayPicker(
                    "Ends",
                    day: endDay,
                    in: max(vacation.start, today) ... max(vacation.start, today).adding(days: 365)
                )
            } footer: {
                Text(started ? "You're on vacation." : "This vacation is scheduled.")
            }
            Section("Paused") {
                ForEach(vacation.habitIDs, id: \.self) { id in
                    if let habit = model.habit(id) {
                        Text([habit.emoji, habit.name].compactMap(\.self).joined(separator: " "))
                    }
                }
            }
            if vacation.quietAllNotifications {
                Section { Text("Notifications are quiet during this vacation.") }
            }
            Section {
                Button(vacation.start < today ? "End vacation now" : "Cancel vacation", role: .destructive) {
                    if errors.attempt({ try model.end(vacation) }) {
                        dismiss()
                    }
                }
            }
        }
        .toolbar {
            Button("Done") { dismiss() }
        }
        .errorAlert(errors)
    }

    private var endDay: Binding<DayKey> {
        Binding(
            get: { vacation.end },
            set: { end in
                var edited = vacation
                edited.end = end
                errors.attempt { try model.save(edited) }
            }
        )
    }
}
