// MARK: - DayView
// The day-centric screen: today's rail, the loadout of orb buttons, and the
// panels below them (tags, what's due this period, numbers, history). Given a
// tag scope, it narrows to that tag's members and counts in the tag's own
// periods. Titled with the wordmark, like the sidebar.

internal import SwiftUI

/// The day-centric screen. Every jewel earned today sits on one rail in the
/// order it was earned, colour-coded by activity.
///
/// With a `scope`, the same screen narrows to one tag: today's rail shows only
/// that tag's members, the loadout offers only their orbs, and the numbers
/// below switch from days to the tag's own periods — "this week" rather than
/// "today", because that's the unit a tag is measured in.
struct DayView: View {
    @Environment(LogStore.self) private var store

    /// When set, every panel narrows to this tag. Nil is the ordinary day.
    var scope: Tag.ID? = nil

    @State private var pulse = 0
    @State private var inspecting: CombinedDay?
    @State private var noting: LoggedJewel?

    var body: some View {
        let stats = store.combined
        let tag = store.tag(scope)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                todayPanel(stats, tag)
                loadout(stats, tag)
                if let tag {
                    tagPeriodPanel(tag)
                    tagStatsPanel(tag)
                    tagHistory(tag)
                } else {
                    tagsPanel(stats)
                    duePanel(stats)
                    statsPanel(stats)
                    history(stats)
                }
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Chrome.panel.ignoresSafeArea())
        // Same header as the sidebar, led by a back button on iPhone, where
        // the header replaces the bar. Tags have no colour of their own, so
        // a scoped day keeps the house colour rather than borrowing a
        // member's.
        .wordmarkTitle(tag?.name ?? "Today", backButton: true)
        .sensoryFeedback(.impact(weight: .medium), trigger: pulse)
        //TODO share from here?
        // NOTE: if this comes back, pass the ShareLink to wordmarkTitle as an
        // accessory instead. The bar is hidden on iPhone, so toolbar items
        // placed here would never show.
//        .toolbar {
//            ToolbarItem {
//                ShareLink(item: store.exportCSV()) {
//                    Label("Export CSV", systemImage: "square.and.arrow.up")
//                }
//            }
//        }
        .sheet(item: $inspecting) { day in
            DayEntriesSheet(day: day.day, capacity: day.capacity)
        }
        .sheet(item: $noting) { entry in
            NoteEditor(entry: entry)
        }
    }

    // MARK: Scope helpers

    /// Today's jewels, chronological, narrowed to the tag when there is one.
    private func todayFills(_ stats: CombinedStats, _ tag: Tag?) -> [RailJewel] {
        (stats.today?.entries ?? [])
            .filter { tag?.contains($0.activityID) ?? true }
            .map(\.rail)
    }

    /// Activities that get a button on this screen.
    private func loadoutActivities(_ tag: Tag?) -> [Activity] {
        tag.map { store.visibleMembers(of: $0) } ?? store.visibleActivities
    }

    // MARK: The one rail

    private func todayPanel(_ stats: CombinedStats, _ tag: Tag?) -> some View {
        let fills = todayFills(stats, tag)
        let capacity = tag.map { store.dailyCapacity(for: $0) } ?? stats.capacity
        let members = loadoutActivities(tag)
        let mastered = capacity > 0 && fills.count >= capacity
        let overflow = max(0, fills.count - capacity)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(store.calc.label(for: store.calc.today))
                    .font(.system(.headline, design: .rounded, weight: .semibold))

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(fills.count)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    if capacity > 0 {
                        Text("/ \(capacity)")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if members.isEmpty && fills.isEmpty {
                Text(emptyMessage(tag))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if fills.isEmpty && capacity == 0 {
                // Nothing daily is due and nothing's been logged, so there are
                // no sockets to draw. Everything lives in the period list below.
                Text("Nothing logged today.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                SlotRail(fills: fills, capacity: capacity, size: 34)
                    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: fills)

                if mastered {
                    Label(
                        overflow > 0 ? "Mastered — \(overflow) over" : "Mastered",
                        systemImage: "star.fill"
                    )
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Chrome.gold)
                }
            }
        }
        .panel()
    }

    private func emptyMessage(_ tag: Tag?) -> String {
        if let tag {
            return tag.activityIDs.isEmpty
                ? "This tag has no activities yet. Edit it to add some."
                : "Everything in this tag is hidden. Unhide one from the sidebar."
        }
        return store.activities.isEmpty
            ? "Create an activity and its jewels will land here."
            : "Everything's hidden. Unhide one from the sidebar."
    }

    // MARK: Every button in one place

    @ViewBuilder
    private func loadout(_ stats: CombinedStats, _ tag: Tag?) -> some View {
        let activities = loadoutActivities(tag)
        let todayCount = todayFills(stats, tag).count

        if !activities.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Slot a jewel")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Spacer()
                    Button {
                        noting = store.mostRecentToday(in: tag)
                    } label: {
                        Label("Note", systemImage: "square.and.pencil")
                            .font(.system(.caption, design: .rounded))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(.bordered)
                    .disabled(todayCount == 0)

                    Button {
                        store.removeLastToday(in: tag)
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.system(.caption, design: .rounded))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(.bordered)
                    .disabled(todayCount == 0)
                }

                // Doubles as the rail's legend — this is where you learn which
                // colour belongs to which activity.
                FlowLayout(spacing: 18, lineSpacing: 16) {
                    ForEach(activities) { activity in
                        ActivityButton(activity: activity) {
                            store.slot(activity.id)
                            pulse += 1
                        } logAndNote: {
                            store.slot(activity.id)
                            pulse += 1
                            noting = store.mostRecentToday(in: tag)
                        }
                    }
                }

                if let tag {
                    // A tag's streak is counted in its own periods, not days.
                    let tagStats = store.stats(for: tag)
                    StreakBadge(
                        streak: tagStats.currentStreak,
                        today: tagStats.currentCount,
                        accent: activities.first?.color.core ?? Chrome.steelHi,
                        unit: streakUnit(tag.cadence)
                    )
                    .padding(.top, 2)
                } else {
                    StreakBadge(
                        streak: stats.currentStreak,
                        today: stats.todayCount,
                        accent: activities.first?.color.core ?? Chrome.steelHi
                    )
                    .padding(.top, 2)
                }
            }
            .panel()
        }
    }

    /// "days" / "weeks" / "months" for a plain cadence; "periods" for a
    /// compound one like every 2 weeks, where none of those is honest.
    private func streakUnit(_ cadence: Cadence) -> String {
        cadence.count == 1 ? cadence.unit.label(count: 2) : "periods"
    }

    // MARK: Where each tag stands (unscoped)

    /// One row per tag on the ordinary day screen. Tags are inherently
    /// periodic, so this is where "3 of 5 exercise this week" lives.
    @ViewBuilder
    private func tagsPanel(_ stats: CombinedStats) -> some View {
        if !stats.tagProgress.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tags")
                    .font(.system(.headline, design: .rounded, weight: .semibold))

                LazyVStack(spacing: 0) {
                    ForEach(stats.tagProgress) { item in
                        TagProgressRow(item: item)

                        if item.id != stats.tagProgress.last?.id {
                            Divider().overlay(Chrome.steel.opacity(0.25))
                        }
                    }
                }
            }
            .panel()
        }
    }

    // MARK: This period, for one tag (scoped)

    /// The scoped equivalent of the today panel's counter, but for the unit
    /// that actually matters to a tag: the current period.
    private func tagPeriodPanel(_ tag: Tag) -> some View {
        let progress = store.progress(for: tag)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(progress.periodLabel)
                    .font(.system(.headline, design: .rounded, weight: .semibold))

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(progress.count)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(progress.isMet ? Chrome.gold : .primary)
                    Text("/ \(progress.target)")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            SlotRail(fills: progress.fills, capacity: progress.target, size: 26, maxSlots: 40)
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: progress.fills)

            if progress.isMet {
                Label(
                    progress.overflow > 0 ? "Met — \(progress.overflow) over" : "Met",
                    systemImage: "star.fill"
                )
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Chrome.gold)
            } else {
                let unit = progress.daysRemaining == 1 ? "day" : "days"
                Text("\(progress.remaining) to go, \(progress.daysRemaining) \(unit) left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Who contributed. The rail already shows it by colour; this puts
            // names to the colours.
            if !progress.tallies.isEmpty {
                FlowLayout(spacing: 12, lineSpacing: 6) {
                    ForEach(progress.tallies) { tally in
                        HStack(spacing: 5) {
                            MateriaOrb(color: tally.color, size: 12, glow: 0.5)
                            Text("\(tally.name) \(tally.count)")
                                .font(.system(.caption, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .panel()
    }

    // MARK: Where each activity stands

    /// Carries the weight for non-daily activities. A day rail can't say
    /// anything useful about a monthly commitment, so this does.
    @ViewBuilder
    private func duePanel(_ stats: CombinedStats) -> some View {
        let outstanding = stats.progress.filter { !$0.cadence.isDaily && !$0.isOpenEnded }

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

    /// Same grid, in the tag's own units.
    private func tagStatsPanel(_ tag: Tag) -> some View {
        let stats = store.stats(for: tag)
        let unit = streakUnit(tag.cadence)
        let singular = String(unit.dropLast())

        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 108), spacing: 12)],
            alignment: .leading,
            spacing: 14
        ) {
            StatTile(label: "Total", value: "\(stats.total)")
            StatTile(label: "Streak", value: "\(stats.currentStreak)", unit: unit)
            StatTile(label: "Longest", value: "\(stats.longestStreak)", unit: unit)
            StatTile(label: "\(singular.capitalized)s logged", value: "\(stats.periodsLogged)")
            StatTile(label: "Met", value: "\(stats.periodsMet)", unit: unit)
            StatTile(label: "Per \(singular)", value: String(format: "%.1f", stats.average))
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

    /// The tag's history is by period, not by day — a weekly tag has nothing
    /// to say about Tuesday in particular.
    private func tagHistory(_ tag: Tag) -> some View {
        let stats = store.stats(for: tag)
        let periods = stats.periods.filter { $0.count > 0 || $0.index == stats.current?.index }

        return VStack(alignment: .leading, spacing: 12) {
            Text("By \(String(streakUnit(tag.cadence).dropLast()))")
                .font(.system(.headline, design: .rounded, weight: .semibold))

            if stats.total == 0 {
                Text("Nothing logged yet. Press an orb.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(periods) { period in
                        TagPeriodRow(
                            period: period,
                            label: store.calc.periodLabel(
                                index: period.index,
                                cadence: tag.cadence,
                                anchor: tag.createdAt
                            )
                        )

                        if period.id != periods.last?.id {
                            Divider().overlay(Chrome.steel.opacity(0.25))
                        }
                    }
                }
            }
        }
        .panel()
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

/// `ProgressRow` for a tag. Identical shape on purpose — the only visible
/// difference should be that the rail is mixed-colour.
private struct TagProgressRow: View {
    let item: TagProgress

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
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

/// One past period of a tag: label, mixed rail, count.
private struct TagPeriodRow: View {
    let period: PeriodSummary
    let label: String

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
                    maxSlots: 24
                )
            }

            Spacer(minLength: 8)

            Text("\(period.count)")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(period.isMet ? Chrome.gold : .primary)
        }
        .padding(.vertical, 10)
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

                Text(progress.isOpenEnded ? "\(progress.count)" : "\(progress.count)/\(progress.target)")
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
