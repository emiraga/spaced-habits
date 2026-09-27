import Foundation
import HabitCore
import HabitUI
import SwiftUI
import Testing

private let today = DayKey(dayNumber: 20723)

private func record(_ source: DaySource, value: Double = 1, questionID: UUID? = nil) -> DayRecord {
    DayRecord(habitID: UUID(), day: today, value: value, source: source, confidence: 1, questionID: questionID)
}

struct DayStatusTests {
    @Test func historyShowsHowEachDayIsKnown() {
        #expect(DayStatus(record: record(.observed, value: 1)) == .done)
        #expect(DayStatus(record: record(.observed, value: 0)) == .notDone)
        #expect(DayStatus(record: record(.aggregated, value: 0.6)) == .aggregated)
        #expect(DayStatus(record: record(.inferred, value: 0.9)) == .inferred)
        #expect(DayStatus(record: record(.paused, value: 0)) == .paused)
        #expect(DayStatus(record: record(.blocked, value: 0)) == .blocked)
    }

    @Test func todayShowsDueOrNotDueUntilAnswered() {
        #expect(DayStatus.today(record: record(.inferred), isDue: true) == .due)
        #expect(DayStatus.today(record: record(.inferred), isDue: false) == .notDue)
        #expect(DayStatus.today(record: record(.unknown), isDue: true) == .due)
        #expect(DayStatus.today(record: nil, isDue: false) == .notDue)
        // "Don't remember" is an answer.
        #expect(DayStatus.today(record: record(.unknown, questionID: UUID()), isDue: false) == .unknown)
        #expect(DayStatus.today(record: record(.observed), isDue: false) == .done)
    }

    @Test func historyTextMarksCountsAndEstimates() {
        #expect(DayStatus.historyText(record(.observed, value: 1)) == "Done")
        #expect(DayStatus.historyText(record(.aggregated, value: 0.5)).hasSuffix("(from a count)"))
        #expect(DayStatus.historyText(record(.inferred, value: 0.9)).hasSuffix("(estimated)"))
        #expect(DayStatus.historyText(record(.paused, value: 0)) == "Paused")
    }

    /// §1.1: aggregated (answered as a count) and inferred (no answer) never look alike.
    @Test func glyphsAreDistinct() {
        #expect(Set(DayStatus.allCases.map(\.glyph)).count == DayStatus.allCases.count)
        #expect(Set(DayStatus.allCases.map(\.label)).count == DayStatus.allCases.count)
    }
}

struct QuestionCardTests {
    @Test func countChipsFollowDesign() {
        #expect(QuestionCard.countChips(total: 6).map(\.value) == [0, 2, 5, 6])
        #expect(QuestionCard.countChips(total: 4).map(\.value) == [0, 1, 3, 4])
        #expect(QuestionCard.countChips(total: 4).map(\.label) == ["None", "Some", "Most", "All"])
    }
}

struct FormattingTests {
    @Test func relativeDayLabels() {
        #expect(DayFormat.short(today, today: today) == "Today")
        #expect(DayFormat.short(today.adding(days: -1), today: today) == "Yesterday")
        let older = DayFormat.short(today.adding(days: -2), today: today)
        #expect(older.contains("25"))
    }

    @Test func askIntervalWording() {
        #expect(DayFormat.askInterval(1) == "Asking daily")
        #expect(DayFormat.askInterval(9) == "Asking every ~9 days")
    }

    @Test func paletteColorsParse() {
        for hex in HabitPalette.colors {
            #expect(Color(hex: hex) != .gray, "\(hex)")
        }
        #expect(Color(hex: "nope") == .gray)
    }
}
