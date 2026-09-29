import Foundation
@testable import HabitCore
import Testing

/// A small history with every value kind the export writes, shared by `ExportTests` and `CSVExportTests`.
enum ExportSample {
    /// 2026-09-27.
    static let today = DayKey(dayNumber: 20723)
    static let noon = Date(timeIntervalSince1970: TimeInterval(today.dayNumber * 86400 + 12 * 3600))

    static func id(_ number: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, number))
    }

    static func day(_ offset: Int) -> DayKey {
        today.adding(days: offset)
    }

    /// `offset` days from today's noon, plus a sub-millisecond remainder that export rounds away.
    static func time(_ offset: Double) -> Date {
        noon.addingTimeInterval(offset * 86400 + 0.123_456)
    }

    /// Every value kind the export writes: all answer, question and pause shapes, both dependency modes, an
    /// archived habit, a Health observation, and text that needs CSV quoting.
    static func truth() throws -> Truth {
        let cluster = Cluster(id: id(1), name: "Morning", colorHex: "#109618", listOrder: 0)
        let habits = habits(cluster: cluster)
        let revisions = habits.enumerated().map { index, habit in
            HabitRevision(id: id(20 + UInt8(index)), habit: habit, editedAt: habit.createdAt)
        }
        var settings = Settings.default
        settings.sessionBudget = 4
        settings.notifications = try NotificationSettings(
            cadence: .everyNDays(2, time: TimeOfDay(hour: 8, minute: 30)), quietHours: QuietHours(
                startHour: 22,
                endHour: 7
            ),
            nudgeAfterSilentDays: 5, onlyWhenQuestionsDue: false
        )
        let truth = Truth(
            habits: habits, clusters: [cluster], habitRevisions: revisions, questions: questions(habits),
            answers: answers(habits), pauses: pauses(habits),
            healthObservations: [HealthObservation(id: id(60), habitID: habits[0].id, day: day(-5), sampleID: "HK-1")],
            settings: settings
        )
        try truth.validate()
        return truth
    }

    /// Gym, Shake (gated on Gym), Stretch (sequence after Shake), Old (archived).
    static func habits(cluster: Cluster) -> [Habit] {
        let gym = Habit(
            id: id(10), name: "Gym", emoji: "🏋️", colorHex: "#3366CC", createdAt: time(-10), createdDay: day(-10),
            importance: .high, dueTime: TimeOfDay(uncheckedHour: 18, minute: 5), clusterID: cluster.id,
            healthBinding: .workout(minMinutes: 30), listOrder: 1
        )
        let shake = Habit(
            id: id(11), name: "Shake", colorHex: "#DC3912", createdAt: time(-9), createdDay: day(-9),
            dependencies: [Dependency(parentID: gym.id)], clusterID: cluster.id
        )
        let stretch = Habit(
            id: id(12), name: "Stretch, \"daily\"", colorHex: "#FF9900", createdAt: time(-8), createdDay: day(-8),
            targetAdherence: 0.6, maxRecallGapDays: 5, vacationBehavior: .keep,
            dependencies: [Dependency(parentID: shake.id, mode: .sequence)], notes: "After shake,\nbefore bed"
        )
        let old = Habit(
            id: id(13), name: "Old", colorHex: "#990099", createdAt: time(-10), createdDay: day(-10),
            archivedAt: time(-2)
        )
        return [gym, shake, stretch, old]
    }

    static func questions(_ habits: [Habit]) -> [Question] {
        let (gym, shake, stretch) = (habits[0], habits[1], habits[2])
        return [
            Question(
                id: id(30), habitID: gym.id, covers: day(-1) ... day(-1), shape: .singleDay, createdAt: time(-1),
                presentedAt: time(-1)
            ),
            Question(
                id: id(31), habitID: stretch.id, covers: day(-3) ... day(-1), shape: .perDay(days: [day(-3), day(-1)]),
                createdAt: time(-1), presentedAt: time(-1), dismissedAt: time(-0.5)
            ),
            Question(
                id: id(32), habitID: shake.id, covers: day(-6) ... day(-1), shape: .count(total: 3),
                createdAt: time(-1),
                presentedAt: time(-1), parentContext: ParentContext(parentIDs: [gym.id], parentDoneDays: 3)
            ),
        ]
    }

    static func answers(_ habits: [Habit]) -> [Answer] {
        let (gym, shake, stretch, old) = (habits[0], habits[1], habits[2], habits[3])
        func answer(_ number: UInt8, _ habit: Habit, _ covers: ClosedRange<DayKey>, _ value: AnswerValue) -> Answer {
            Answer(
                id: id(number), questionID: id(number + 10), habitID: habit.id, covers: covers, value: value,
                answeredAt: time(Double(covers.upperBound.dayNumber - today.dayNumber)),
                timezone: "Europe/Sarajevo", channel: .app
            )
        }
        return [
            answer(40, gym, day(-1) ... day(-1), .done),
            answer(41, gym, day(-2) ... day(-2), .notDone),
            answer(42, stretch, day(-3) ... day(-1), .perDay([day(-3): true, day(-1): false])),
            answer(43, shake, day(-6) ... day(-1), .count(done: 2, total: 3)),
            answer(44, old, day(-4) ... day(-4), .dontRemember),
            answer(45, stretch, day(0) ... day(0), .delayed(days: 2)),
        ]
    }

    static func pauses(_ habits: [Habit]) -> [PauseEvent] {
        let (gym, shake, stretch, old) = (habits[0], habits[1], habits[2], habits[3])
        return [
            PauseEvent(
                id: id(50),
                habitIDs: [stretch.id],
                start: day(0),
                end: day(1),
                reason: .manual,
                createdAt: time(0)
            ),
            PauseEvent(
                id: id(51), habitIDs: [gym.id, shake.id], start: day(5), end: day(9), reason: .vacation,
                createdAt: time(-3), quietAllNotifications: true
            ),
            PauseEvent(
                id: id(52), habitIDs: [old.id], start: day(3), end: day(4), reason: .sick, createdAt: time(-5),
                cancelledAt: time(-4)
            ),
            PauseEvent(
                id: id(53), habitIDs: [gym.id], start: day(-8), end: day(-7), reason: .other("Flu, \"again\""),
                createdAt: time(-8)
            ),
        ]
    }

    static func export(_ truth: Truth? = nil) throws -> DataExport {
        let truth = try truth ?? Self.truth()
        let clock = try FixedClock(date: noon, calendar: DayCalendar(timeZone: #require(TimeZone(identifier: "UTC"))))
        return try DataExport(truth: truth, projected: Projection.rebuild(truth, clock: clock), exportedAt: time(0))
    }

    /// Golden files under `Fixtures/Export`. `RECORD_GOLDENS=1 swift test` rewrites them (and fails, so a
    /// recording run is never mistaken for a passing one).
    static func expectGolden(_ data: Data, _ name: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/Export/\(name)")
        if ProcessInfo.processInfo.environment["RECORD_GOLDENS"] == "1" {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
            Issue.record("Recorded \(name)", sourceLocation: sourceLocation)
            return
        }
        let golden = try Data(contentsOf: url)
        #expect(
            String(bytes: data, encoding: .utf8) == String(bytes: golden, encoding: .utf8),
            "\(name) differs from its golden file", sourceLocation: sourceLocation
        )
    }
}
