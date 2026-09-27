import HabitCore
import HabitUI
import SwiftUI

/// Question cards, then every habit with today's glyph (DESIGN.md §5.1).
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(ErrorPresenter.self) private var errors
    @Environment(Notifier.self) private var notifier
    @State private var editingDraft: Habit?
    @State private var showingSettings = false
    @State private var showingVacation = false
    @State private var delaying: Question?
    @State private var answers = 0

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let vacation = model.currentVacation {
                    vacationBanner(vacation)
                }
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Vacation", systemImage: "beach.umbrella") { showingVacation = true }
                    .disabled(model.activeHabits.isEmpty)
                Button("Add habit", systemImage: "plus") { editingDraft = model.newHabitDraft() }
            }
        }
        .sheet(item: $editingDraft) { draft in
            NavigationStack { HabitEditorView(habit: draft, isNew: true) }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack { SettingsView() }
        }
        .sheet(isPresented: $showingVacation) {
            NavigationStack { VacationSheet() }
        }
        .sheet(item: Binding(
            get: { notifier.vacationAfter.map(NudgedVacation.init) },
            set: { notifier.vacationAfter = $0?.after }
        )) { nudged in
            NavigationStack { VacationSheet(after: nudged.after) }
        }
        .sheet(item: $delaying) { question in
            if let habit = model.habit(question.habitID) {
                NavigationStack { PauseSheet(habit: habit, origin: .card(question), today: model.today) }
            }
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
                parentNames: model.parentNames(for: question),
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
                onDelay: { delaying = question },
                onLater: { withAnimation { _ = errors.attempt { try model.later(question) } } }
            )
            .id(question.id)
            .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
        }
    }

    private func vacationBanner(_ vacation: PauseEvent) -> some View {
        let today = model.today
        let text = vacation.start <= today
            ? "On vacation until \(DayFormat.short(vacation.end, today: today))"
            : "Vacation \(DayFormat.range(vacation.start, vacation.end, today: today))"
        return Button { showingVacation = true } label: {
            Label(text, systemImage: "beach.umbrella")
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .padding(.horizontal)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
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

    /// One group per cluster, then habits in none ("Habits", or "Other" when there are clusters).
    private var habitList: some View {
        let groups = model.habitsByCluster
        return ForEach(groups, id: \.cluster?.id) { group in
            habitGroup(
                title: group.cluster?.name ?? (groups.count > 1 ? "Other" : "Habits"),
                habits: group.habits
            )
        }
    }

    private func habitGroup(title: String, habits: [Habit]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding(.vertical, 8)
            ForEach(habits) { habit in
                NavigationLink(value: habit.id) {
                    HabitRow(
                        habit: habit,
                        status: model.todayStatus(of: habit.id),
                        intervalDays: model.state(of: habit.id).currentIntervalDays,
                        resumes: model.resumeDay(of: habit.id).map { DayFormat.short($0, today: model.today) }
                    )
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }
}

/// `sheet(item:)` needs `Identifiable`.
private struct NudgedVacation: Identifiable {
    let after: DayKey
    var id: DayKey {
        after
    }
}

private struct HabitRow: View {
    let habit: Habit
    let status: DayStatus
    let intervalDays: Int
    /// "Resumes <day>" replaces the ask interval while the habit is paused (§4.6).
    let resumes: String?

    var body: some View {
        HStack(spacing: 12) {
            Text(status.glyph)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(Color(hex: habit.colorHex))
            Text([habit.emoji, habit.name].compactMap(\.self).joined(separator: " "))
            Spacer()
            Text(resumes.map { "Resumes \($0)" } ?? "~\(intervalDays)d")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(habit.name), \(status.label), \(resumes.map { "resumes \($0)" } ?? DayFormat.askInterval(intervalDays))"
        )
    }
}
