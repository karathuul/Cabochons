import WidgetKit
internal import SwiftUI
import AppIntents

// MARK: - Entry

/// One render's worth of state. Everything precomputed here so the view body
/// stays dumb — widget bodies are snapshotted and shouldn't be doing work.
struct HistoryEntry: TimelineEntry {
    let date: Date
    let name: String?
    let color: MateriaColor?
    let history: ActivityHistory?
    let streak: Int

    /// A year back. The view only draws as many weeks as fit, so building the
    /// full span costs nothing visible and means the same entry serves both
    /// families without knowing which one it's in.
    static let weeks = 53

    static func build(for activity: Activity?, file: LogFile, date: Date = .now) -> HistoryEntry {
        let calc = DayCalculator(dayStartHour: file.dayStartHour)
        guard let activity else {
            return HistoryEntry(date: date, name: nil, color: nil, history: nil, streak: 0)
        }
        return HistoryEntry(
            date: date,
            name: activity.name,
            color: activity.color,
            history: .build(for: activity, weeks: weeks, calc: calc),
            streak: Stats.compute(for: activity, calc: calc).currentStreak
        )
    }

    /// Gallery preview. Plausible rather than empty, so it doesn't look broken.
    static let placeholder = HistoryEntry(
        date: .now,
        name: "Practice",
        color: MateriaColor(hue: 0.38, saturation: 0.75, brightness: 0.9),
        history: .sample(weeks: weeks, calc: DayCalculator()),
        streak: 6
    )
}

// MARK: - Provider

struct HistoryProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> HistoryEntry {
        .placeholder
    }

    func snapshot(for configuration: HistoryWidgetConfiguration, in context: Context) async -> HistoryEntry {
        guard !context.isPreview else { return .placeholder }
        let file = SharedStorage.load()
        return .build(for: resolve(configuration, in: file), file: file)
    }

    func timeline(for configuration: HistoryWidgetConfiguration, in context: Context) async -> Timeline<HistoryEntry> {
        let file = SharedStorage.load()
        let entry = HistoryEntry.build(for: resolve(configuration, in: file), file: file)

        // Same policy as the Today widget: the only thing that changes without
        // an app write is the day rolling over, which adds a new empty square.
        let calc = DayCalculator(dayStartHour: file.dayStartHour)
        let nextDay = calc.offsetting(calc.today, by: 1)
        let refresh = max(nextDay, entry.date.addingTimeInterval(60 * 60))

        return Timeline(entries: [entry], policy: .after(refresh))
    }

    /// The configured activity if it still exists, else the first visible
    /// one, else nothing. Deleted activities fall through to the fallback
    /// rather than freezing the widget on stale data.
    private func resolve(_ configuration: HistoryWidgetConfiguration, in file: LogFile) -> Activity? {
        if let id = configuration.activity?.id,
           let match = file.activities.first(where: { $0.id == id }) {
            return match
        }
        return file.activities.first { !$0.isHidden }
    }
}

// MARK: - Views

struct HistoryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HistoryEntry

    var body: some View {
        Group {
            if let history = entry.history, let color = entry.color {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(entry.name ?? "")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if entry.streak > 0 {
                            Label("\(entry.streak)", systemImage: "flame.fill")
                                .font(.system(.caption2, design: .rounded, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(Chrome.gold)
                        }
                    }

                    // Month labels need horizontal room; the small widget
                    // spends it on squares instead.
                    HistoryGridView(
                        history: history,
                        color: color,
                        showsMonths: family != .systemSmall
                    )
                }
            } else {
                Text("Add an activity in MateriaLog")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { Chrome.panel }
    }
}

// MARK: - Widget

struct HistoryWidget: Widget {
    let kind = "MateriaHistoryWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: HistoryWidgetConfiguration.self,
            provider: HistoryProvider()
        ) { entry in
            HistoryWidgetView(entry: entry)
                .preferredColorScheme(.dark)
        }
        .configurationDisplayName("History")
        .description("A year of jewels for one activity, one square per day.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#if DEBUG
#Preview("Medium", as: .systemMedium) {
    HistoryWidget()
} timeline: {
    HistoryEntry.placeholder
}

#Preview("Small", as: .systemSmall) {
    HistoryWidget()
} timeline: {
    HistoryEntry.placeholder
}
#endif
