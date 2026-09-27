import HabitCore
import HabitStore
import HabitUI
import SwiftUI

@main
struct SpacedHabitsApp: App {
    @State private var launch: Result<AppModel, any Error>
    @State private var errors = ErrorPresenter()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        LaunchMetrics.begin()
        _launch = State(initialValue: Result {
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
        })
    }

    var body: some Scene {
        WindowGroup {
            switch launch {
            case let .success(model):
                RootView()
                    .environment(model)
                    .environment(errors)
                    .errorAlert(errors)
                    // Returning from the background starts a new session (§4.4); launch already planned one.
                    .onChange(of: scenePhase) { old, new in
                        if old == .background, new != .background {
                            errors.attempt { try model.startSession() }
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
