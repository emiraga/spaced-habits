import Foundation

/// The JSON export (DESIGN.md §11): `{ schemaVersion, exportedAt, settings, habits, habitRevisions, clusters,
/// answers, questions, pauses, healthObservations }`, i.e. the full `Truth` plus an envelope, and with
/// `includeProjection` the derived `dayRecords`. Collections are in a canonical order that doesn't depend on
/// the store's write order, so export → import → export is byte-identical apart from `exportedAt` (§13 M10).
public struct ExportDocument: Sendable, Hashable {
    /// Bumping it needs a migration note in DESIGN.md §11.
    public static let schemaVersion = 1

    public let exportedAt: Date
    public let truth: Truth
    /// Derived; only with `includeProjection`. Import ignores them and re-projects.
    public let dayRecords: [DayRecord]?

    public init(truth: Truth, exportedAt: Date, projection: Projected? = nil) {
        let truth = truth.canonicallyOrdered()
        self.exportedAt = exportedAt
        self.truth = truth
        dayRecords = projection.map { projected in
            truth.habits.flatMap { habit in
                (projected.records[habit.id] ?? [:]).values.sorted { $0.day < $1.day }
            }
        }
    }
}

/// Envelope keys next to `Truth`'s own: the document is one flat object.
extension ExportDocument: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, exportedAt, dayRecords
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.schemaVersion else { throw ImportError.unsupportedSchemaVersion(version) }
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        truth = try Truth(from: decoder)
        dayRecords = try container.decodeIfPresent([DayRecord].self, forKey: .dayRecords)
    }

    public func encode(to encoder: any Encoder) throws {
        try truth.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaVersion, forKey: .schemaVersion)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encodeIfPresent(dayRecords, forKey: .dayRecords)
    }
}

/// Why a JSON import was refused. Nothing is written when one is thrown.
public enum ImportError: Error, Equatable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    /// Not an export, or a value this version can't read (e.g. an unknown dependency `mode`).
    case invalidDocument(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(version):
            String(
                localized: "This file uses export format \(version); this version of Spaced Habits reads format \(ExportDocument.schemaVersion).",
                bundle: .module
            )
        case let .invalidDocument(detail):
            String(localized: "This file isn't a Spaced Habits export: \(detail)", bundle: .module)
        }
    }
}

/// Encodes and decodes export JSON: sorted keys, pretty-printed, dates as `ExportDate` strings.
public enum ExportCodec {
    public static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ExportDate.string(from: date))
        }
        return try encoder.encode(value)
    }

    public static func decode<Value: Decodable>(_: Value.Type, from data: Data) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = ExportDate.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Invalid date '\(string)', expected yyyy-MM-ddTHH:mm:ss.SSSZ"
                )
            }
            return date
        }
        do {
            return try decoder.decode(Value.self, from: data)
        } catch let error as DecodingError {
            throw ImportError.invalidDocument(describe(error))
        }
    }

    /// Reads an export: checks the schema version and every value's encoding. Validation of the truth itself
    /// (references, the dependency DAG) is `TruthImport`'s.
    public static func decodeDocument(_ data: Data) throws -> ExportDocument {
        try decode(ExportDocument.self, from: data)
    }

    /// `value` as it reads back from an export: dates rounded to the millisecond.
    static func roundTripped<Value: Codable>(_ value: Value) throws -> Value {
        try decode(Value.self, from: encode(value))
    }

    /// "habits[0].dependencies[0].mode: Cannot initialize DependencyMode from invalid String value chain".
    private static func describe(_ error: DecodingError) -> String {
        let context: DecodingError.Context
        switch error {
        case let .typeMismatch(_, errorContext), let .valueNotFound(_, errorContext),
             let .dataCorrupted(errorContext):
            context = errorContext
        case let .keyNotFound(key, errorContext):
            return path(errorContext.codingPath + [key]) + ": missing"
        @unknown default:
            return String(describing: error)
        }
        let path = path(context.codingPath)
        return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
    }

    private static func path(_ codingPath: [any CodingKey]) -> String {
        codingPath.reduce(into: "") { path, key in
            if let index = key.intValue {
                path += "[\(index)]"
            } else {
                path += path.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
    }
}

/// Export timestamps: UTC ISO 8601 with milliseconds, `2026-09-27T12:00:00.000Z`. A date rounds to the
/// millisecond, and a parsed string formats back to itself, which keeps re-exports byte-identical.
public enum ExportDate {
    /// Milliseconds since 1970: the precision exports keep, and the key canonical ordering sorts by.
    public static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    public static func string(from date: Date) -> String {
        let millis = milliseconds(date)
        let msPerDay: Int64 = 86_400_000
        var (days, time) = millis.quotientAndRemainder(dividingBy: msPerDay)
        if time < 0 {
            days -= 1
            time += msPerDay
        }
        let civil = DayKey(dayNumber: Int(days)).components
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", civil.year, civil.month, civil.day,
            Int(time / 3_600_000), Int(time / 60000 % 60), Int(time / 1000 % 60), Int(time % 1000)
        )
    }

    /// Parses `yyyy-MM-ddTHH:mm:ss[.S…]Z` (one to three fraction digits). Nil for anything else.
    public static func date(from string: String) -> Date? {
        let parts = string.split(separator: "T", omittingEmptySubsequences: false)
        guard parts.count == 2, let day = DayKey(String(parts[0])), parts[1].hasSuffix("Z") else { return nil }
        let clock = parts[1].dropLast().split(separator: ".", omittingEmptySubsequences: false)
        guard (1 ... 2).contains(clock.count) else { return nil }
        let fields = clock[0].split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 3, fields.allSatisfy({ $0.count == 2 }),
              let hour = digits(fields[0]), let minute = digits(fields[1]), let second = digits(fields[2]),
              hour < 24, minute < 60, second < 60
        else { return nil }
        var millis = 0
        if clock.count == 2 {
            let fraction = clock[1]
            guard (1 ... 3).contains(fraction.count), let value = digits(fraction) else { return nil }
            millis = value * [100, 10, 1][fraction.count - 1]
        }
        let total = ((Int64(day.dayNumber) * 24 + Int64(hour)) * 60 + Int64(minute)) * 60 + Int64(second)
        return Date(timeIntervalSince1970: Double(total * 1000 + Int64(millis)) / 1000)
    }

    /// Only ASCII digits: `Int` alone also accepts a sign.
    private static func digits(_ text: Substring) -> Int? {
        text.allSatisfy { $0.isASCII && $0.isNumber } ? Int(text) : nil
    }
}

extension Truth {
    /// Export order (§11): habits and questions by creation, revisions by edit, answers by answer time,
    /// pauses by creation, clusters by name, Health observations by day, ties by ID. Times compare at export
    /// precision, so an imported copy sorts the same.
    func canonicallyOrdered() -> Truth {
        func ms(_ date: Date) -> Int64 {
            ExportDate.milliseconds(date)
        }
        var truth = self
        truth.habits.sort { (ms($0.createdAt), $0.id.uuidString) < (ms($1.createdAt), $1.id.uuidString) }
        truth.clusters.sort { ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString) }
        truth.habitRevisions.sort { (ms($0.editedAt), $0.id.uuidString) < (ms($1.editedAt), $1.id.uuidString) }
        truth.questions.sort { (ms($0.createdAt), $0.id.uuidString) < (ms($1.createdAt), $1.id.uuidString) }
        truth.answers.sort { (ms($0.answeredAt), $0.id.uuidString) < (ms($1.answeredAt), $1.id.uuidString) }
        truth.pauses.sort { (ms($0.createdAt), $0.id.uuidString) < (ms($1.createdAt), $1.id.uuidString) }
        truth.healthObservations.sort { ($0.day, $0.id.uuidString) < ($1.day, $1.id.uuidString) }
        return truth
    }
}
