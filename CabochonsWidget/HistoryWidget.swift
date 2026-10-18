import WidgetKit
internal import SwiftUI
import AppIntents

// MARK: - Entry

/// One render's worth of state. Everything precomputed here so the view body
/// stays dumb — widget bodies are snapshotted and shouldn't be doing work.
struct HistoryEntry: TimelineEntry {
    let date: Date
    let name: String?
    let color: CabochonsColor?
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
        color: CabochonsColor(hue: 0.38, saturation: 0.75, brightness: 0.9),
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

        // The only thing that changes without
        // an app write is the day rolling over, which adds a new empty socket.
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
                                .widgetAccentable()   // no-op in full colour; takes the tint when accented
                        }
                    }

                    // Month labels need horizontal room; the small widget
                    // spends it on orbs instead.
                    HistoryOrbGrid(
                        history: history,
                        color: color,
                        showsMonths: family != .systemSmall
                    )
                }
            } else {
                Text("Add an activity in Cabochons")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { Chrome.panel }
    }
}

// MARK: - Orb grid

/// The contribution grid drawn with the app's real jewels.
///
/// Same sizing rules as `HistoryGridView`: the cell size comes from the
/// height (seven rows always fit), then as many weeks as fit the width are
/// shown, newest at the trailing edge. But the cells are `CabochonsSocket` and
/// `CabochonsOrb` views rather than Canvas circles, so the widget reads like a
/// wall of the app's own sockets. Every cell is under `CabochonsOrb.liveThreshold`,
/// so they all take the static tier — no tilt, no blur passes.
///
/// Intensity: an empty day is a bare socket. A logged day is an orb sitting in
/// that socket, faded in from about half opacity at the day's lowest count to
/// solid at the busiest count in view. A dim orb in a socket reads as "some",
/// a bright one as "a lot", without inventing a new colour per level (which
/// `CabochonsColor`'s readability pass would flatten anyway).
struct HistoryOrbGrid: View {
    let history: ActivityHistory
    let color: CabochonsColor
    var showsMonths = true
    var maxCellSize: CGFloat = 12
    var gap: CGFloat = 2
    var calendar: Calendar = .current

    /// Home Screen tinting. `.accented` throws away colour and keeps only
    /// alpha, so the real socket and orb views are swapped for `TintedCell`.
    @Environment(\.widgetRenderingMode) private var renderingMode

    private static let labelBand: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let band = showsMonths ? Self.labelBand : 0
            let side = min(maxCellSize, (geo.size.height - band - gap * 6) / 7)
            let step = side + gap

            if side > 1 {
                let fit = max(1, Int((geo.size.width + gap) / step))
                let columns = Array(history.columns.suffix(fit))
                let gridWidth = CGFloat(columns.count) * step - gap
                let originX = geo.size.width - gridWidth   // newest week hugs the trailing edge

                ZStack(alignment: .topLeading) {
                    if showsMonths {
                        ForEach(monthLabels(for: columns), id: \.column) { label in
                            let x = originX + CGFloat(label.column) * step
                            if x + 20 <= geo.size.width {   // don't run off the edge
                                Text(label.day.formatted(.dateTime.month(.abbreviated)))
                                    .font(.system(size: 8, weight: .medium, design: .rounded))
                                    .foregroundStyle(Chrome.steelHi)
                                    .offset(x: x)
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: gap) {
                        ForEach(columns.indices, id: \.self) { c in
                            VStack(spacing: gap) {
                                ForEach(columns[c], id: \.day) { cell in
                                    self.cell(cell, side: side)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, band)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ cell: ActivityHistory.Cell, side: CGFloat) -> some View {
        if renderingMode == .accented {
            TintedCell(filled: cell.count > 0, intensity: intensity(for: cell.count), side: side)
        } else {
            ZStack {
                CabochonsSocket(size: side)
                if cell.count > 0 {
                    CabochonsOrb(color: color, size: side)
                        .opacity(intensity(for: cell.count))
                }
            }
            .frame(width: side, height: side)
        }
    }

    /// 0.5 at count 1, 1.0 at the busiest day shown. Four steps, like the
    /// Canvas ramp, so a grid of near-identical days doesn't shimmer with
    /// meaningless half-percent differences.
    private func intensity(for count: Int) -> Double {
        guard history.maxCount > 1 else { return 1 }
        let level = min(4, 1 + (count - 1) * 4 / history.maxCount)   // 1...4
        return 0.5 + Double(level - 1) * (0.5 / 3)
    }

    // MARK: Month labels

    private struct MonthLabel {
        let column: Int
        let day: Date
    }

    /// One label per column whose first day starts a new month, skipping the
    /// very first column unless it happens to start one — a label on a
    /// mid-month leading edge just says where the widget was cut.
    private func monthLabels(for columns: [[ActivityHistory.Cell]]) -> [MonthLabel] {
        var labels: [MonthLabel] = []
        var lastMonth: Int?
        for (c, column) in columns.enumerated() {
            guard let first = column.first else { continue }
            let month = calendar.component(.month, from: first.day)
            defer { lastMonth = month }
            guard let previous = lastMonth, previous != month else { continue }
            labels.append(MonthLabel(column: c, day: first.day))
        }
        return labels
    }
}

// MARK: - Tinted cell

/// One grid cell under Home Screen tinting.
///
/// Accented mode discards colour and keeps only alpha, so `CabochonsSocket`
/// (opaque well, opaque ring) and `CabochonsOrb` collapse into the same solid
/// disc — every day looked logged. Here the two states differ in shape, not
/// colour: a logged day is a solid disc marked accentable, so it takes the
/// user's tint and dims with intensity; an empty day is a thin ring left
/// unaccented, so the system draws it in its muted primary treatment.
private struct TintedCell: View {
    let filled: Bool
    let intensity: Double
    let side: CGFloat

    var body: some View {
        Group {
            if filled {
                Circle()
                    .fill(.white)            // colour is irrelevant here; only alpha survives
                    .opacity(intensity)
                    .widgetAccentable()
            } else {
                Circle()
                    .strokeBorder(.white.opacity(0.35), lineWidth: max(1, side * 0.1))
            }
        }
        .frame(width: side, height: side)
    }
}

// MARK: - Widget

struct HistoryWidget: Widget {
    let kind = "CabochonsHistoryWidget"

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
        .description("A year of jewels for one activity, one orb per day.")
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

// Flips the layout branch only. The actual colour-stripping happens in the
// system compositor, so this shows white discs and rings, not the tint —
// check the real thing on device with a tinted Home Screen.
#Preview("Accented (layout only)") {
    HistoryWidgetView(entry: .placeholder)
        .environment(\.widgetRenderingMode, .accented)
        .frame(width: 329, height: 155)
        .background(Chrome.panel)
        .preferredColorScheme(.dark)
}
#endif
