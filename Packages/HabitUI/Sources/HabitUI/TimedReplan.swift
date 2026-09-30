import SwiftUI

public extension View {
    /// Replans when the next due time passes or a "Later" snooze ends while the view is on screen (DESIGN.md
    /// §4.2, §4.4, §5.1), so the phone's and the watch's Today show a habit's "Done today?" card or the
    /// snoozed card then without a relaunch.
    func replanningOnTime(_ model: AppModel, errors: ErrorPresenter) -> some View {
        task(id: model.nextReplan) {
            guard let next = model.nextReplan else { return }
            do {
                // A second late, so the replan's clock is past the due time or snooze end.
                try await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow) + 1))
            } catch {
                // Cancelled: the view left the screen or the next replan time changed (and restarts this task).
                return
            }
            errors.attempt { try model.reload(newSession: false) }
        }
    }
}
