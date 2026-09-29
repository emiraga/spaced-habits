import AppIntents
import HabitUI
import SwiftUI
import WidgetKit

/// The top question with Yes / No (DESIGN.md §6): small, Lock Screen and the watch's Smart Stack show one,
/// medium two. Per-day and count questions need the card, so they open the app.
struct QuestionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuestionWidget", provider: SnapshotProvider()) { entry in
            QuestionWidgetView(entry: entry)
        }
        .configurationDisplayName("Check-in")
        .description("Answer the next question without opening the app.")
        #if os(watchOS)
            // The Smart Stack card (§6).
            .supportedFamilies([.accessoryRectangular])
        #else
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
        #endif
    }
}

struct QuestionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(DeepLink.today.url)
    }

    @ViewBuilder private var content: some View {
        let snapshot = entry.snapshot
        if let failure = entry.failure {
            Text(failure).font(.caption)
        } else if snapshot.cards.isEmpty {
            NothingDue(nextCheckIn: snapshot.nextCheckIn)
        } else if family.isSystemMedium {
            HStack(alignment: .top, spacing: 12) {
                ForEach(snapshot.cards.prefix(2)) { CardView(card: $0, compact: false) }
            }
        } else {
            CardView(card: snapshot.cards[0], compact: family == .accessoryRectangular)
        }
    }
}

private struct CardView: View {
    let card: WidgetSnapshot.Card
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 6) {
            Text(card.title)
                .font(compact ? .headline : .subheadline.bold())
                .foregroundStyle(compact ? Color.primary : Color(hex: card.colorHex))
                .lineLimit(1)
            if compact, let dayLabel = card.dayLabel {
                // Too small for the prompt: say which day Yes / No answers (§4.2).
                Text(dayLabel).font(.caption).foregroundStyle(.secondary)
            }
            if !compact {
                Text(card.body)
                    .font(.caption)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
            if card.isYesNo {
                HStack(spacing: 6) {
                    answerButton("Yes", done: true)
                    answerButton("No", done: false)
                }
            } else {
                Text("Open to answer").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func answerButton(_ title: LocalizedStringKey, done: Bool) -> some View {
        Button(intent: AnswerHabitIntent(habitID: card.id, day: card.day, done: done)) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(done ? Color(hex: card.colorHex) : .secondary)
        .controlSize(compact ? .mini : .regular)
    }
}

private struct NothingDue: View {
    let nextCheckIn: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text("Nothing to ask")
            } icon: {
                BrandMark().frame(width: 22, height: 22)
            }
            .font(.subheadline.bold())
            if let nextCheckIn {
                Text("Next: \(nextCheckIn)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
