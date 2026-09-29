import HabitCore
import SwiftUI

/// One check-in card (DESIGN.md §5.2): Yes/No for a single day, a toggle per day for 2–3 days, or
/// "N of K" for longer gaps; always with Don't remember, Delay… and Later. A gated habit's card leads with
/// its parents ("You did Gym on 4 of the last 6 days.") and asks only about those days (§4.5).
public struct QuestionCard: View {
    let question: Question
    let habit: Habit
    let parentNames: [String]
    let intervalDays: Int
    let today: DayKey
    let onAnswer: (AnswerValue) -> Void
    let onDelay: () -> Void
    let onLater: () -> Void

    @State private var perDay: [DayKey: Bool]
    @State private var count: Int

    /// Model mean at or above which per-day toggles start on and the count starts at "All" (§5.2).
    public static let presetThreshold = 0.8

    /// `guess` is the model's mean, used only to preset the controls. `parentNames` name the habits in
    /// `question.parentContext`.
    public init(
        question: Question,
        habit: Habit,
        parentNames: [String] = [],
        intervalDays: Int,
        guess: Double,
        today: DayKey,
        onAnswer: @escaping (AnswerValue) -> Void,
        onDelay: @escaping () -> Void,
        onLater: @escaping () -> Void
    ) {
        self.question = question
        self.habit = habit
        self.parentNames = parentNames
        self.intervalDays = intervalDays
        self.today = today
        self.onAnswer = onAnswer
        self.onDelay = onDelay
        self.onLater = onLater
        let likely = guess >= Self.presetThreshold
        switch question.shape {
        case let .perDay(days):
            _perDay = State(initialValue: Dictionary(uniqueKeysWithValues: days.map { ($0, likely) }))
            _count = State(initialValue: 0)
        case let .count(total):
            _perDay = State(initialValue: [:])
            _count = State(initialValue: likely ? total : 0)
        case .singleDay:
            _perDay = State(initialValue: [:])
            _count = State(initialValue: 0)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let context = question.parentContext {
                Text(Self.contextLine(
                    parentNames: parentNames,
                    context: context,
                    covers: question.covers,
                    today: today
                ))
                .foregroundStyle(.secondary)
            }
            Text(prompt)
                .font(.title3.weight(.semibold))
            controls
            footer
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16)
                .fill(Color(hex: habit.colorHex))
                .frame(width: 6)
        }
        // One rotor stop per card, named for its habit; the controls stay separate elements.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.accessibilityLabel(habit: habit))
    }

    /// One row on the phone; stacked at large Dynamic Type, where the row would wrap both sides.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                headerName.fixedSize()
                Spacer()
                headerDetail.fixedSize()
            }
            VStack(alignment: .leading, spacing: 2) {
                headerName
                headerDetail
            }
        }
    }

    private var headerName: some View {
        Text(habit.displayName)
            .font(.headline)
    }

    private var headerDetail: some View {
        Text("\(Self.importanceLabel(habit.importance)) · ~\(intervalDays)d", bundle: .module)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Self.headerAccessibilityLabel(importance: habit.importance, intervalDays: intervalDays))
    }

    var prompt: String {
        Self.prompt(for: question, today: today)
    }

    @ViewBuilder private var controls: some View {
        switch question.shape {
        case .singleDay:
            HStack {
                primaryButton(String(localized: "Yes", bundle: .module)) { onAnswer(.done) }
                primaryButton(String(localized: "No", bundle: .module), prominent: false) { onAnswer(.notDone) }
            }
        case let .perDay(days):
            ForEach(days, id: \.self) { day in
                Toggle(DayFormat.short(day, today: today), isOn: binding(for: day))
                    .frame(minHeight: 44)
            }
            primaryButton(String(localized: "Save", bundle: .module)) { onAnswer(.perDay(perDay)) }
        case let .count(total):
            countControls(total: total)
        }
    }

    private func countControls(total: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(value: $count, in: 0 ... total) {
                Text("\(count) of \(total) days", bundle: .module)
                    .font(.body.monospacedDigit())
            }
            .frame(minHeight: 44)
            HStack {
                ForEach(Self.countChips(total: total), id: \.label) { chip in
                    Button(chip.label) { count = chip.value }
                        .buttonStyle(.bordered)
                        .tint(count == chip.value ? Color(hex: habit.colorHex) : .secondary)
                        .accessibilityAddTraits(count == chip.value ? .isSelected : [])
                }
            }
            primaryButton(String(localized: "Save", bundle: .module)) { onAnswer(.count(done: count, total: total)) }
        }
    }

    /// One row on the phone; stacked where a row doesn't fit (the watch, large Dynamic Type).
    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { footerButtons }
                .frame(minHeight: 44)
            VStack(alignment: .leading, spacing: 4) { footerButtons }
        }
        .font(.subheadline)
        .buttonStyle(.borderless)
    }

    @ViewBuilder private var footerButtons: some View {
        Button(String(localized: "Don't remember", bundle: .module)) { onAnswer(.dontRemember) }
            .lineLimit(1)
        Button(String(localized: "Delay…", bundle: .module), action: onDelay)
        Button(String(localized: "Later", bundle: .module), action: onLater)
    }

    @ViewBuilder
    private func primaryButton(_ title: String, prominent: Bool = true, action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Text(title).frame(maxWidth: .infinity, minHeight: 44)
        }
        .tint(Color(hex: habit.colorHex))
        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private func binding(for day: DayKey) -> Binding<Bool> {
        Binding(get: { perDay[day] ?? false }, set: { perDay[day] = $0 })
    }

    // MARK: Pure helpers (tested)

    /// The question. For a gated habit the days are the parents' done days, so it asks about "those".
    /// Names the day asked about (§5.2): a question ends on its ask day, today or yesterday (§4.2).
    public nonisolated static func prompt(for question: Question, today: DayKey) -> String {
        let gated = question.parentContext != nil
        let yesterday = question.covers.upperBound < today
        switch question.shape {
        case .singleDay:
            return yesterday
                ? String(localized: "Done yesterday?", bundle: .module)
                : String(localized: "Done today?", bundle: .module)
        case .perDay:
            return gated
                ? String(localized: "Which of those days?", bundle: .module)
                : String(localized: "Which of these days?", bundle: .module)
        case .count(1) where gated:
            return String(localized: "Done on that day?", bundle: .module)
        case let .count(total):
            if gated {
                return String(localized: "On how many of those \(total)?", bundle: .module)
            }
            return yesterday
                ? String(localized: "How many of the \(total) days through yesterday?", bundle: .module)
                : String(localized: "How many of the last \(total) days?", bundle: .module)
        }
    }

    /// "You did Gym on 4 of the last 6 days." (§4.5), or "… through yesterday." when `covers` end before today.
    public nonisolated static func contextLine(
        parentNames: [String],
        context: ParentContext,
        covers: ClosedRange<DayKey>,
        today: DayKey
    ) -> String {
        let parents = parentNames.isEmpty
            ? String(localized: "the habits this depends on", bundle: .module)
            : parentNames.formatted(.list(type: .and))
        let days = covers.count
        let done = context.parentDoneDays
        switch (covers.upperBound < today, days == 1, done == days) {
        case (false, true, _): return String(localized: "You did \(parents) today.", bundle: .module)
        case (true, true, _): return String(localized: "You did \(parents) yesterday.", bundle: .module)
        case (false, false, true):
            return String(localized: "You did \(parents) on all of the last \(days) days.", bundle: .module)
        case (false, false, false):
            return String(localized: "You did \(parents) on \(done) of the last \(days) days.", bundle: .module)
        case (true, false, true):
            return String(
                localized: "You did \(parents) on all of the \(days) days through yesterday.",
                bundle: .module
            )
        case (true, false, false):
            return String(
                localized: "You did \(parents) on \(done) of the \(days) days through yesterday.", bundle: .module
            )
        }
    }

    /// None / Some / Most / All → 0 / round(0.35K) / round(0.75K) / K (§5.2).
    public nonisolated static func countChips(total: Int) -> [(label: String, value: Int)] {
        [
            (String(localized: "None", bundle: .module), 0),
            (String(localized: "Some", bundle: .module), Int((0.35 * Double(total)).rounded())),
            (String(localized: "Most", bundle: .module), Int((0.75 * Double(total)).rounded())),
            (String(localized: "All", bundle: .module), total),
        ]
    }

    /// "Check-in: Gym".
    public nonisolated static func accessibilityLabel(habit: Habit) -> String {
        String(localized: "Check-in: \(habit.name)", bundle: .module)
    }

    /// "High importance, asking every ~6 days": the header's "high · ~6d" read aloud.
    public nonisolated static func headerAccessibilityLabel(importance: Importance, intervalDays: Int) -> String {
        String(
            localized: "\(importanceLabel(importance).localizedCapitalized) importance, \(DayFormat.askInterval(intervalDays))",
            bundle: .module
        )
    }

    public nonisolated static func importanceLabel(_ importance: Importance) -> String {
        switch importance {
        case .low: String(localized: "low", bundle: .module)
        case .normal: String(localized: "normal", bundle: .module)
        case .high: String(localized: "high", bundle: .module)
        }
    }
}

public extension AppModel {
    /// The card for a planned question, with its habit's parents, ask interval and guess filled in (§5.2).
    /// Nil if the habit is gone. Shared by the phone's and the watch's Today screens.
    func card(
        for question: Question,
        onAnswer: @escaping (AnswerValue) -> Void,
        onDelay: @escaping () -> Void,
        onLater: @escaping () -> Void
    ) -> QuestionCard? {
        guard let habit = habit(question.habitID) else { return nil }
        let state = state(of: habit.id)
        return QuestionCard(
            question: question, habit: habit, parentNames: parentNames(for: question),
            intervalDays: state.currentIntervalDays, guess: state.adherence.mean, today: today,
            onAnswer: onAnswer, onDelay: onDelay, onLater: onLater
        )
    }
}
