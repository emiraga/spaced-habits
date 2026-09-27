import BackgroundTasks
import HabitCore
import HabitUI
import Observation
import os
import UserNotifications

/// Local notifications (DESIGN.md §8): keeps the pending requests equal to `NotificationPlanner`'s plan
/// (the app calls `reschedule` on every `AppModel.onRefresh`), and turns actions and taps back into
/// `AppModel` calls. Set up in `App.init`, so it is the notification
/// center's delegate before a background launch for an action finishes.
@MainActor
@Observable
final class Notifier: NSObject {
    static let refreshTaskID = "ga.emira.spacedhabits.refresh"

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    /// What is scheduled now, in fire order.
    private(set) var pending: [NotificationContent] = []
    /// Set by tapping the silence nudge; the Today screen opens a retroactive vacation from the day after.
    var vacationAfter: DayKey?

    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private var scheduling: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "ga.emira.spacedhabits", category: "notifications")

    init(model: AppModel) {
        self.model = model
        super.init()
        center.delegate = self
        let actions = NotificationAction.allCases.map { action in
            UNNotificationAction(identifier: action.rawValue, title: action.title, options: [])
        }
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: NotificationContent.questionCategory,
                actions: actions,
                intentIdentifiers: []
            ),
        ])
        reschedule()
    }

    // MARK: Permission

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws {
        _ = try await center.requestAuthorization(options: [.alert, .sound])
        await refreshAuthorization()
        reschedule()
    }

    // MARK: Scheduling

    /// Replaces every pending notification with the current plan. Planning runs off the main actor. A newer
    /// call cancels an older one and waits for it, so their requests never interleave. Await the returned
    /// task to know the requests are in.
    @discardableResult
    func reschedule() -> Task<Void, Never> {
        let previous = scheduling
        previous?.cancel()
        let task = Task { [weak self, model, center, logger] in
            await previous?.value
            do {
                let allowed = await Self.canNotify(center.notificationSettings().authorizationStatus)
                let snapshot = try model.notificationSnapshot()
                let contents = allowed ? try await Task.detached { try snapshot.contents() }.value : []
                try Task.checkCancellation()
                center.removeAllPendingNotificationRequests()
                for content in contents {
                    try Task.checkCancellation()
                    try await center.add(Self.request(for: content))
                }
                self?.pending = contents
                logger.info("Scheduled \(contents.count) notifications")
            } catch is CancellationError {
                return
            } catch {
                logger.error("Rescheduling failed: \(String(describing: error), privacy: .public)")
            }
        }
        scheduling = task
        return task
    }

    #if DEBUG
        /// Checkpoint aid: in 5 seconds, delivers the notification a slot would deliver now (the top card).
        func fireSoon() async throws {
            guard let top = model.questions.first else { throw NotifierError.nothingDue }
            let dueCount = model.questions.count + model.queuedCount
            let planned = PlannedNotification(fireAt: .now, day: model.today, kind: .question(top, dueCount: dueCount))
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            let content = NotificationContent(planned, habits: model.truth.habits)
            try await center.add(Self.request(for: content, identifier: "debug-soon", trigger: trigger))
        }
    #endif

    /// App opened: the cards now on screen supersede delivered notifications, so log and clear them.
    func appBecameActive() async throws {
        await refreshAuthorization()
        var questions: [(question: Question, deliveredAt: Date)] = []
        for notification in await center.deliveredNotifications() {
            if case let .question(question) = try NotificationPayload(userInfo: notification.request.content.userInfo) {
                questions.append((question, notification.date))
            }
        }
        try model.logDelivered(questions)
        center.removeAllDeliveredNotifications()
    }

    // MARK: Background refresh

    /// Asks for a background refresh a few hours out, so the plan moves forward even if the app isn't opened.
    func scheduleBackgroundRefresh() throws {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try BGTaskScheduler.shared.submit(request)
    }

    func backgroundRefresh() async {
        do {
            try model.startSession()
            await reschedule().value
            try scheduleBackgroundRefresh()
        } catch {
            logger.error("Background refresh failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Responses

    private func handle(action: String, payload: NotificationPayload, deliveredAt: Date) async throws {
        switch (payload, NotificationAction(rawValue: action)) {
        case let (.question(question), action?):
            try model.respond(to: question, deliveredAt: deliveredAt, with: action)
        case let (.question(question), nil):
            try model.logDelivered([(question, deliveredAt)])
        case let (.silenceNudge(lastActiveDay), _):
            vacationAfter = lastActiveDay
        case (.reminder, _):
            break
        }
        await reschedule().value
    }

    private static func canNotify(_ status: UNAuthorizationStatus) -> Bool {
        [.authorized, .provisional, .ephemeral].contains(status)
    }

    private static func request(
        for content: NotificationContent,
        identifier: String? = nil,
        trigger: UNNotificationTrigger? = nil
    ) throws -> UNNotificationRequest {
        let body = UNMutableNotificationContent()
        body.title = content.title
        body.subtitle = content.subtitle
        body.body = content.body
        body.categoryIdentifier = content.categoryIdentifier
        body.threadIdentifier = NotificationContent.threadIdentifier
        body.sound = .default
        body.userInfo = try content.payload.userInfo()
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: content.fireAt
        )
        return UNNotificationRequest(
            identifier: identifier ?? content.identifier,
            content: body,
            trigger: trigger ?? UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }
}

enum NotifierError: LocalizedError {
    case nothingDue

    var errorDescription: String? {
        switch self {
        case .nothingDue: String(localized: "Nothing is due, so there is nothing to notify about.")
        }
    }
}

/// Main-actor isolated (not `nonisolated async`): the notification center hands each method an ObjC
/// completion handler, and a `nonisolated async` method calls it from the cooperative pool when it
/// finishes. UIKit asserts that the response handler completes on the main thread (it snapshots the
/// scene), which crashed every tap on a notification.
extension Notifier: @MainActor UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        do {
            let payload = try NotificationPayload(userInfo: response.notification.request.content.userInfo)
            try await handle(action: action, payload: payload, deliveredAt: response.notification.date)
        } catch {
            // Nobody to show it to: the app may have been launched in the background just for this.
            logger.error("Response \(action, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
    }
}
