import HabitCore
import HabitUI
import SwiftUI

/// The watch's Today (DESIGN.md §7): the same cards as the phone, one after another.
struct WatchTodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(ErrorPresenter.self) private var errors
    @State private var delaying: Question?
    @State private var answers = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(model.questions) { question in
                    if let card = model.card(
                        for: question,
                        onAnswer: { value in
                            if errors.attempt({ try model.answer(question, with: value) }) {
                                answers += 1
                            }
                        },
                        onDelay: { delaying = question },
                        onLater: { errors.attempt { try model.later(question) } }
                    ) {
                        card.id(question.id)
                    }
                }
                if model.queuedCount > 0 {
                    Button("\(model.queuedCount) more") { errors.attempt { try model.showMore() } }
                }
                if model.questions.isEmpty {
                    emptyState
                }
            }
        }
        .navigationTitle("Today")
        .sheet(item: $delaying) { question in
            WatchDelaySheet(question: question)
        }
        .sensoryFeedback(.success, trigger: answers)
    }

    @ViewBuilder private var emptyState: some View {
        if model.activeHabits.isEmpty {
            Text("Add habits on your iPhone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.top)
        } else {
            nothingToAsk
        }
    }

    private var nothingToAsk: some View {
        VStack(spacing: 4) {
            Image(systemName: "checkmark.circle")
                .font(.title)
                .foregroundStyle(.green)
            Text("Nothing to ask")
                .font(.headline)
            if let next = model.nextCheckIn() {
                Text("Next: \(next.habit.name), \(DayFormat.short(next.day, today: model.today))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top)
    }
}

/// "Delay…" on the wrist: a few fixed lengths. Backdating and vacations stay on the phone.
struct WatchDelaySheet: View {
    let question: Question
    @Environment(AppModel.self) private var model
    @Environment(ErrorPresenter.self) private var errors
    @Environment(\.dismiss) private var dismiss

    private static let lengths = [1, 3, 7, 14]

    var body: some View {
        List(Self.lengths, id: \.self) { days in
            Button(DayFormat.days(days)) {
                if errors.attempt({ try model.delay(question, days: days, reason: .manual) }) {
                    dismiss()
                }
            }
        }
        .navigationTitle("Delay")
    }
}
