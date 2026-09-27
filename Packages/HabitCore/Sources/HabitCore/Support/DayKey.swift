/// A local calendar day (`yyyy-MM-dd`), independent of time zone. All habit data is keyed by `DayKey`,
/// never by `Date` (DESIGN.md §3.1). Only `DayCalendar` converts between the two.
///
/// Stored as a proleptic-Gregorian day number (days since 1970-01-01), so comparison and day
/// arithmetic are integer operations and unaffected by DST. `Strideable` makes `ClosedRange<DayKey>`
/// iterable.
public struct DayKey: Hashable, Comparable, Strideable, Sendable {
    /// Year/month/day of a `DayKey`.
    public struct CivilDate: Hashable, Sendable {
        public let year: Int
        public let month: Int
        public let day: Int
    }

    /// Days since 1970-01-01.
    public let dayNumber: Int

    public init(dayNumber: Int) {
        self.dayNumber = dayNumber
    }

    /// Returns nil when the components do not name a real Gregorian date (e.g. Feb 30).
    public init?(year: Int, month: Int, day: Int) {
        guard (1 ... 12).contains(month), (1 ... Self.daysIn(month: month, year: year)).contains(day) else {
            return nil
        }
        dayNumber = Self.dayNumber(year: year, month: month, day: day)
    }

    /// Parses `yyyy-MM-dd`. Returns nil for anything else.
    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    public var components: CivilDate {
        Self.civil(fromDayNumber: dayNumber)
    }

    public func adding(days: Int) -> DayKey {
        DayKey(dayNumber: dayNumber + days)
    }

    /// Signed number of days from `self` to `other` (`other - self`).
    public func days(to other: DayKey) -> Int {
        other.dayNumber - dayNumber
    }

    // MARK: Comparable, Strideable

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        lhs.dayNumber < rhs.dayNumber
    }

    public func distance(to other: DayKey) -> Int {
        days(to: other)
    }

    public func advanced(by days: Int) -> DayKey {
        adding(days: days)
    }
}

// MARK: - Civil calendar arithmetic

/// Howard Hinnant's days_from_civil / civil_from_days, valid for the whole proleptic Gregorian calendar.
extension DayKey {
    static func dayNumber(year: Int, month: Int, day: Int) -> Int {
        let adjustedYear = month <= 2 ? year - 1 : year
        let era = (adjustedYear >= 0 ? adjustedYear : adjustedYear - 399) / 400
        let yearOfEra = adjustedYear - era * 400
        let shiftedMonth = month > 2 ? month - 3 : month + 9
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    static func civil(fromDayNumber number: Int) -> CivilDate {
        let shifted = number + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return CivilDate(year: year, month: month, day: day)
    }

    static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2:
            let isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return isLeap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }
}

// MARK: - String and Codable

extension DayKey: CustomStringConvertible, LosslessStringConvertible {
    /// `yyyy-MM-dd`, zero-padded.
    public var description: String {
        let date = components
        return "\(Self.pad(date.year, 4))-\(Self.pad(date.month, 2))-\(Self.pad(date.day, 2))"
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}

/// Encoded as a `yyyy-MM-dd` string so exports and sync payloads are human-readable.
extension DayKey: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let key = DayKey(string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid DayKey '\(string)', expected yyyy-MM-dd"
            )
        }
        self = key
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// Lets `[DayKey: V]` encode as a JSON object keyed by `yyyy-MM-dd` instead of a flat key/value array.
extension DayKey: CodingKeyRepresentable {
    public var codingKey: any CodingKey {
        AnyDayCodingKey(stringValue: description)
    }

    public init?(codingKey: some CodingKey) {
        self.init(codingKey.stringValue)
    }
}

private struct AnyDayCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? {
        nil
    }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}
