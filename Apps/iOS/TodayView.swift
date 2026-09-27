import HabitCore
import HabitUI
import SwiftUI

/// Question cards, then every habit with today's glyph (DESIGN.md §5.1).
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(ErrorPresenter.self) private var errors
    @State private var editingDraft: Habit?
    @State private var showingSettings = false
    @State private var showingDelayNotice = false
    @State private var answers = 0

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if model.questions.isEmpty {
                    emptyState
                }
                ForEach(model.questions) { question in
                    card(for: question)
                }
                if model.queuedCount > 0 {
                    Button("More… (\(model.queuedCount) more due)") {
                        withAnimation { _ = errors.attempt { try model.showMore() } }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                if !model.activeHabits.isEmpty {
                    habitList
                }
            }
            .padding()
        }
        .refreshable { errors.attempt { try model.startSession() } }
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") { showingSettings = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add habit", systemImage: "plus") { editingDraft = model.newHabitDraft() }
            }
        }
        .sheet(item: $editingDraft) { draft in
            NavigationStack { HabitEditorView(habit: draft, isNew: true) }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack { SettingsView() }
        }
        .alert("Delay", isPresented: $showingDelayNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Delaying a habit is coming soon. Use Later to skip it for now.")
        }
        .sensoryFeedback(.success, trigger: answers)
        .onAppear { LaunchMetrics.firstScreenAppeared() }
    }

    @ViewBuilder
    private func card(for question: Question) -> some View {
        if let habit = model.habit(question.habitID) {
            let state = model.state(of: habit.id)
            QuestionCard(
                question: question,
                habit: habit,
                intervalDays: state.currentIntervalDays,
                guess: state.adherence.mean,
                today: model.today,
                onAnswer: { value in
                    withAnimation {
                        if errors.attempt({ try model.answer(question, with: value) }) {
                            answers += 1
                        }
                    }
                },
                onDelay: { showingDelayNotice = true },
                onLater: { withAnimation { _ = errors.attempt { try model.later(question) } } }
            )
            .id(question.id)
            .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
        }
    }

    @ViewBuilder private var emptyState: some View {
        if model.activeHabits.isEmpty {
            ContentUnavailableView {
                Label("No habits yet", systemImage: "leaf")
            } description: {
                Text("Add a habit and Spaced Habits will ask about it only as often as it needs to.")
            } actions: {
                Button("Add habit") { editingDraft = model.newHabitDraft() }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing to ask.")
                    .font(.title3.weight(.semibold))
                if let next = model.nextCheckIn() {
                    Text("Next check-in: \(next.habit.name) on \(DayFormat.short(next.day, today: model.today)).")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var habitList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Habits")
                .font(.headline)
                .padding(.vertical, 8)
            ForEach(model.activeHabits) { habit in
                NavigationLink(value: habit.id) {
                    HabitRow(
                        habit: habit,
                        status: model.todayStatus(of: habit.id),
                        intervalDays: model.state(of: habit.id).currentIntervalDays
                    )
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }
}

private struct HabitRow: View {
    let habit: Habit
    let status: DayStatus
    let intervalDays: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(status.glyph)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(Color(hex: habit.colorHex))
            Text([habit.emoji, habit.name].compactMap(\.self).joined(separator: " "))
            Spacer()
            Text("~\(intervalDays)d")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(habit.name), \(status.label), \(DayFormat.askInterval(intervalDays))")
    }
}
