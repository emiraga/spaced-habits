import HabitCore
import HabitUI
import SwiftUI

/// Question cards, then every habit with today's glyph (DESIGN.md §5.1).
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(ErrorPresenter.self) private var errors
    @Environment(Notifier.self) private var notifier
    @State private var editingDraft: Habit?
    /// Long-press menu targets (§5.1).
    @State private var editingHabit: Habit?
    @State private var pausingHabit: Habit?
    @State private var deletingHabit: Habit?
    @State private var showingSettings = false
    @State private var showingVacation = false
    @State private var delaying: Question?
    @State private var answers = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .safeAreaInset(edge: .bottom) { undoBar }
        .navigationTitle("Today")
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") { showingSettings = true }
                NavigationLink(value: InsightsDestination()) {
                    Label("Insights", systemImage: "chart.line.uptrend.xyaxis")
                }
                .disabled(model.activeHabits.isEmpty)
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
        .sheet(item: $editingHabit) { habit in
            NavigationStack { HabitEditorView(habit: habit, isNew: false) }
        }
        .sheet(item: $pausingHabit) { habit in
            NavigationStack { PauseSheet(habit: habit, origin: .detail, today: model.today) }
        }
        .confirmingDeletion(of: $deletingHabit)
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
        if let card = model.card(
            for: question,
            onAnswer: { value in
                withAnimation {
                    if errors.attempt({ try model.answer(question, with: value) }) {
                        answers += 1
                    }
                }
            },
            onDelay: { delaying = question },
            onLater: { withAnimation { _ = errors.attempt { try model.later(question) } } }
        ) {
            card
                .id(question.id)
                .transition(Self.cardTransition(reduceMotion: reduceMotion))
        }
    }

    /// Answered cards slide away; with Reduce Motion they only fade (§5.2).
    static func cardTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity))
    }

    private func vacationBanner(_ vacation: PauseEvent) -> some View {
        let today = model.today
        let text = vacation.start <= today
            ? String(localized: "On vacation until \(DayFormat.short(vacation.end, today: today))")
            : String(localized: "Vacation \(DayFormat.range(vacation.start, vacation.end, today: today))")
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
                    Text("Next check-in: \(next.habit.name), \(DayFormat.short(next.day, today: model.today)).")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    /// One group per cluster, then habits in none ("Habits", or "Other" when there are clusters). Habits
    /// are dragged within their group and cluster headers among the clusters (§5.1).
    private var habitList: some View {
        let groups = model.habitsByCluster
        return ForEach(groups, id: \.cluster?.id) { group in
            habitGroup(group.cluster, habits: group.habits, isOnlyGroup: groups.count == 1)
        }
    }

    private func habitGroup(_ cluster: Cluster?, habits: [Habit], isOnlyGroup: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            groupHeader(cluster, isOnlyGroup: isOnlyGroup)
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
                .contextMenu {
                    HabitMenu(
                        habit: habit,
                        onEdit: { editingHabit = habit },
                        onPause: { pausingHabit = habit },
                        onDelete: { deletingHabit = habit }
                    )
                }
                .reorderable(TodayDrag(kind: .habit, id: habit.id)) { moved in
                    errors.attempt { try model.move(habit: moved, to: habit.id) }
                }
                Divider()
            }
        }
    }
}

extension TodayView {
    /// "Answered Gym · Undo" for 5 s after a card is answered (§5.2); a newer answer restarts the time.
    @ViewBuilder private var undoBar: some View {
        if let answered = model.lastAnswered, let habit = model.habit(answered.habitID) {
            HStack {
                Text("Answered \(habit.displayName)")
                    .lineLimit(1)
                Spacer()
                Button("Undo") {
                    withAnimation { _ = errors.attempt { try model.undoLastAnswer() } }
                }
                .fontWeight(.semibold)
                .frame(minHeight: 44)
            }
            .padding(.horizontal)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding()
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: answered) {
                // Nil when cancelled: the bar went away or a newer answer restarted the time.
                guard await (try? Task.sleep(for: .seconds(5))) != nil else { return }
                withAnimation { model.dismissUndo() }
            }
        }
    }

    @ViewBuilder
    private func groupHeader(_ cluster: Cluster?, isOnlyGroup: Bool) -> some View {
        if let cluster {
            header(cluster.name)
                .reorderable(TodayDrag(kind: .cluster, id: cluster.id)) { moved in
                    errors.attempt { try model.move(cluster: moved, to: cluster.id) }
                }
        } else {
            header(isOnlyGroup ? String(localized: "Habits") : String(localized: "Other"))
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityAddTraits(.isHeader)
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
            Text(habit.displayName)
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
