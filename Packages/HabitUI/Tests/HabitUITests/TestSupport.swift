import Foundation
import HabitCore
import HabitStore
@testable import HabitUI
import Testing

/// 2026-09-27, noon UTC.
let start = DayKey(dayNumber: 20723)
let noon = Date(timeIntervalSince1970: TimeInterval(start.dayNumber) * 86400 + 12 * 3600)

@MainActor
struct Harness {
    let store: TruthStore
    let defaults: UserDefaults

    init(location: StoreLocation = .inMemory) throws {
        store = try TruthStore(container: StoreContainer.make(location))
        defaults = try #require(UserDefaults(suiteName: "AppModelTests-\(UUID().uuidString)"))
    }

    func model(at date: Date = noon) throws -> AppModel {
        try AppModel(store: store, timeZone: .gmt, defaults: defaults) { FixedClock(date: date, calendar: $0) }
    }
}

@MainActor
func addHabit(_ model: AppModel, _ name: String) throws -> Habit {
    var habit = model.newHabitDraft()
    habit.name = name
    try model.save(habit)
    return habit
}

/// "Yes" to every day the question asks about.
func allDone(_ question: Question) -> AnswerValue {
    switch question.shape {
    case .singleDay: .done
    case let .perDay(days): .perDay(Dictionary(uniqueKeysWithValues: days.map { ($0, true) }))
    case let .count(total): .count(done: total, total: total)
    }
}
