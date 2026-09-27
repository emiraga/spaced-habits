import HabitCore
import HabitStore
import HabitUI
import SwiftUI
import WidgetKit

/// The watch app (DESIGN.md §7): its own store, synced by CloudKit and by the bridge to the phone.
@main
struct SpacedHabitsWatchApp: App {
    @State private var launch: Result<AppModel, any Error>
    /// Nil when the store couldn't be opened.
    private let bridge: WatchBridge?
    private let sync = SyncMonitor()
    private let errors: ErrorPresenter
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let errors = ErrorPresenter()
        self.errors = errors
        var bridge: WatchBridge?
        let launch = Result {
            let store = try TruthStore(container: StoreContainer.make(.appGroup(syncs: true)))
            bridge = WatchBridge(store: store, errors: errors)
            return try AppModel(
                store: store, timeZone: .current, defaults: StoreContainer.sharedDefaults(), channel: .watch
            ) { SystemClock(calendar: $0) }
        }
        _launch = State(initialValue: launch)
        self.bridge = bridge
        guard case let .success(model) = launch else { return }
        bridge?.model = model
        model.onRefresh = { WidgetCenter.shared.reloadAllTimelines() }
        // Another device's changes via CloudKit (§10). Not a new session: "Later" cards stay hidden.
        sync.onMerge = {
            errors.attempt { try model.reload(newSession: false) }
        }
    }

    var body: some Scene {
        WindowGroup {
            switch launch {
            case let .success(model):
                WatchRootView()
                    .environment(model)
                    .environment(errors)
                    .errorAlert(errors)
                    .onChange(of: scenePhase) { old, new in
                        // Returning to the app starts a new session on re-read truth (§4.4).
                        if old == .background, new != .background {
                            errors.attempt { try model.reload() }
                        }
                    }
            case let .failure(error):
                ContentUnavailableView(
                    "Spaced Habits couldn't open its data",
                    systemImage: "exclamationmark.triangle",
                    description: Text(String(describing: error))
                )
            }
        }
    }
}

/// Today's cards, then the habit list, as vertical pages.
struct WatchRootView: View {
    var body: some View {
        NavigationStack {
            TabView {
                WatchTodayView()
                WatchHabitsView()
            }
            .tabViewStyle(.verticalPage)
        }
    }
}
