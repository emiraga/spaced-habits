import Foundation
import HabitCore
import HabitStore
@testable import HabitUI
import Testing

/// Phone and watch, each with its own store and model, joined by the change feed (DESIGN.md §7).
@MainActor
struct WatchSyncTests {
    /// §13 M7 checkpoint, minus the radios: answer on the watch while the phone is unreachable; the watch
    /// shows it at once; delivered later, by WatchConnectivity and again by CloudKit, the phone has it once.
    @Test func checkpointWatchAnswerReachesThePhoneExactlyOnce() throws {
        let phoneHarness = try Harness()
        let phone = try phoneHarness.model()
        var settings = phone.truth.settings
        settings.spotCheckRate = 0
        try phone.save(settings)
        let gym = try addHabit(phone, "Gym")

        let watchHarness = try Harness()
        try watchHarness.store.merge(phoneHarness.store.allChanges())
        let watch = try AppModel(
            store: watchHarness.store, timeZone: .gmt, defaults: watchHarness.defaults, channel: .watch
        ) { FixedClock(date: noon, calendar: $0) }
        var outbox: [TruthChange] = []
        watchHarness.store.onChange = { outbox.append($0) }

        let question = try #require(watch.questions.first)
        #expect(question.habitID == gym.id)
        try watch.answer(question, with: .done)
        #expect(watch.todayStatus(of: gym.id) == .done)
        #expect(phone.todayStatus(of: gym.id) == .due)

        try phone.merge(outbox)
        try phone.merge(outbox)
        #expect(phone.todayStatus(of: gym.id) == .done)
        #expect(phone.questions.isEmpty)
        #expect(phone.truth.answers.map(\.channel) == [.watch])
        #expect(try phoneHarness.store.load().answers.count == 1)
    }

    /// Merged changes aren't sent back: the bridge would otherwise bounce every write forever.
    @Test func mergedChangesAreNotEchoed() throws {
        let phoneHarness = try Harness()
        let phone = try phoneHarness.model()
        _ = try addHabit(phone, "Gym")
        let watchHarness = try Harness()
        var echoed: [TruthChange] = []
        watchHarness.store.onChange = { echoed.append($0) }
        let watch = try watchHarness.model()
        try watch.merge(phoneHarness.store.allChanges())
        #expect(watch.activeHabits.map(\.name) == ["Gym"])
        // Planning the merged habit logs its question, which is a write of the watch's own.
        #expect(Set(echoed.map(\.kind)) == ["question"])
    }
}
