import Foundation
import HabitCore
@testable import HabitUI
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

    private func question(_ shape: QuestionShape, days: Int, parentDoneDays: Int? = nil) -> Question {
        Question(
            habitID: UUID(), covers: today.adding(days: 1 - days) ... today, shape: shape, createdAt: .now,
            parentContext: parentDoneDays.map { ParentContext(parentIDs: [UUID()], parentDoneDays: $0) }
        )
    }

    @Test func promptsAskAboutParentDoneDaysWhenGated() {
        #expect(QuestionCard.prompt(for: question(.singleDay, days: 1)) == "Done today?")
        #expect(QuestionCard.prompt(for: question(.count(total: 6), days: 6)) == "How many of the last 6 days?")
        #expect(QuestionCard
            .prompt(for: question(.count(total: 4), days: 6, parentDoneDays: 4)) == "On how many of those 4?")
        #expect(QuestionCard.prompt(for: question(.count(total: 1), days: 6, parentDoneDays: 1)) == "Done on that day?")
        let perDay = QuestionShape.perDay(days: [today])
        #expect(QuestionCard.prompt(for: question(perDay, days: 2)) == "Which of these days?")
        #expect(QuestionCard.prompt(for: question(perDay, days: 2, parentDoneDays: 1)) == "Which of those days?")
    }

    @Test func contextLineNamesParentsAndTheirDoneDays() {
        func line(_ names: [String], done: Int, of days: Int) -> String {
            QuestionCard.contextLine(
                parentNames: names, context: ParentContext(parentIDs: [], parentDoneDays: done), coverDays: days
            )
        }
        #expect(line(["Gym"], done: 4, of: 6) == "You did Gym on 4 of the last 6 days.")
        #expect(line(["Gym"], done: 3, of: 3) == "You did Gym on all of the last 3 days.")
        #expect(line(["Gym"], done: 1, of: 1) == "You did Gym today.")
        #expect(line(["Gym", "Stretch"], done: 2, of: 5) == "You did Gym and Stretch on 2 of the last 5 days.")
    }
}

struct FormattingTests {
    @Test func relativeDayLabels() {
        #expect(DayFormat.short(today, today: today) == "Today")
        #expect(DayFormat.short(today.adding(days: -1), today: today) == "Yesterday")
        #expect(DayFormat.short(today.adding(days: 1), today: today) == "Tomorrow")
        let older = DayFormat.short(today.adding(days: -2), today: today)
        #expect(older.contains("25"))
    }

    @Test func rangeCollapsesASingleDay() {
        #expect(DayFormat.range(today, today, today: today) == "Today")
        #expect(DayFormat.range(today, today.adding(days: 1), today: today) == "Today – Tomorrow")
    }

    /// `DayPicker` maps days through noon UTC and back.
    @Test func pickerDatesRoundTrip() {
        for offset in [-400, -1, 0, 1, 365] {
            let day = today.adding(days: offset)
            #expect(DayFormat.day(fromNoonUTC: DayFormat.noonUTC(day)) == day)
        }
    }

    @Test func pauseReasonLabels() {
        #expect(PauseReason.choices.map(\.label) == ["Delay", "Sick", "Other"])
        #expect(PauseReason.vacation.label == "Vacation")
        #expect(PauseReason.other("Travel").label == "Travel")
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
