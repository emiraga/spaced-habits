import HabitCore
import HabitUI
import SwiftUI
import UIKit

/// Reminder permission, cadence, quiet hours and the silence nudge (DESIGN.md §5.1 screen 7, §8).
struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Notifier.self) private var notifier
    @Environment(ErrorPresenter.self) private var errors

    private static let maxTimesPerDay = 6
    private static let defaultQuietHours = (start: 22, end: 7)
    private static let defaultNudgeDays = 5

    private var settings: NotificationSettings {
        model.truth.settings.notifications
    }

    var body: some View {
        Form {
            permissionSection
            cadenceSection
            Section {
                Toggle("Only when something is due", isOn: Binding(
                    get: { settings.onlyWhenQuestionsDue },
                    set: { value in update { $0.onlyWhenQuestionsDue = value } }
                ))
            } footer: {
                Text("Off: a reminder at every time, even with nothing to answer.")
            }
            quietHoursSection
            nudgeSection
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .task { await notifier.refreshAuthorization() }
    }

    /// "20:00" / "08:00, 20:00" / "Every 3 days at 20:00", for the Settings row.
    static func summary(_ settings: NotificationSettings) -> String {
        switch settings.cadence {
        case let .timesPerDay(times): times.sorted().map(format).joined(separator: ", ")
        case let .everyNDays(days, time): "Every \(days) days at \(format(time))"
        }
    }

    // MARK: Sections

    @ViewBuilder private var permissionSection: some View {
        switch notifier.authorization {
        case .notDetermined:
            Section {
                Button("Allow notifications") {
                    Task { await errors.attemptAsync { try await notifier.requestAuthorization() } }
                }
            } footer: {
                Text("Questions arrive as notifications you can answer without opening the app.")
            }
        case .denied:
            Section {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    Link("Turn on in iOS Settings", destination: url)
                }
            } footer: {
                Text("Notifications are off for Spaced Habits.")
            }
        default:
            Section {
                if let next = notifier.pending.first {
                    LabeledContent("Next reminder") {
                        Text("\(next.fireAt.formatted(date: .abbreviated, time: .shortened)) · \(next.title)")
                    }
                } else {
                    LabeledContent("Next reminder", value: "None in the next week")
                }
            } footer: {
                Text("\(notifier.pending.count) scheduled.")
            }
        }
    }

    private var cadenceSection: some View {
        Section("Schedule") {
            Picker("Remind me", selection: Binding(get: { isDaily }, set: setDaily)) {
                Text("Every day").tag(true)
                Text("Every few days").tag(false)
            }
            .pickerStyle(.segmented)
            switch settings.cadence {
            case let .timesPerDay(times):
                ForEach(Array(times.enumerated()), id: \.offset) { index, time in
                    DatePicker(
                        "Time \(index + 1)",
                        selection: timeBinding(time) { new in
                            var edited = times
                            edited[index] = new
                            return .timesPerDay(edited)
                        },
                        displayedComponents: .hourAndMinute
                    )
                    .deleteDisabled(times.count == 1)
                }
                .onDelete { offsets in
                    update {
                        $0
                            .cadence = .timesPerDay(times.enumerated().filter { !offsets.contains($0.offset) }
                                .map(\.element))
                    }
                }
                Button("Add time") {
                    update { try $0.cadence = .timesPerDay(times + [Self.nextFreeTime(after: times)]) }
                }
                .disabled(times.count >= Self.maxTimesPerDay)
            case let .everyNDays(days, time):
                Stepper("Every \(days) days", value: Binding(
                    get: { days },
                    set: { value in update { $0.cadence = .everyNDays(value, time: time) } }
                ), in: 2 ... 14)
                DatePicker(
                    "Time",
                    selection: timeBinding(time) { .everyNDays(days, time: $0) },
                    displayedComponents: .hourAndMinute
                )
            }
        }
    }

    private var quietHoursSection: some View {
        Section {
            Toggle("Quiet hours", isOn: Binding(
                get: { settings.quietHours != nil },
                set: { isOn in
                    update {
                        $0.quietHours = isOn
                            ? try QuietHours(
                                startHour: Self.defaultQuietHours.start,
                                endHour: Self.defaultQuietHours.end
                            )
                            : nil
                    }
                }
            ))
            if let quiet = settings.quietHours {
                Picker("From", selection: Binding(
                    get: { quiet.startHour },
                    set: { hour in update { $0.quietHours = try QuietHours(startHour: hour, endHour: quiet.endHour) } }
                )) { hourOptions }
                Picker("Until", selection: Binding(
                    get: { quiet.endHour },
                    set: { hour in
                        update { $0.quietHours = try QuietHours(startHour: quiet.startHour, endHour: hour) }
                    }
                )) { hourOptions }
            }
        } footer: {
            Text("Reminder times inside quiet hours are skipped.")
        }
    }

    private var nudgeSection: some View {
        Section {
            Toggle("Nudge me when I go quiet", isOn: Binding(
                get: { settings.nudgeAfterSilentDays != nil },
                set: { isOn in update { $0.nudgeAfterSilentDays = isOn ? Self.defaultNudgeDays : nil } }
            ))
            if let days = settings.nudgeAfterSilentDays {
                Stepper("After \(days) days", value: Binding(
                    get: { days },
                    set: { value in update { $0.nudgeAfterSilentDays = value } }
                ), in: 2 ... 30)
            }
        } footer: {
            Text("One notification after that many days without an answer, offering vacation mode for the gap.")
        }
    }

    // MARK: Helpers

    private var isDaily: Bool {
        if case .timesPerDay = settings.cadence {
            true
        } else {
            false
        }
    }

    private func setDaily(_ daily: Bool) {
        guard daily != isDaily else { return }
        let time: TimeOfDay? = switch settings.cadence {
        case let .timesPerDay(times): times.min()
        case let .everyNDays(_, time): time
        }
        update {
            guard let time else { throw NotificationSettings.ValidationError.noTimes }
            $0.cadence = daily ? .timesPerDay([time]) : .everyNDays(3, time: time)
        }
    }

    private var hourOptions: some View {
        ForEach(0 ..< 24, id: \.self) { hour in
            Text(String(format: "%02d:00", hour))
        }
    }

    /// A `DatePicker` binding for a wall-clock time; `cadence` builds the new cadence from the picked time.
    private func timeBinding(
        _ time: TimeOfDay,
        cadence: @escaping (TimeOfDay) -> NotificationSettings.Cadence
    ) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: DateComponents(hour: time.hour, minute: time.minute)) ?? .distantPast },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                update { $0.cadence = try cadence(TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)) }
            }
        )
    }

    private func update(_ change: (inout NotificationSettings) throws -> Void) {
        errors.attempt {
            var settings = model.truth.settings
            try change(&settings.notifications)
            try model.save(settings)
        }
    }

    /// The first whole hour from noon on that isn't taken, for "Add time".
    private static func nextFreeTime(after times: [TimeOfDay]) throws -> TimeOfDay {
        let taken = Set(times.map(\.hour))
        let hour = (0 ..< 24).map { (12 + $0) % 24 }.first { !taken.contains($0) } ?? 12
        return try TimeOfDay(hour: hour, minute: 0)
    }

    private static func format(_ time: TimeOfDay) -> String {
        String(format: "%02d:%02d", time.hour, time.minute)
    }
}
