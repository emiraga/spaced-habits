import HabitCore
import HabitUI
import SwiftUI

/// Pause one habit (DESIGN.md §5.1 screen 4, §4.6). From a card ("Delay…") the pause starts today and is
/// logged as a `.delayed` answer; from habit detail the start can be backdated or scheduled.
struct PauseSheet: View {
    enum Origin {
        case card(Question)
        case detail
    }

    let habit: Habit
    let origin: Origin
    @Environment(AppModel.self) private var model
    @Environment(ErrorPresenter.self) private var errors
    @Environment(\.dismiss) private var dismiss
    /// Nil is "Custom".
    @State private var preset: Int? = 3
    @State private var customDays = 5
    @State private var start: DayKey
    @State private var reason: PauseReason = .manual
    @State private var otherReason = ""

    static let presets = [1, 3, 7, 14]

    init(habit: Habit, origin: Origin, today: DayKey) {
        self.habit = habit
        self.origin = origin
        _start = State(initialValue: today)
    }

    private var isDelay: Bool {
        if case .card = origin {
            return true
        }
        return false
    }

    private var days: Int {
        preset ?? customDays
    }

    private var end: DayKey {
        start.adding(days: days - 1)
    }

    private var resolvedReason: PauseReason {
        if case .other = reason {
            return .other(otherReason.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return reason
    }

    var body: some View {
        Form {
            Section("Duration") {
                Picker("Duration", selection: $preset) {
                    ForEach(Self.presets, id: \.self) { Text(DayFormat.days($0)).tag(Int?.some($0)) }
                    Text("Custom").tag(Int?.none)
                }
                .pickerStyle(.segmented)
                if preset == nil {
                    Stepper(DayFormat.days(customDays), value: $customDays, in: 1 ... 90)
                }
            }
            if !isDelay {
                Section {
                    DayPicker(
                        "Starts", day: $start,
                        in: min(habit.createdDay, model.today) ... model.today.adding(days: 365)
                    )
                } footer: {
                    Text("Pick a past day to cover days you've already missed, for example while sick.")
                }
            }
            Section("Reason") {
                Picker("Reason", selection: $reason) {
                    ForEach(PauseReason.choices, id: \.self) { Text($0.label).tag($0) }
                }
                if case .other = reason {
                    TextField("Reason", text: $otherReason)
                }
            }
            Section {
                Text(summary)
            } footer: {
                Text("Paused days don't count against the habit, and its progress is frozen until it resumes.")
            }
        }
        .navigationTitle("\(isDelay ? "Delay" : "Pause") \(habit.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isDelay ? "Delay" : "Pause", action: confirm)
                    .disabled(resolvedReason == .other(""))
            }
        }
        .errorAlert(errors)
    }

    private var summary: String {
        let today = model.today
        let resumes = DayFormat.short(end.adding(days: 1), today: today)
        return String(localized: "Paused \(DayFormat.range(start, end, today: today)). Resumes \(resumes).")
    }

    private func confirm() {
        let done = errors.attempt {
            switch origin {
            case let .card(question):
                try model.delay(question, days: days, reason: resolvedReason)
            case .detail:
                try model.pause(habit.id, from: start, through: end, reason: resolvedReason)
            }
        }
        if done {
            dismiss()
        }
    }
}
