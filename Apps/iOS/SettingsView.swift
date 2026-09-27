import HabitCore
import HabitUI
import SwiftUI

/// Session budget, day start hour and reminders (DESIGN.md §5.1), plus debug controls in debug builds.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(ErrorPresenter.self) private var errors
    @Environment(Notifier.self) private var notifier
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingErase = false
    private let buildInfo = BuildInfo(infoDictionary: Bundle.main.infoDictionary)

    var body: some View {
        Form {
            Section {
                Stepper(
                    "Questions per session: \(model.truth.settings.sessionBudget)",
                    value: setting(\.sessionBudget),
                    in: 1 ... 10
                )
                Picker("Day starts at", selection: setting(\.dayStartHour)) {
                    ForEach(0 ..< 24, id: \.self) { hour in
                        Text(String(format: "%02d:00", hour))
                    }
                }
            } header: {
                Text("Check-ins")
            } footer: {
                Text("Answers given before this hour count for the previous day.")
            }
            Section {
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    LabeledContent(
                        "Reminders",
                        value: NotificationSettingsView.summary(model.truth.settings.notifications)
                    )
                }
            }
            Section("About") {
                LabeledContent("Version", value: buildInfo.displayString)
            }
            #if DEBUG
                debugSection
            #endif
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Done") { dismiss() }
        }
        .errorAlert(errors)
    }

    /// Reads and writes one field of the stored settings; invalid values are rejected by `AppModel`.
    private func setting<Value>(_ keyPath: WritableKeyPath<Settings, Value>) -> Binding<Value> {
        Binding(
            get: { model.truth.settings[keyPath: keyPath] },
            set: { value in
                var settings = model.truth.settings
                settings[keyPath: keyPath] = value
                errors.attempt { try model.save(settings) }
            }
        )
    }

    #if DEBUG
        /// §13 M2 checkpoint controls: shift the injected clock, seed data, start over.
        private var debugSection: some View {
            Section {
                LabeledContent("Today", value: "\(model.today) (+\(model.dayOffset) days)")
                Button("Advance one day") {
                    if errors.attempt({ try model.advanceDay() }) {
                        dismiss()
                    }
                }
                Button("Notify in 5 seconds") {
                    Task { await errors.attemptAsync { try await notifier.fireSoon() } }
                }
                Button("Add sample habits") { errors.attempt { try model.addSampleHabits() } }
                Button("Erase all data", role: .destructive) { confirmingErase = true }
                    .confirmationDialog("Erase all habits and answers?", isPresented: $confirmingErase) {
                        Button("Erase all data", role: .destructive) { errors.attempt { try model.eraseAll() } }
                    }
            } header: {
                Text("Debug")
            } footer: {
                Text("Advancing the day moves the app's clock forward; it can only be reset by erasing all data.")
            }
        }
    #endif
}
