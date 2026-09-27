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
                Text(Self.contextLine(parentNames: parentNames, context: context, coverDays: question.covers.count))
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
    }

    private var header: some View {
        HStack {
            Text(habit.displayName)
                .font(.headline)
            Spacer()
            Text("\(Self.importanceLabel(habit.importance)) · ~\(intervalDays)d")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(DayFormat.askInterval(intervalDays))
        }
    }

    var prompt: String {
        Self.prompt(for: question)
    }

    @ViewBuilder private var controls: some View {
        switch question.shape {
        case .singleDay:
            HStack {
                primaryButton("Yes") { onAnswer(.done) }
                primaryButton("No", prominent: false) { onAnswer(.notDone) }
            }
        case let .perDay(days):
            ForEach(days, id: \.self) { day in
                Toggle(DayFormat.short(day, today: today), isOn: binding(for: day))
                    .frame(minHeight: 44)
            }
            primaryButton("Save") { onAnswer(.perDay(perDay)) }
        case let .count(total):
            countControls(total: total)
        }
    }

    private func countControls(total: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(value: $count, in: 0 ... total) {
                Text("\(count) of \(total) days")
                    .font(.body.monospacedDigit())
            }
            .frame(minHeight: 44)
            HStack {
                ForEach(Self.countChips(total: total), id: \.label) { chip in
                    Button(chip.label) { count = chip.value }
                        .buttonStyle(.bordered)
                        .tint(count == chip.value ? Color(hex: habit.colorHex) : .secondary)
                }
            }
            primaryButton("Save") { onAnswer(.count(done: count, total: total)) }
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Button("Don't remember") { onAnswer(.dontRemember) }
            Button("Delay…", action: onDelay)
            Button("Later", action: onLater)
        }
        .font(.subheadline)
        .buttonStyle(.borderless)
        .frame(minHeight: 44)
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
    public nonisolated static func prompt(for question: Question) -> String {
        let gated = question.parentContext != nil
        switch question.shape {
        case .singleDay: return "Done today?"
        case .perDay: return gated ? "Which of those days?" : "Which of these days?"
        case .count(1) where gated: return "Done on that day?"
        case let .count(total): return gated ? "On how many of those \(total)?" : "How many of the last \(total) days?"
        }
    }

    /// "You did Gym on 4 of the last 6 days." (§4.5)
    public nonisolated static func contextLine(
        parentNames: [String],
        context: ParentContext,
        coverDays: Int
    ) -> String {
        let parents = parentNames.isEmpty ? "the habits this depends on" : parentNames.formatted(.list(type: .and))
        if coverDays == 1 {
            return "You did \(parents) today."
        }
        return context.parentDoneDays == coverDays
            ? "You did \(parents) on all of the last \(coverDays) days."
            : "You did \(parents) on \(context.parentDoneDays) of the last \(coverDays) days."
    }

    /// None / Some / Most / All → 0 / round(0.35K) / round(0.75K) / K (§5.2).
    public nonisolated static func countChips(total: Int) -> [(label: String, value: Int)] {
        [
            ("None", 0),
            ("Some", Int((0.35 * Double(total)).rounded())),
            ("Most", Int((0.75 * Double(total)).rounded())),
            ("All", total),
        ]
    }

    public nonisolated static func importanceLabel(_ importance: Importance) -> String {
        switch importance {
        case .low: "low"
        case .normal: "normal"
        case .high: "high"
        }
    }
}
