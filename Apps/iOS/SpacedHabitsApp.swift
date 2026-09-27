import HabitCore
import HabitStore
import HabitUI
import os
import SwiftUI
import UIKit
import WidgetKit

@main
struct SpacedHabitsApp: App {
    @State private var launch: Result<AppModel, any Error>
    /// Nil when the data couldn't be opened. Created here, not in a view, so a background launch for a
    /// notification action finds its delegate (§8).
    private let notifier: Notifier?
    /// Sends this device's writes to the watch and merges the watch's (§7). Nil when the store couldn't
    /// be opened.
    private let bridge: WatchBridge?
    private let sync = SyncMonitor()
    /// A constant, not @State: `init` captures it for sync merges, and an App is created once.
    private let errors = ErrorPresenter()
    @Environment(\.scenePhase) private var scenePhase
    private let logger = Logger(subsystem: "ga.emira.spacedhabits", category: "app")

    init() {
        LaunchMetrics.begin()
        let errors = errors
        var bridge: WatchBridge?
        let launch = Result {
            let store = try TruthStore(container: StoreContainer.make(.appGroup(syncs: true)))
            // Before the model: its first session's questions are writes the watch should get.
            bridge = WatchBridge(store: store, errors: errors)
            let model = try AppModel(
                store: store, timeZone: .current, defaults: StoreContainer.sharedDefaults()
            ) { SystemClock(calendar: $0) }
            #if DEBUG
                // UI tests start from an empty store and today's real date.
                if ProcessInfo.processInfo.arguments.contains("-resetData") {
                    try model.eraseAll()
                }
                // Simulator checks of the watch bridge (§7): something for the watch to receive.
                if ProcessInfo.processInfo.arguments.contains("-sampleHabits"), model.truth.habits.isEmpty {
                    try model.addSampleHabits()
                }
                // §13 M9/M10 checkpoints: import an export (`simulate <scenario> --json` makes one), and
                // export into a folder as Settings → Your data would (export.json, export-csv.zip).
                let arguments = ProcessInfo.processInfo.arguments
                if let flag = arguments.firstIndex(of: "-importFixture"), flag + 1 < arguments.count {
                    try model.importJSON(Data(contentsOf: URL(filePath: arguments[flag + 1])))
                }
                if let flag = arguments.firstIndex(of: "-exportData"), flag + 1 < arguments.count {
                    let folder = URL(filePath: arguments[flag + 1])
                    let export = model.dataExport()
                    try export.json().write(to: folder.appending(path: "export.json"))
                    try export.csvArchive().write(to: folder.appending(path: "export-csv.zip"))
                }
                // UI tests skip animations: every sheet and push otherwise costs an idle wait.
                if ProcessInfo.processInfo.arguments.contains("-disableAnimations") {
                    UIView.setAnimationsEnabled(false)
                }
            #endif
            return model
        }
        _launch = State(initialValue: launch)
        self.bridge = bridge
        guard case let .success(model) = launch else {
            notifier = nil
            return
        }
        bridge?.model = model
        let notifier = Notifier(model: model)
        // Every change to truth, settings or the day: replan notifications, redraw widgets (§6, §8).
        model.onRefresh = { [weak notifier] in
            notifier?.reschedule()
            WidgetCenter.shared.reloadAllTimelines()
        }
        self.notifier = notifier
        // Another device's changes (§10). Not a new session: "Later" cards stay hidden.
        sync.onMerge = { [errors] in
            errors.attempt { try model.reload(newSession: false) }
        }
        // Siri and Shortcuts act on this model when they run in the app (§6).
        IntentModel.live = model
        SpacedHabitsShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            switch launch {
            case let .success(model):
                RootView()
                    .environment(model)
                    .environment(notifier)
                    .environment(sync)
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
        // Returning from the background starts a new session (§4.4) on truth re-read from the store, which
        // widgets and Siri write while the app is suspended (§6). Launch already planned one.
        if old == .background, new != .background {
            errors.attempt { try model.reload() }
        }
        if new == .active, let notifier {
            Task { await errors.attemptAsync { try await notifier.appBecameActive() } }
        }
        if new == .background {
            // Habit names Siri matches in "Log <habit>" (§6).
            SpacedHabitsShortcuts.updateAppShortcutParameters()
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
