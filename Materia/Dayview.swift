internal import SwiftUI

/// The day-centric screen. Every jewel earned today sits on one rail in the
/// order it was earned, colour-coded by activity.
struct DayView: View {
    @Environment(LogStore.self) private var store


    @State private var pulse = 0
    @State private var inspecting: CombinedDay?
    @State private var noting: LoggedJewel?

    var body: some View {
        let stats = store.combined

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                todayPanel(stats)
                loadout(stats)
                duePanel(stats)
                statsPanel(stats)
                history(stats)
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Chrome.panel.ignoresSafeArea())
        .navigationTitle("Today")
        .sensoryFeedback(.impact(weight: .medium), trigger: pulse)
        .toolbar {
            ToolbarItem {
                ShareLink(item: store.exportCSV()) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $inspecting) { day in
            DayEntriesSheet(day: day.day, capacity: day.capacity)
        }
        .sheet(item: $noting) { entry in
            NoteEditor(entry: entry)
        }
    }

    // MARK: The one rail

    private func todayPanel(_ stats: CombinedStats) -> some View {
        let fills = stats.today?.fills ?? []

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(store.calc.label(for: store.calc.today))
                    .font(.system(.headline, design: .rounded, weight: .semibold))

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(fills.count)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    if stats.capacity > 0 {
                        Text("/ \(stats.capacity)")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if store.visibleActivities.isEmpty && fills.isEmpty {
                Text(store.activities.isEmpty
                     ? "Create an activity and its jewels will land here."
                     : "Everything's hidden. Unhide one from the sidebar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if fills.isEmpty && stats.capacity == 0 {
                // Nothing daily is due and nothing's been logged, so there are
                // no sockets to draw. Everything lives in the period list below.
                Text("Nothing logged today.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                SlotRail(fills: fills, capacity: stats.capacity, size: 34)
                    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: fills)

                if let today = stats.today, today.isMastered {
                    Label(
                        today.overflow > 0 ? "Mastered — \(today.overflow) over" : "Mastered",
                        systemImage: "star.fill"
                    )
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Chrome.gold)
                }
            }
        }
        .panel()
    }

    // MARK: Every button in one place

    @ViewBuilder
    private func loadout(_ stats: CombinedStats) -> some View {
        if !store.visibleActivities.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Slot a jewel")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Spacer()
                    Button {
                        noting = store.mostRecentToday
                    } label: {
                        Label("Note", systemImage: "square.and.pencil")
                            .font(.system(.caption, design: .rounded))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(.bordered)
                    .disabled(stats.todayCount == 0)

                    Button {
                        store.removeLastToday()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.system(.caption, design: .rounded))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(.bordered)
                    .disabled(stats.todayCount == 0)
                }

                // Doubles as the rail's legend — this is where you learn which
                // colour belongs to which activity.
                FlowLayout(spacing: 18, lineSpacing: 16) {
                    ForEach(store.visibleActivities) { activity in
                        ActivityButton(activity: activity) {
                            store.slot(activity.id)
                            pulse += 1
                        } logAndNote: {
                            store.slot(activity.id)
                            pulse += 1
                            noting = store.mostRecentToday
                        }
                    }
                }

                StreakBadge(
                    streak: stats.currentStreak,
                    today: stats.todayCount,
                    accent: store.visibleActivities.first?.color.core ?? Chrome.steelHi
                )
                .padding(.top, 2)
            }
            .panel()
        }
    }

    // MARK: Where each activity stands

    /// Carries the weight for non-daily activities. A day rail can't say
    /// anything useful about a monthly commitment, so this does.
    @ViewBuilder
    private func duePanel(_ stats: CombinedStats) -> some View {
        let outstanding = stats.progress.filter { !$0.cadence.isDaily }

        if !outstanding.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("This period")
                    .font(.system(.headline, design: .rounded, weight: .semibold))

                LazyVStack(spacing: 0) {
                    ForEach(outstanding) { item in
                        ProgressRow(item: item)

                        if item.id != outstanding.last?.id {
                            Divider().overlay(Chrome.steel.opacity(0.25))
                        }
                    }
                }
            }
            .panel()
        }
    }

    // MARK: Numbers

    private func statsPanel(_ stats: CombinedStats) -> some View {
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

    private func history(_ stats: CombinedStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By day")
                .font(.system(.headline, design: .rounded, weight: .semibold))

            if stats.days.isEmpty {
                Text("Nothing logged yet. Press an orb.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(stats.days) { day in
                        Button {
                            inspecting = day
                        } label: {
                            CombinedDayRow(day: day, calc: store.calc)
                        }
                        .buttonStyle(.plain)

                        if day.id != stats.days.last?.id {
                            Divider().overlay(Chrome.steel.opacity(0.25))
                        }
                    }
                }
            }
        }
        .panel()
        // Dont render specular shiny on the heavy populated areas
        .environment(\.orbShading, OrbShading.standard.quiet)
    }
}

// MARK: - Tap target

private struct ProgressRow: View {
    let item: PeriodProgress

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .lineLimit(1)
                    if item.isMet {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Chrome.gold)
                    }
                }

                SlotRail(
                    fills: item.fills,
                    capacity: item.target,
                    size: 13,
                    maxSlots: 20
                )

                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text("\(item.count)/\(item.target)")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(item.isMet ? Chrome.gold : .primary)
        }
        .padding(.vertical, 10)
    }

    private var caption: String {
        if item.isMet {
            return "\(item.periodLabel) · done"
        }
        let days = item.daysRemaining
        let unit = days == 1 ? "day" : "days"
        return "\(item.periodLabel) · \(item.remaining) to go, \(days) \(unit) left"
    }
}

private struct ActivityButton: View {
    @Environment(LogStore.self) private var store
    let activity: Activity
    let action: () -> Void
    /// Long press: log it and open the note straight away, for when you already
    /// know this one was worth writing about.
    let logAndNote: () -> Void

    var body: some View {
        let progress = store.progress(for: activity)

        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [activity.color.core.opacity(0.20), .clear],
                                center: .center,
                                startRadius: 6,
                                endRadius: 48
                            )
                        )
                        .frame(width: 96, height: 96)

                    MateriaOrb(color: activity.color, size: 66, glow: 1.2)

                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.5), radius: 3)
                }

                Text(activity.name)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .lineLimit(1)

                Text("\(progress.count)/\(progress.target)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(progress.isMet ? Chrome.gold : .secondary)
            }
            .frame(width: 104)
        }
        .buttonStyle(OrbButtonStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in logAndNote() }
        )
        .accessibilityLabel("Slot a jewel for \(activity.name)")
        .accessibilityHint("Long press to log with a note")
    }
}

// MARK: - Day row

private struct CombinedDayRow: View {
    let day: CombinedDay
    let calc: DayCalculator

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(calc.label(for: day.day))
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                    if day.isMastered {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Chrome.gold)
                    }
                }

                SlotRail(
                    fills: day.fills,
                    capacity: day.capacity,
                    size: 14,
                    maxSlots: 24
                )
            }

            Spacer(minLength: 8)

            Text("\(day.count)")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(day.isMastered ? Chrome.gold : .primary)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
