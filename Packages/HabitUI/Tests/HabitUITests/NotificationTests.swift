import Foundation
import HabitCore
import HabitStore
@testable import HabitUI
import Testing

private let eightPM = noon.addingTimeInterval(8 * 3600)

@MainActor
private func useTwoTimesPerDay(_ model: AppModel, quietHours: QuietHours? = nil) throws {
    var settings = model.truth.settings
    settings.spotCheckRate = 0
    settings.notifications.cadence = try .timesPerDay([TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 20, minute: 0)])
    settings.notifications.quietHours = quietHours
    try model.save(settings)
}

/// The payload as the notification center hands it back.
private func roundTrip(_ content: NotificationContent) throws -> NotificationPayload {
    let userInfo: [AnyHashable: Any] = try content.payload.userInfo()
    return try NotificationPayload(userInfo: userInfo)
}

private func question(_ content: NotificationContent?) throws -> Question {
    guard case let .question(question) = try roundTrip(#require(content)) else {
        Issue.record("not a question: \(String(describing: content))")
        throw CancellationError()
    }
    return question
}

/// Notifications (§8), minus the notification center: two times per day, notified only while
/// something is due, "Yes" answered by a process launched just for the action, then seen after relaunch.
@MainActor
struct NotificationCheckpointTests {
    @Test func checkpointAnswerYesFromNotificationWithAppKilled() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let harness = try Harness(location: .file(url))
        func launch() throws -> AppModel {
            try AppModel(
                store: TruthStore(container: StoreContainer.make(.file(url))), timeZone: .gmt,
                defaults: harness.defaults
            ) { FixedClock(date: noon, calendar: $0) }
        }

        let app = try harness.model()
        let gym = try addHabit(app, "Gym")
        try useTwoTimesPerDay(app)
        let planned = try app.notificationSnapshot().contents()
        let tonight = try #require(planned.first)
        #expect(tonight.fireAt == eightPM)
        #expect(tonight.title == "Gym")
        #expect(tonight.body == "Done today?")
        #expect(tonight.categoryIdentifier == NotificationContent.questionCategory)

        let background = try launch()
        let asked = try question(tonight)
        try background.respond(to: asked, deliveredAt: eightPM, with: .done)

        let relaunched = try launch()
        let answer = try #require(relaunched.truth.answers.last)
        #expect(relaunched.truth.answers.count == 1)
        #expect(answer.channel == .notification)
        #expect(answer.value == .done)
        #expect(answer.covers == start ... start)
        #expect(answer.questionID == asked.id)
        #expect(relaunched.truth.questions.first { $0.id == asked.id }?.presentedAt == eightPM)
        #expect(relaunched.todayStatus(of: gym.id) == .done)
        #expect(relaunched.questions.isEmpty)
        // Nothing is due for the rest of today, so tonight's slot is gone.
        #expect(try relaunched.notificationSnapshot().contents().first?.fireAt ?? .distantFuture > eightPM)
    }

    @Test func checkpointQuietHoursSkipTheNextSlot() throws {
        let model = try Harness().model()
        _ = try addHabit(model, "Gym")
        try useTwoTimesPerDay(model, quietHours: QuietHours(startHour: 19, endHour: 7))
        let planned = try model.notificationSnapshot().contents()
        #expect(planned.first?.fireAt == eightPM.addingTimeInterval(12 * 3600))
        #expect(!planned.contains { $0.fireAt == eightPM })
    }
}

@MainActor
struct NotificationResponseTests {
    @Test func staleNotificationIsRejected() throws {
        let model = try Harness().model()
        _ = try addHabit(model, "Gym")
        try useTwoTimesPerDay(model)
        let planned = try question(model.notificationSnapshot().contents().first)
        try model.answer(#require(model.questions.first), with: .notDone)

        #expect(throws: AnswerRefusal.alreadyCovered(through: start)) {
            try model.respond(to: planned, deliveredAt: eightPM, with: .done)
        }
        #expect(model.truth.answers.map(\.value) == [.notDone])
    }

    @Test func laterLogsADismissalOnly() throws {
        let model = try Harness().model()
        _ = try addHabit(model, "Gym")
        try useTwoTimesPerDay(model)
        let planned = try question(model.notificationSnapshot().contents().first)
        try model.logDelivered([(planned, eightPM)])
        try model.respond(to: planned, deliveredAt: eightPM, with: .later)

        #expect(model.truth.answers.isEmpty)
        let logged = model.truth.questions.filter { $0.id == planned.id }
        #expect(logged.count == 1)
        #expect(logged.first?.presentedAt == eightPM)
        #expect(logged.first?.dismissedAt == noon)
    }

    @Test func deliveredQuestionsAreLoggedOnce() throws {
        let model = try Harness().model()
        _ = try addHabit(model, "Gym")
        let planned = try question(model.notificationSnapshot().contents().first)
        let before = model.truth.questions.count
        try model.logDelivered([(planned, eightPM)])
        try model.logDelivered([(planned, eightPM)])
        #expect(model.truth.questions.count == before + 1)
    }

    @Test func multiDayQuestionsNeedTheApp() throws {
        let model = try Harness().model()
        let gym = try addHabit(model, "Gym")
        let question = Question(
            habitID: gym.id,
            covers: start ... start.adding(days: 1),
            shape: .perDay(days: [start]),
            createdAt: noon
        )
        #expect(throws: AnswerRefusal.notSingleDay) {
            try model.respond(to: question, deliveredAt: eightPM, with: .done)
        }
    }

    /// The debug clock runs days ahead; notifications still fire on the real clock.
    @Test func dayOffsetShiftsFireDatesBack() throws {
        let model = try Harness().model()
        _ = try addHabit(model, "Gym")
        try useTwoTimesPerDay(model)
        try model.advanceDay()
        let first = try #require(model.notificationSnapshot().contents().first)
        #expect(first.fireAt == eightPM)
        #expect(try question(first).covers == start ... start.adding(days: 1))
    }

    @Test func nudgeDraftsARetroactiveVacation() throws {
        let model = try Harness().model()
        _ = try addHabit(model, "Gym")
        let draft = model.vacationDraft(after: start.adding(days: -4))
        #expect(draft.start == start.adding(days: -3))
        #expect(draft.end == start)
        #expect(model.vacationDraft(after: start.adding(days: -90)).start == start.adding(days: -30))
    }
}

struct NotificationContentTests {
    private let gym = Habit(name: "Gym", emoji: "🏋️", colorHex: "#00AA00", createdAt: noon, createdDay: start)

    @Test func groupedQuestionNamesTheTopHabitAndCountsTheRest() throws {
        let question = Question(habitID: gym.id, covers: start ... start, shape: .singleDay, createdAt: noon)
        let planned = PlannedNotification(fireAt: eightPM, day: start, kind: .question(question, dueCount: 3))
        let content = NotificationContent(planned, habits: [gym])
        #expect(content.title == "🏋️ Gym")
        #expect(content.subtitle == "3 habits to review")
        #expect(try roundTrip(content) == .question(question))
    }

    @Test func gatedQuestionLeadsWithItsParents() {
        var protein = Habit(name: "Protein", colorHex: "#00AA00", createdAt: noon, createdDay: start)
        protein.dependencies = [Dependency(parentID: gym.id, mode: .gate)]
        let covers = start.adding(days: -5) ... start
        let question = Question(
            habitID: protein.id, covers: covers, shape: .count(total: 4), createdAt: noon,
            parentContext: ParentContext(parentIDs: [gym.id], parentDoneDays: 4)
        )
        let planned = PlannedNotification(fireAt: eightPM, day: start, kind: .question(question, dueCount: 1))
        let content = NotificationContent(planned, habits: [gym, protein])
        #expect(content.body == "You did Gym on 4 of the last 6 days. On how many of those 4?")
        #expect(content.categoryIdentifier.isEmpty)
        #expect(content.subtitle.isEmpty)
    }

    @Test func nudgeAndReminderRoundTrip() throws {
        let nudge = NotificationContent(
            PlannedNotification(
                fireAt: eightPM,
                day: start,
                kind: .silenceNudge(lastActiveDay: start.adding(days: -5))
            ),
            habits: []
        )
        #expect(nudge.body.hasPrefix("No check-ins for 5 days."))
        #expect(try roundTrip(nudge) == .silenceNudge(lastActiveDay: start.adding(days: -5)))
        let reminder = NotificationContent(
            PlannedNotification(fireAt: eightPM, day: start, kind: .reminder),
            habits: []
        )
        #expect(try roundTrip(reminder) == .reminder)
    }

    @Test func malformedPayloadsThrow() {
        #expect(throws: NotificationPayload.PayloadError.missingKind) { try NotificationPayload(userInfo: [:]) }
        #expect(throws: NotificationPayload.PayloadError.unknownKind("x")) {
            try NotificationPayload(userInfo: ["kind": "x"])
        }
        #expect(throws: NotificationPayload.PayloadError.invalidDay("nope")) {
            try NotificationPayload(userInfo: ["kind": "silenceNudge", "lastActiveDay": "nope"])
        }
    }
}
