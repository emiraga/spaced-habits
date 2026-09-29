import AppIntents
import Foundation
import HabitCore
import HabitStore
import HabitUI

/// The model an intent acts on (DESIGN.md §6). Compiled into the app and the widget extension.
@MainActor
enum IntentModel {
    /// The app's model, set at launch; nil in the widget extension.
    static var live: AppModel?

    /// The live model if this is the app, otherwise one on the App Group store that plans without logging.
    /// The app re-reads truth when it returns from the background, so it sees the extension's writes.
    static func open() throws -> AppModel {
        if let live {
            return live
        }
        return try AppModel(
            store: TruthStore(container: StoreContainer.make(.appGroup(syncs: false))),
            timeZone: .current,
            defaults: StoreContainer.sharedDefaults(),
            logsPresentedQuestions: false
        ) { SystemClock(calendar: $0) }
    }
}

/// Yes / No on the question widget. Not offered in Shortcuts: `LogHabitIntent` is the one for Siri.
struct AnswerHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Answer Habit"
    static let isDiscoverable = false

    @Parameter(title: "Habit ID") var habitID: String
    /// `yyyy-MM-dd`: the question's ask day (§4.2). Nil in buttons from before due times, which answered today.
    @Parameter(title: "Day") var day: String?
    @Parameter(title: "Done") var done: Bool

    init() {}

    init(habitID: UUID, day: DayKey, done: Bool) {
        self.habitID = habitID.uuidString
        self.day = day.description
        self.done = done
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: habitID) else { throw IntentError.invalidHabitID(habitID) }
        let model = try IntentModel.open()
        let answered = try day.map { string in
            guard let day = DayKey(string) else { throw IntentError.invalidDay(string) }
            return day
        } ?? model.today
        try model.answer(id, day: answered, done: done, channel: .widget)
        return .result()
    }
}

enum IntentError: LocalizedError {
    case invalidHabitID(String)
    case invalidDay(String)

    var errorDescription: String? {
        switch self {
        case let .invalidHabitID(id): String(localized: "\(id) is not a habit ID.")
        case let .invalidDay(day): String(localized: "\(day) is not a day.")
        }
    }
}
