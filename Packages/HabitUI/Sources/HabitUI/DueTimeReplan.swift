import SwiftUI

public extension View {
    /// Replans when the next due time passes while the view is on screen (DESIGN.md §4.2, §5.1), so the phone's
    /// and the watch's Today show a habit's "Done today?" card then without a relaunch.
    func replanningAtDueTimes(_ model: AppModel, errors: ErrorPresenter) -> some View {
        task(id: model.nextDueTime) {
            guard let next = model.nextDueTime else { return }
            do {
                // A second late, so the replan's clock is past the due time.
                try await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow) + 1))
            } catch {
                // Cancelled: the view left the screen or the next due time changed (and restarts this task).
                return
            }
            errors.attempt { try model.reload(newSession: false) }
        }
    }
}
