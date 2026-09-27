import HabitCore
import HabitUI
import SwiftUI

/// First launch (DESIGN.md §5.1 screen 0): the idea, a first habit, notifications. Shown once per device,
/// and only while there is no data: habits synced from iCloud or imported skip it.
struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(Notifier.self) private var notifier
    @Environment(ErrorPresenter.self) private var errors

    @State private var page = Page.idea
    @State private var name = ""

    enum Page: Int, CaseIterable {
        case idea, firstHabit, notifications
    }

    /// `UserDefaults` key: set when the last page is left (per device, not synced).
    static let completedKey = "onboarding.completed"

    static func isNeeded(defaults: UserDefaults, habits: [Habit]) -> Bool {
        !defaults.bool(forKey: completedKey) && habits.isEmpty
    }

    var body: some View {
        // One page at a time, moved by its buttons, without a transition (nothing moves with Reduce Motion
        // either): a paged TabView would let a swipe skip a step, and keeps the neighboring pages in the
        // accessibility tree.
        Group {
            switch page {
            case .idea: idea
            case .firstHabit: firstHabit
            case .notifications: notifications
            }
        }
        .safeAreaInset(edge: .bottom) { PageDots(current: page) }
        .interactiveDismissDisabled()
    }

    // MARK: Pages

    private var idea: some View {
        OnboardingPage {
            Image("LogoMark")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)
            Text("Spaced Habits")
                .font(.largeTitle.bold())
            Text("The habit tracker that asks less the better you do.")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 20) {
                Point(
                    "A few quick questions", systemImage: "questionmark.bubble",
                    detail: "Answer a handful of check-ins, then you're done for the day."
                )
                Point(
                    "Asks less as you improve", systemImage: "chart.line.uptrend.xyaxis",
                    detail: "Habits you keep come up less and less often. The growing gap is your progress."
                )
                Point(
                    "Honest history", systemImage: "checkmark.seal",
                    detail: "Answers, counts and estimates always look different. No fake streaks."
                )
            }
            .padding(.top)
        } actions: {
            primary("Continue") { go(to: .firstHabit) }
        }
    }

    private var firstHabit: some View {
        OnboardingPage {
            Text("Add your first habit")
                .font(.largeTitle.bold())
            Text("Something you'd like to do most days. You can add more, and connect habits, later.")
                .foregroundStyle(.secondary)
            TextField("Habit name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .submitLabel(.done)
                .onSubmit(addHabit)
            FlowingSuggestions(suggestions: Self.suggestions) { name = $0.name }
        } actions: {
            primary("Add habit", action: addHabit)
                .disabled(trimmedName.isEmpty)
                // Today's "Add habit" is behind the cover.
                .accessibilityIdentifier("onboarding.addHabit")
            secondary("Skip") { go(to: .notifications) }
        }
    }

    private var notifications: some View {
        OnboardingPage {
            Image(systemName: "bell.badge")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("Check-ins come to you")
                .font(.largeTitle.bold())
            Text(
                "A reminder arrives only when there's something to answer, and you can reply Yes or No right from the notification. Quiet hours are respected."
            )
            .foregroundStyle(.secondary)
            Text("Change times and quiet hours any time in Settings.")
                .foregroundStyle(.secondary)
        } actions: {
            primary("Allow notifications") {
                Task {
                    await errors.attemptAsync { try await notifier.requestAuthorization() }
                    onFinish()
                }
            }
            secondary("Not now", action: onFinish)
        }
    }

    // MARK: Actions

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addHabit() {
        guard !trimmedName.isEmpty else { return }
        var habit = model.newHabitDraft()
        habit.name = trimmedName
        // A suggestion's emoji, unless its name was edited.
        habit.emoji = Self.suggestions.first { $0.name == trimmedName }?.emoji
        if errors.attempt({ try model.save(habit) }) {
            go(to: .notifications)
        }
    }

    private func go(to next: Page) {
        page = next
        // VoiceOver starts reading the new page from the top.
        AccessibilityNotification.ScreenChanged(nil).post()
    }

    private func primary(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
    }

    private func secondary(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    // MARK: Suggestions

    struct Suggestion: Hashable {
        let name: String
        let emoji: String
    }

    static let suggestions = [
        Suggestion(name: String(localized: "Exercise"), emoji: "🏃"),
        Suggestion(name: String(localized: "Read"), emoji: "📚"),
        Suggestion(name: String(localized: "Meditate"), emoji: "🧘"),
        Suggestion(name: String(localized: "Drink water"), emoji: "💧"),
        Suggestion(name: String(localized: "Journal"), emoji: "✍️"),
        Suggestion(name: String(localized: "Stretch"), emoji: "🤸"),
    ]
}

/// Where in onboarding the user is.
private struct PageDots: View {
    let current: OnboardingView.Page

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingView.Page.allCases, id: \.self) { page in
                Circle()
                    .fill(page == current ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement()
        .accessibilityLabel(Text("Step \(current.rawValue + 1) of \(OnboardingView.Page.allCases.count)"))
    }
}

/// A scrollable page, so large Dynamic Type never clips, with its buttons pinned above the page dots.
private struct OnboardingPage<Content: View, Actions: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .padding(.top, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) { actions }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .background(.background)
        }
    }
}

/// A feature line on the first page: symbol, title, one sentence.
private struct Point: View {
    let title: LocalizedStringKey
    let systemImage: String
    let detail: LocalizedStringKey

    init(_ title: LocalizedStringKey, systemImage: String, detail: LocalizedStringKey) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Suggestion chips that wrap onto as many lines as the text size needs.
private struct FlowingSuggestions: View {
    let suggestions: [OnboardingView.Suggestion]
    let onPick: (OnboardingView.Suggestion) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button("\(suggestion.emoji) \(suggestion.name)") { onPick(suggestion) }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(suggestion.name)
                    .accessibilityHint(Text("Fills in the name"))
            }
        }
    }
}
