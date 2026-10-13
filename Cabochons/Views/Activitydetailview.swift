internal import SwiftUI

/// One activity in isolation. The combined day rail lives in `DayView`; this
/// screen is for when you want to look at a single habit's history.
struct ActivityDetailView: View {
    @Environment(LogStore.self) private var store
    let activityID: Activity.ID

    @State private var pulse = 0
    @State private var inspecting: PeriodSummary?
    @State private var noting: LoggedJewel?
    @State private var editing = false
    
    @State private var confirmingDelete = false
    var onDelete: (() -> Void)? = nil

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
                Menu {
                    Button {
                        editing = true
                    } label: {
                        Label("Edit", systemImage: "slider.horizontal.3")
                    }

                    if let activity {
                        Button {
                            store.setHidden(activity.id, !activity.isHidden)
                        } label: {
                            Label(
                                activity.isHidden ? "Unhide" : "Hide",
                                systemImage: activity.isHidden ? "eye" : "eye.slash"
                            )
                        }
                    }
                    if activity?.isHidden == true {
                        Divider()
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                } label: {
                    Label("Options", systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $editing) {
            if let activity {
                ActivityEditor(mode: .edit(activity)) { store.update($0) }
            }
        }
        .sheet(item: $noting) { entry in
            NoteEditor(entry: entry)
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
        .confirmationDialog(
            "Delete \(activity?.name ?? "activity")?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete \(activity?.jewels.count ?? 0) jewels", role: .destructive) {
                onDelete?()
                store.delete(activityID)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure? All history of this cabochon will be lost.")
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(for activity: Activity) -> some View {
        let stats = store.stats(for: activity)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if activity.isHidden {
                    hiddenBanner(activity)
                }
                slotPanel(activity: activity, stats: stats)
                tapRow(activity: activity, stats: stats)
                statsPanel(stats)
                if !activity.jewels.isEmpty {
                    HistoryYearPanel(
                        history: .build(for: activity, weeks: 53, calc: store.calc),
                        color: activity.color
                    )
                    weekdayPanel(activity: activity)
                    hourPanel(activity: activity)
                }
                history(activity: activity, stats: stats)
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: pulse)
    }

    // MARK: Hidden

    private func hiddenBanner(_ activity: Activity) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "eye.slash")
                .foregroundStyle(Chrome.steelHi)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hidden")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text("All \(activity.jewels.count) jewels are kept and still show in past days. It just isn't asking for anything.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("Unhide") {
                store.setHidden(activity.id, false)
            }
            .buttonStyle(.bordered)
        }
        .panel()
    }

    // MARK: This period's sockets

    private func slotPanel(activity: Activity, stats: ActivityStats) -> some View {
        let current = stats.current

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(periodTitle(stats))
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    if stats.isOpenEnded {
                        Text("whenever")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !stats.cadence.isDaily {
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
                    if !stats.isOpenEnded {
                        Text("/ \(stats.target)")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SlotRail(
                fills: current?.fills ?? [],
                capacity: stats.target,
                size: 34
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: current?.fills ?? [])

            if let current, current.isMet {
                Label(
                    current.overflow > 0 ? "Completed — \(current.overflow) over" : "Completed",
                    systemImage: "star.fill"
                )
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Chrome.gold)
            } else if let current, !stats.isOpenEnded, !stats.cadence.isDaily {
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

                    CabochonsOrb(color: activity.color, size: 108, glow: 1.3)

                    Image(systemName: "plus")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.5), radius: 3)
                }
            }
            .buttonStyle(OrbButtonStyle())
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                    store.slot(activity.id)
                    pulse += 1
                    noting = store.entries(on: store.calc.today, activityID: activity.id).first
                }
            )
            .accessibilityLabel("Slot a jewel for \(activity.name)")
            .accessibilityHint("Long press to log with a note")

            VStack(alignment: .leading, spacing: 10) {
                // A streak is a target in disguise; open-ended activities
                // don't get one.
                if !stats.isOpenEnded {
                    StreakBadge(
                        streak: stats.currentStreak,
                        current: stats.current,
                        accent: activity.color.core,
                        unit: stats.cadence.unit.label(count: 2)
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }

                // Stacked, not side by side: the orb is a fixed 152pt, so on a
                // phone the remaining column is too narrow for two bordered
                // buttons and SwiftUI compresses them until the labels wrap one
                // character per line.
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        noting = store.entries(on: store.calc.today, activityID: activity.id).first
                    } label: {
                        Label("Note", systemImage: "square.and.pencil")
                            .font(.system(.callout, design: .rounded))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.todayCount(for: activity) == 0)

                    Button {
                        store.removeLastToday(activity.id)
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.system(.callout, design: .rounded))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.todayCount(for: activity) == 0)
                }
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
            if !stats.isOpenEnded {
                StatTile(label: "Streak", value: "\(stats.currentStreak)", unit: unit)
                StatTile(label: "Longest", value: "\(stats.longestStreak)", unit: unit)
            }
            StatTile(label: "Logged", value: "\(stats.periodsLogged)", unit: unit)
            if !stats.isOpenEnded {
                StatTile(label: "Completed", value: "\(stats.periodsMet)", unit: unit)
            }
            StatTile(label: "Average", value: String(format: "%.1f", stats.average))
        }
        .panel()
    }
    
    // MARK: Weekday affinity

    private func weekdayPanel(activity: Activity) -> some View {
        let profile = Stats.weekdayProfile(for: activity, calc: store.calc)
        let calendar = Calendar.current
        let entries = profile.ordered(firstWeekday: calendar.firstWeekday)
        let peak = entries.map(\.rate).max() ?? 0
        let bestWeekday = profile.best?.weekday

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("By weekday")
                    .font(.system(.headline, design: .rounded, weight: .semibold))

                Spacer()

                if let best = profile.best {
                    Text("\(calendar.standaloneWeekdaySymbols[best.weekday - 1])s · \(best.count) of \(best.opportunities)")
                        .font(.system(.caption, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(entries) { entry in
                    let isBest = entry.weekday == bestWeekday
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isBest ? activity.color.core : Chrome.steel.opacity(0.45))
                            .frame(height: barHeight(entry.rate, peak: peak))
                            .frame(height: 56, alignment: .bottom)
                            .accessibilityLabel(
                                "\(calendar.standaloneWeekdaySymbols[entry.weekday - 1]): \(entry.count) of \(entry.opportunities)"
                            )

                        Text(calendar.veryShortStandaloneWeekdaySymbols[entry.weekday - 1])
                            .font(.system(.caption2, design: .rounded, weight: isBest ? .semibold : .regular))
                            .foregroundStyle(isBest ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .panel()
    }

    /// Bars scale against the busiest day, not against 1.0 — a multi-target
    /// activity can exceed one jewel per weekday and the bar would clip.
    private func barHeight(_ rate: Double, peak: Double) -> CGFloat {
        guard peak > 0 else { return 3 }
        return max(3, 56 * CGFloat(rate / peak))
    }
    
    // MARK: Hour affinity

    private func hourPanel(activity: Activity) -> some View {
        let profile = Stats.hourProfile(for: activity, calc: store.calc)
        let window = profile.busiestWindow()
        let peak = Double(profile.peak)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("By hour")
                    .font(.system(.headline, design: .rounded, weight: .semibold))

                Spacer()

                if let window {
                    Text("\(hourLabel(window.start))–\(hourLabel(window.end)) · \(window.count) of \(profile.total)")
                        .font(.system(.caption, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24, id: \.self) { hour in
                    let inWindow = window?.contains(hour) ?? false
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(inWindow ? activity.color.core : Chrome.steel.opacity(0.45))
                        .frame(height: barHeight(Double(profile.counts[hour]), peak: peak))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56, alignment: .bottom)
                        .accessibilityLabel("\(hourLabel(hour)): \(profile.counts[hour])")
                }
            }

            // Four labels spread across the row land close enough to their
            // bars; exact alignment isn't worth a GeometryReader.
            HStack(spacing: 0) {
                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    Text(hourLabel(hour))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .panel()
    }

    /// Locale-aware: "6 PM" for 12-hour users, "18" for everyone else.
    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(.dateTime.hour())
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
                            .equatable()
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

private struct PeriodRow: View, Equatable {
    let period: PeriodSummary
    let label: String
    let color: CabochonsColor

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
                    fills: period.fills,
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
