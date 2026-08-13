internal import SwiftUI

struct ActivityDetailView: View {
    @Environment(LogStore.self) private var store
    let activityID: Activity.ID

    @State private var pulse = 0
    @State private var inspecting: DaySummary?
    @State private var editing = false

    private var activity: Activity? { store.activity(activityID) }

    var body: some View {
        Group {
            if let activity {
                content(for: activity)
            } else {
                Color.clear
            }
        }
        .background(Chrome.panel.ignoresSafeArea())
        .navigationTitle(activity?.name ?? "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = true
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                }
            }
            ToolbarItem {
                ShareLink(item: store.exportCSV()) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $editing) {
            if let activity {
                ActivityEditor(mode: .edit(activity)) { store.update($0) }
            }
        }
        .sheet(item: $inspecting) { summary in
            if let activity {
                DayDetailSheet(activity: activity, summary: summary)
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(for activity: Activity) -> some View {
        let stats = store.stats(for: activity)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                slotPanel(activity: activity, stats: stats)
                tapRow(activity: activity, stats: stats)
                statsPanel(stats)
                history(activity: activity, stats: stats)
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: pulse)
    }

    // MARK: Today's sockets

    private func slotPanel(activity: Activity, stats: ActivityStats) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(.system(.headline, design: .rounded, weight: .semibold))

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(stats.today)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(activity.color.core)
                    Text("/ \(activity.dailyTarget)")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            SlotRail(
                filled: stats.today,
                capacity: activity.dailyTarget,
                color: activity.color,
                size: 34
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: stats.today)

            if stats.today >= activity.dailyTarget, activity.dailyTarget > 0 {
                Label(
                    stats.today > activity.dailyTarget
                        ? "Mastered — \(stats.today - activity.dailyTarget) over"
                        : "Mastered",
                    systemImage: "star.fill"
                )
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Chrome.gold)
            }
        }
        .panel()
    }

    // MARK: The button

    private func tapRow(activity: Activity, stats: ActivityStats) -> some View {
        HStack(spacing: 18) {
            Button {
                store.slot(activity.id)
                pulse += 1
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [activity.color.core.opacity(0.22), .clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: 76
                            )
                        )
                        .frame(width: 152, height: 152)

                    MateriaOrb(color: activity.color, size: 108, glow: 1.3)

                    Image(systemName: "plus")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.5), radius: 3)
                }
            }
            .buttonStyle(OrbButtonStyle())
            .accessibilityLabel("Slot a jewel for \(activity.name)")

            VStack(alignment: .leading, spacing: 10) {
                StreakBadge(stats: stats, color: activity.color)

                Button {
                    store.removeLastToday(activity.id)
                } label: {
                    Label("Remove last", systemImage: "arrow.uturn.backward")
                        .font(.system(.callout, design: .rounded))
                }
                .buttonStyle(.bordered)
                .disabled(stats.today == 0)
            }

            Spacer(minLength: 0)
        }
        .panel(padding: 20)
    }

    // MARK: Numbers

    private func statsPanel(_ stats: ActivityStats) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 108), spacing: 12)],
            alignment: .leading,
            spacing: 14
        ) {
            StatTile(label: "Total", value: "\(stats.total)")
            StatTile(label: "Streak", value: "\(stats.currentStreak)", unit: "days")
            StatTile(label: "Longest", value: "\(stats.longestStreak)", unit: "days")
            StatTile(label: "Days logged", value: "\(stats.daysLogged)")
            StatTile(label: "Mastered", value: "\(stats.masteredDays)", unit: "days")
            StatTile(label: "Per day", value: String(format: "%.1f", stats.average))
        }
        .panel()
    }

    // MARK: History

    @ViewBuilder
    private func history(activity: Activity, stats: ActivityStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By day")
                .font(.system(.headline, design: .rounded, weight: .semibold))

            if stats.days.isEmpty {
                Text("Nothing logged yet. Press the orb.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(stats.days) { summary in
                        Button {
                            inspecting = summary
                        } label: {
                            DayRow(summary: summary, color: activity.color, calc: store.calc)
                        }
                        .buttonStyle(.plain)

                        if summary.id != stats.days.last?.id {
                            Divider().overlay(Chrome.steel.opacity(0.25))
                        }
                    }
                }
            }
        }
        .panel()
    }
}

// MARK: - Streak badge

private struct StreakBadge: View {
    let stats: ActivityStats
    let color: MateriaColor

    var body: some View {
        let atRisk = Stats.streakAtRisk(stats)

        HStack(spacing: 8) {
            Image(systemName: stats.currentStreak > 0 ? "flame.fill" : "flame")
                .font(.title3)
                .foregroundStyle(atRisk ? Chrome.steelHi : color.core)

            VStack(alignment: .leading, spacing: 0) {
                Text("\(stats.currentStreak)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(streakCaption(atRisk: atRisk))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func streakCaption(atRisk: Bool) -> String {
        if stats.currentStreak == 0 { return "no streak" }
        return atRisk ? "day streak — nothing today yet" : "day streak"
    }
}

// MARK: - Stat tile

private struct StatTile: View {
    let label: String
    let value: String
    var unit: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Day row

private struct DayRow: View {
    let summary: DaySummary
    let color: MateriaColor
    let calc: DayCalculator

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(calc.label(for: summary.day))
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                    if summary.isMastered {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Chrome.gold)
                    }
                }
                SlotRail(
                    filled: summary.count,
                    capacity: summary.target,
                    color: color,
                    size: 14,
                    maxSlots: 20
                )
            }

            Spacer(minLength: 8)

            Text("\(summary.count)")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(summary.isMastered ? Chrome.gold : .primary)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
