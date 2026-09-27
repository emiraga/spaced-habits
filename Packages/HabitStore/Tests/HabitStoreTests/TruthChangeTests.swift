import Foundation
import HabitCore
@testable import HabitStore
import Testing

/// The phone ↔ watch change feed (DESIGN.md §7): what one store writes, the other merges.
@MainActor
struct TruthChangeTests {
    private let day = DayKey(dayNumber: 20723)
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// A store that records what it reports.
    @MainActor
    private final class Recording {
        let store: TruthStore
        var changes: [TruthChange] = []

        init() throws {
            store = try TruthStore(container: StoreContainer.make(.inMemory))
            store.onChange = { [unowned self] in changes.append($0) }
        }
    }

    private func gym() -> Habit {
        Habit(name: "Gym", colorHex: "#3366CC", createdAt: now, createdDay: day)
    }

    private func answer(_ habit: Habit, _ value: AnswerValue, at date: Date) -> Answer {
        Answer(
            questionID: UUID(), habitID: habit.id, covers: day ... day, value: value, answeredAt: date,
            timezone: "UTC", channel: .watch
        )
    }

    @Test func writesAreReportedAndMergeIntoAnotherStore() throws {
        let watch = try Recording()
        let gym = gym()
        try watch.store.save(gym, editedAt: now)
        try watch.store.append(answer(gym, .done, at: now))
        #expect(watch.changes.map(\.kind) == ["habit", "habitRevision", "answer"])

        let phone = try Recording()
        #expect(try phone.store.merge(watch.changes))
        #expect(try phone.store.load() == watch.store.load())
        #expect(phone.changes.isEmpty, "merged changes must not be echoed back")
    }

    /// The same answer by WatchConnectivity and again by CloudKit, or late: stored once, newest kept.
    @Test func mergeIsIdempotentAndLatestWins() throws {
        let phone = try Recording()
        let gym = gym()
        try phone.store.save(gym, editedAt: now)
        let original = phone.changes

        var renamed = gym
        renamed.name = "Gym (evenings)"
        let watch = try Recording()
        try watch.store.merge(original)
        try watch.store.save(renamed, editedAt: now.addingTimeInterval(60))

        #expect(try !watch.store.merge(original))
        #expect(try watch.store.load().habits.map(\.name) == ["Gym (evenings)"])
        #expect(try phone.store.merge(watch.changes))
        #expect(try !phone.store.merge(watch.changes))
        #expect(try phone.store.load().habits.map(\.name) == ["Gym (evenings)"])
        #expect(try phone.store.load().habitRevisions.count == 2)
    }

    /// CloudKit imports in batches: an answer can arrive before its habit. Loading must not fail meanwhile.
    @Test func answerMergedBeforeItsHabitWaitsForIt() throws {
        let watch = try Recording()
        let gym = gym()
        try watch.store.save(gym, editedAt: now)
        try watch.store.append(answer(gym, .done, at: now))

        let phone = try Recording()
        try phone.store.merge(watch.changes.filter { $0.kind == "answer" })
        let early = try phone.store.load()
        #expect(early == Truth(habits: []))
        try early.validate()

        try phone.store.merge(watch.changes)
        #expect(try phone.store.load() == watch.store.load())
        #expect(try phone.store.load().answers.count == 1)
    }

    /// A newly installed watch gets every record at once.
    @Test func allChangesRebuildTheSameTruth() throws {
        let phone = try Recording()
        let gym = gym()
        try phone.store.save(gym, editedAt: now)
        try phone.store.append(answer(gym, .notDone, at: now))
        var settings = Settings.default
        settings.sessionBudget = 4
        try phone.store.save(settings, at: now)

        let watch = try Recording()
        try watch.store.merge(phone.store.allChanges())
        #expect(try watch.store.load() == phone.store.load())
    }

    @Test func invalidOrUnknownChangesAreRefused() throws {
        let store = try TruthStore(container: StoreContainer.make(.inMemory))
        var nameless = gym()
        nameless.name = " "
        let payload = try JSONEncoder().encode(nameless)
        #expect(throws: Habit.ValidationError.emptyName) {
            try store.merge([TruthChange(kind: "habit", id: nameless.id, payload: payload, updatedAt: now)])
        }
        #expect(throws: StoreError.unknownKind("mood")) {
            try store.merge([TruthChange(kind: "mood", id: UUID(), payload: Data("{}".utf8), updatedAt: now)])
        }
        #expect(throws: DecodingError.self) {
            try store.merge([TruthChange(kind: "answer", id: UUID(), payload: payload, updatedAt: now)])
        }
        #expect(try store.load() == Truth(habits: []))
    }
}
