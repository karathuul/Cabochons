import WidgetKit
internal import SwiftUI

/// Routes each widget family to a view built for it. Both families get the full
/// gunmetal-and-orb treatment.
struct CabochonsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CabochonsEntry

    var body: some View {
        switch family {
        case .systemSmall:  SmallHomeView(entry: entry)
        case .systemMedium: MediumHomeView(entry: entry)
        default:            SmallHomeView(entry: entry)
        }
    }
}

// MARK: - Home Screen

private struct SmallHomeView: View {
    let entry: CabochonsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Spacer()
                if entry.streak > 0 {
                    Label("\(entry.streak)", systemImage: "flame.fill")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(Chrome.gold)
                        .labelStyle(.titleAndIcon)
                }
            }

            Spacer(minLength: 0)

            if entry.hasActivities {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(entry.todayCount)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(entry.isMastered ? Chrome.gold : .white)
                    if entry.capacity > 0 {
                        Text("/ \(entry.capacity)")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                SlotRail(fills: entry.fills, capacity: entry.capacity, size: 15, maxSlots: 8)
            } else {
                Text("No activities")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { Chrome.panel }
    }
}

private struct MediumHomeView: View {
    let entry: CabochonsEntry

    private var lines: [PeriodProgress] { Array(entry.progress.prefix(4)) }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Today")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(entry.todayCount)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(entry.isMastered ? Chrome.gold : .white)
                    if entry.capacity > 0 {
                        Text("/ \(entry.capacity)")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                if entry.streak > 0 {
                    Label("\(entry.streak) day streak", systemImage: "flame.fill")
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(Chrome.gold)
                }

                Spacer(minLength: 0)
            }
            .frame(width: 96, alignment: .leading)

            if lines.isEmpty {
                emptyColumn
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(lines) { line in
                        ActivityLineView(line: line)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { Chrome.panel }
    }

    private var emptyColumn: some View {
        VStack {
            Spacer()
            Text(entry.hasActivities ? "Nothing due" : "No activities")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ActivityLineView: View {
    let line: PeriodProgress

    var body: some View {
        HStack(spacing: 8) {
            CabochonsOrb(color: line.color, size: 16, glow: 0.5)

            Text(line.name)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 4)

            Text("\(line.count)/\(line.target)")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(line.isMet ? Chrome.gold : .secondary)
        }
    }
}
