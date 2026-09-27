import Foundation
import HabitStore
import HabitUI
import os
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// Shown instead of the snapshot when the store couldn't be read.
    var failure: String?
}

/// Timelines for both widgets from the App Group store (DESIGN.md §6): an entry now and one at the next
/// day boundary. Writers (app, widget buttons, Siri) reload the timelines when truth changes.
struct SnapshotProvider: TimelineProvider {
    private static let logger = Logger(subsystem: "ga.emira.spacedhabits", category: "widgets")

    func placeholder(in _: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (SnapshotEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task { @MainActor in
            completion(Self.entries(now: .now)[0])
        }
    }

    func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<SnapshotEntry>) -> Void) {
        Task { @MainActor in
            completion(Timeline(entries: Self.entries(now: .now), policy: .atEnd))
        }
    }

    /// Never empty. A failure becomes an entry that says so (the widget has nobody else to tell) and is
    /// retried at the next reload.
    @MainActor
    private static func entries(now: Date) -> [SnapshotEntry] {
        do {
            return try WidgetTimeline.entries(
                store: TruthStore(container: StoreContainer.make(.appGroup)),
                timeZone: .current,
                defaults: StoreContainer.sharedDefaults(),
                now: now
            ).map { SnapshotEntry(date: $0.date, snapshot: $0.snapshot) }
        } catch {
            logger.error("Timeline failed: \(String(describing: error), privacy: .public)")
            return [SnapshotEntry(date: now, snapshot: .placeholder, failure: "Open Spaced Habits to refresh.")]
        }
    }
}
