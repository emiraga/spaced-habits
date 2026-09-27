import Foundation
@testable import HabitCore
import Testing

struct DayKeyTests {
    @Test func epochIsDayZero() {
        #expect(DayKey(year: 1970, month: 1, day: 1)?.dayNumber == 0)
        #expect(DayKey(dayNumber: 0).description == "1970-01-01")
    }

    @Test func matchesFoundationGregorianAcrossCenturies() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let start = try #require(utc.date(from: DateComponents(year: 1600, month: 1, day: 1)))
        let startNumber = try #require(DayKey(year: 1600, month: 1, day: 1)).dayNumber
        // Every 97th day for ~800 years: covers all months, leap rules for 1700/1800/1900/2000/2100.
        for offset in stride(from: 0, to: 292_000, by: 97) {
            let date = try #require(utc.date(byAdding: .day, value: offset, to: start))
            let parts = utc.dateComponents([.year, .month, .day], from: date)
            let key = DayKey(dayNumber: startNumber + offset)
            #expect(try key.components == .init(
                year: #require(parts.year),
                month: #require(parts.month),
                day: #require(parts.day)
            ))
        }
    }

    @Test func rejectsImpossibleDates() {
        #expect(DayKey(year: 2026, month: 2, day: 29) == nil)
        #expect(DayKey(year: 2024, month: 2, day: 29) != nil)
        #expect(DayKey(year: 1900, month: 2, day: 29) == nil)
        #expect(DayKey(year: 2000, month: 2, day: 29) != nil)
        #expect(DayKey(year: 2026, month: 4, day: 31) == nil)
        #expect(DayKey(year: 2026, month: 13, day: 1) == nil)
        #expect(DayKey(year: 2026, month: 1, day: 0) == nil)
    }

    @Test(arguments: ["2026-09-27", "0999-01-05", "2024-02-29"])
    func stringRoundTrip(_ string: String) throws {
        #expect(try #require(DayKey(string)).description == string)
    }

    @Test(arguments: ["2026-9-27", "2026-09-27T00:00", "20260927", "2026-02-30", "", "abcd-ef-gh", "2026--09-27"])
    func rejectsMalformedStrings(_ string: String) {
        #expect(DayKey(string) == nil)
    }

    @Test func arithmeticAndRanges() throws {
        let feb27 = try #require(DayKey("2024-02-27"))
        let mar2 = try #require(DayKey("2024-03-02"))
        #expect(feb27.days(to: mar2) == 4)
        #expect(mar2.adding(days: -4) == feb27)
        #expect(feb27 < mar2)
        #expect((feb27 ... mar2).map(\.description) == [
            "2024-02-27", "2024-02-28", "2024-02-29", "2024-03-01", "2024-03-02",
        ])
    }

    @Test func codableUsesPlainString() throws {
        let key = try #require(DayKey("2026-09-27"))
        let data = try JSONEncoder().encode([key])
        #expect(String(bytes: data, encoding: .utf8) == #"["2026-09-27"]"#)
        #expect(try JSONDecoder().decode([DayKey].self, from: data) == [key])
    }

    @Test func decodingInvalidStringThrows() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([DayKey].self, from: Data(#"["2026-02-30"]"#.utf8))
        }
    }
}

struct DayCalendarTests {
    private func date(_ string: String, _ zone: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
        let timeZone = try #require(TimeZone(identifier: zone))
        formatter.timeZone = timeZone
        return try #require(formatter.date(from: string))
    }

    private func calendar(_ zone: String, dayStartHour: Int = 4) throws -> DayCalendar {
        try DayCalendar(timeZone: #require(TimeZone(identifier: zone)), dayStartHour: dayStartHour)
    }

    @Test func instantsBeforeDayStartBelongToPreviousDay() throws {
        let cal = try calendar("Europe/Sarajevo")
        #expect(try cal.dayKey(for: date("2026-09-27T03:59:59", "Europe/Sarajevo")).description == "2026-09-26")
        #expect(try cal.dayKey(for: date("2026-09-27T04:00:00", "Europe/Sarajevo")).description == "2026-09-27")
        #expect(try cal.dayKey(for: date("2026-09-27T23:59:59", "Europe/Sarajevo")).description == "2026-09-27")
    }

    @Test func midnightDayStartUsesPlainCalendarDay() throws {
        let cal = try calendar("America/New_York", dayStartHour: 0)
        #expect(try cal.dayKey(for: date("2026-09-27T00:00:00", "America/New_York")).description == "2026-09-27")
    }

    @Test func sameInstantMapsToDifferentDaysPerTimeZone() throws {
        let instant = try date("2026-09-27T10:00:00", "UTC")
        #expect(try calendar("Pacific/Auckland").dayKey(for: instant).description == "2026-09-27")
        #expect(try calendar("Pacific/Honolulu").dayKey(for: instant).description == "2026-09-26")
    }

    @Test func dstTransitionsDoNotShiftDays() throws {
        let cal = try calendar("America/New_York")
        // Spring forward 2026-03-08 02:00 → 03:00; fall back 2026-11-01 02:00 → 01:00.
        #expect(try cal.dayKey(for: date("2026-03-08T03:30:00", "America/New_York")).description == "2026-03-07")
        #expect(try cal.dayKey(for: date("2026-03-08T04:00:00", "America/New_York")).description == "2026-03-08")
        #expect(try cal.dayKey(for: date("2026-11-01T03:59:00", "America/New_York")).description == "2026-10-31")
        #expect(try cal.dayKey(for: date("2026-11-01T04:00:00", "America/New_York")).description == "2026-11-01")
    }

    @Test(arguments: [-1, 24])
    func rejectsOutOfRangeDayStartHour(_ hour: Int) {
        #expect(throws: DayCalendar.ValidationError.dayStartHourOutOfRange(hour)) {
            try DayCalendar(timeZone: .gmt, dayStartHour: hour)
        }
    }

    @Test func fixedClockReportsCalendarDay() throws {
        let clock = try FixedClock(date: date("2026-09-27T02:00:00", "UTC"), calendar: calendar("UTC"))
        #expect(clock.today().description == "2026-09-26")
    }
}

struct RandomSourceTests {
    @Test func seededSourceIsReproducible() {
        var first = SeededRandomSource(seed: 42)
        var second = SeededRandomSource(seed: 42)
        let firstDraws = (0 ..< 100).map { _ in first.nextUnit() }
        let secondDraws = (0 ..< 100).map { _ in second.nextUnit() }
        #expect(firstDraws == secondDraws)
        #expect(firstDraws.allSatisfy { (0 ..< 1).contains($0) })
    }

    @Test func differentSeedsDiverge() {
        var first = SeededRandomSource(seed: 1)
        var second = SeededRandomSource(seed: 2)
        #expect((0 ..< 10).map { _ in first.next() } != (0 ..< 10).map { _ in second.next() })
    }

    @Test func bernoulliRateIsRoughlyCorrect() {
        var rng = SeededRandomSource(seed: 7)
        let hits = (0 ..< 20000).count(where: { _ in rng.bernoulli(0.05) })
        #expect((800 ... 1200).contains(hits))
    }
}
