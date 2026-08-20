internal import SwiftUI

/// One activity in isolation. The combined day rail lives in `DayView`; this
/// screen is for when you want to look at a single habit's history.
struct ActivityDetailView: View {
    @Environment(LogStore.self) private var store
    let activityID: Activity.ID

    @State private var pulse = 0
    @State private var inspecting: PeriodSummary?
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
        }
        .sheet(isPresented: $editing) {
            if let activity {
                ActivityEditor(mode: .edit(activity)) { store.update($0) }
            }
        }
        .sheet(item: $inspecting) { period in
            PeriodEntriesSheet(
                period: period,
                title: store.calc.periodLabel(
                    index: period.index,
                    cadence: store.activity(activityID)?.cadence ?? .daily,
                    anchor: store.activity(activityID)?.createdAt ?? .now
                ),
                activityID: activityID
            )
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

    // MARK: This period's sockets

    private func slotPanel(activity: Activity, stats: ActivityStats) -> some View {
        let current = stats.current

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(periodTitle(stats))
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    if !stats.cadence.isDaily {
                        Text("\(stats.target) every \(stats.cadence.phrase)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(current?.count ?? 0)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(activity.color.core)
                    Text("/ \(stats.target)")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            SlotRail(
                count: current?.count ?? 0,
                color: activity.color,
                capacity: stats.target,
                size: 34
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: current?.count ?? 0)

            if let current, current.isMet {
                Label(
                    current.overflow > 0 ? "Mastered — \(current.overflow) over" : "Mastered",
                    systemImage: "star.fill"
                )
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Chrome.gold)
            } else if let current, !stats.cadence.isDaily {
                let days = max(0, store.calc.daysBetween(store.calc.today, current.end))
                Text("\(current.remaining) to go · \(days) \(days == 1 ? "day" : "days") left")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .panel()
    }

    private func periodTitle(_ stats: ActivityStats) -> String {
        guard let current = stats.current else { return "This period" }
        return store.calc.periodLabel(
            index: current.index,
            cadence: stats.cadence,
            anchor: activity?.createdAt ?? .now
        )
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
                StreakBadge(
                    streak: stats.currentStreak,
                    today: stats.currentCount,
                    accent: activity.color.core,
                    unit: stats.cadence.unit.label(count: 2)
                )

                Button {
                    store.removeLastToday(activity.id)
                } label: {
                    Label("Remove last", systemImage: "arrow.uturn.backward")
                        .font(.system(.callout, design: .rounded))
                }
                .buttonStyle(.bordered)
                .disabled(store.todayCount(for: activity) == 0)
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
            let unit = stats.cadence.unit.label(count: 2)
            StatTile(label: "Total", value: "\(stats.total)")
            StatTile(label: "Streak", value: "\(stats.currentStreak)", unit: unit)
            StatTile(label: "Longest", value: "\(stats.longestStreak)", unit: unit)
            StatTile(label: "Logged", value: "\(stats.periodsLogged)", unit: unit)
            StatTile(label: "Mastered", value: "\(stats.periodsMet)", unit: unit)
            StatTile(label: "Average", value: String(format: "%.1f", stats.average))
        }
        .panel()
    }

    // MARK: History

    private func history(activity: Activity, stats: ActivityStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(stats.cadence.isDaily ? "By day" : "By \(stats.cadence.phrase)")
                .font(.system(.headline, design: .rounded, weight: .semibold))

            if stats.periods.isEmpty {
                Text("Nothing logged yet. Press the orb.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(stats.periods) { period in
                        Button {
                            inspecting = period
                        } label: {
                            PeriodRow(
                                period: period,
                                label: store.calc.periodLabel(
                                    index: period.index,
                                    cadence: stats.cadence,
                                    anchor: activity.createdAt
                                ),
                                color: activity.color
                            )
                        }
                        .buttonStyle(.plain)

                        if period.id != stats.periods.last?.id {
                            Divider().overlay(Chrome.steel.opacity(0.25))
                        }
                    }
                }
            }
        }
        .panel()
    }
}

// MARK: - Period row

private struct PeriodRow: View {
    let period: PeriodSummary
    let label: String
    let color: MateriaColor

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                    if period.isMet {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Chrome.gold)
                    }
                }

                SlotRail(
                    count: period.count,
                    color: color,
                    capacity: period.target,
                    size: 14,
                    maxSlots: 20
                )
            }

            Spacer(minLength: 8)

            Text("\(period.count)")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(period.isMet ? Chrome.gold : .primary)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
