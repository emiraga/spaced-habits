import HabitCore
import HabitUI
import SwiftUI

/// Every active habit with today's glyph (DESIGN.md §7).
struct WatchHabitsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(model.activeHabits) { habit in
            NavigationLink(value: habit.id) {
                HStack {
                    Text(model.todayStatus(of: habit.id).glyph)
                        .foregroundStyle(Color(hex: habit.colorHex))
                        .accessibilityLabel(model.todayStatus(of: habit.id).label)
                    Text(habit.displayName)
                }
            }
        }
        .overlay {
            if model.activeHabits.isEmpty {
                Text("Add habits on your iPhone.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Habits")
    }
}

/// A habit at a glance: the last 7 days, the ask interval and the next check-in.
struct WatchHabitView: View {
    let habitID: UUID
    @Environment(AppModel.self) private var model

    var body: some View {
        if let habit = model.habit(habitID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    strip(habit)
                    Text(DayFormat.askInterval(model.state(of: habitID).currentIntervalDays))
                        .font(.footnote)
                    if let resume = model.resumeDay(of: habitID) {
                        Text("Resumes \(DayFormat.short(resume, today: model.today))")
                            .font(.footnote)
                    } else if let next = model.nextCheckIn(of: habit) {
                        Text("Next check-in: \(DayFormat.checkIn(next, dueTime: habit.dueTime, today: model.today))")
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(habit.displayName)
        } else {
            Text("This habit no longer exists.")
        }
    }

    /// One glyph per day, oldest first, with the weekday's initial under it.
    private func strip(_ habit: Habit) -> some View {
        HStack(spacing: 4) {
            ForEach(model.recentStatuses(of: habit), id: \.day) { day, status in
                VStack(spacing: 2) {
                    Text(status.glyph)
                        .font(.body.monospaced())
                    Text(DayFormat.weekdayInitial(day))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(DayFormat.short(day, today: model.today)): \(status.label)")
            }
        }
    }
}
