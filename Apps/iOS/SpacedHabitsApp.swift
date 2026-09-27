import HabitCore
import HabitStore
import HabitUI
import os
import SwiftUI

@main
struct SpacedHabitsApp: App {
    @State private var launch: Result<AppModel, any Error>
    /// Nil when the data couldn't be opened. Created here, not in a view, so a background launch for a
    /// notification action finds its delegate (§8).
    private let notifier: Notifier?
    @State private var errors = ErrorPresenter()
    @Environment(\.scenePhase) private var scenePhase
    private let logger = Logger(subsystem: "ga.emira.spacedhabits", category: "app")

    init() {
        LaunchMetrics.begin()
        let launch = Result {
            let model = try AppModel(
                store: TruthStore(container: StoreContainer.make(.appGroup)),
                timeZone: .current,
                defaults: .standard
            ) { SystemClock(calendar: $0) }
            #if DEBUG
                // UI tests start from an empty store and today's real date.
                if ProcessInfo.processInfo.arguments.contains("-resetData") {
                    try model.eraseAll()
                }
            #endif
            return model
        }
        _launch = State(initialValue: launch)
        notifier = if case let .success(model) = launch {
            Notifier(model: model)
        } else {
            nil
        }
    }

    var body: some Scene {
        WindowGroup {
            switch launch {
            case let .success(model):
                RootView()
                    .environment(model)
                    .environment(notifier)
                    .environment(errors)
                    .errorAlert(errors)
                    .onChange(of: scenePhase) { old, new in
                        sceneChanged(from: old, to: new, model: model)
                    }
            case let .failure(error):
                ContentUnavailableView(
                    "Spaced Habits couldn't open its data",
                    systemImage: "exclamationmark.triangle",
                    description: Text(String(describing: error))
                )
            }
        }
        .backgroundTask(.appRefresh(Notifier.refreshTaskID)) {
            await notifier?.backgroundRefresh()
        }
    }

    private func sceneChanged(from old: ScenePhase, to new: ScenePhase, model: AppModel) {
        // Returning from the background starts a new session (§4.4); launch already planned one.
        if old == .background, new != .background {
            errors.attempt { try model.startSession() }
        }
        if new == .active, let notifier {
            Task { await errors.attemptAsync { try await notifier.appBecameActive() } }
        }
        if new == .background {
            do {
                try notifier?.scheduleBackgroundRefresh()
            } catch {
                // Not the user's problem: the simulator has no background refresh, and the app still
                // reschedules on every open.
                logger.error("Background refresh request failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
