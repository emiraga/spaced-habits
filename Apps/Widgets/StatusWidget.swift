import HabitUI
import SwiftUI
import WidgetKit

/// Every habit with today's glyph (DESIGN.md §6); a row opens the habit's detail. On the Lock Screen and
/// as a watch complication, how many habits are due.
struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StatusWidget", provider: SnapshotProvider()) { entry in
            StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Your habits and today's status.")
        #if os(watchOS)
            // Complications (§6).
            .supportedFamilies([.accessoryCircular, .accessoryInline])
        #else
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline])
        #endif
    }
}

struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(DeepLink.today.url)
    }

    @ViewBuilder private var content: some View {
        let snapshot = entry.snapshot
        switch family {
        case .accessoryInline:
            Text(snapshot.dueCount == 0 ? "All caught up" : "\(snapshot.dueCount) habits due")
        case .accessoryCircular:
            if snapshot.dueCount == 0 {
                BrandMark().padding(6).accessibilityElement().accessibilityLabel("All caught up")
            } else {
                VStack(spacing: 0) {
                    Text("\(snapshot.dueCount)").font(.title2.bold())
                    Text("due").font(.caption2)
                }
            }
        default:
            if let failure = entry.failure {
                Text(failure).font(.caption)
            } else {
                list(snapshot.habits.prefix(family.isSystemSmall ? 5 : 6))
            }
        }
    }

    private func list(_ rows: ArraySlice<WidgetSnapshot.Row>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if rows.isEmpty {
                Text("No habits yet").font(.caption)
            }
            ForEach(rows) { row in
                Link(destination: DeepLink.habit(row.id).url) {
                    HStack(spacing: 6) {
                        Text(row.status.glyph)
                            .foregroundStyle(Color(hex: row.colorHex))
                            .accessibilityLabel(row.status.label)
                        Text(row.title).lineLimit(1)
                    }
                    .font(.caption)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
