// MARK: - DayView
// The day-centric screen: today's rail, the loadout of orb buttons, and the
// panels below them. Shown for a calendar span (Today, this week, this month,
// this year) or narrowed to a tag. Spans and tags are both a `Scope`, so there
// is one screen, not several that look alike. Titled with the wordmark.

internal import SwiftUI

/// The day-centric screen for one scope. Every jewel earned today sits on one
/// rail in the order it was earned, colour-coded by activity.
///
/// A span is the scope of every activity, measured against what they all ask
/// for in that span. A tag is the scope of its members, measured against its
/// own target and cadence. The panels are the same for all of them; only the
/// units change — "this week" rather than "today" for anything weekly.
struct DayView: View {
    @Environment(LogStore.self) private var store

    /// Which calendar span to show, when there's no tag.
    var span: Scope.Span = .day
    /// When set, every panel narrows to this tag instead.
    var tagID: Tag.ID? = nil

    @State private var pulse = 0
    @State private var inspecting: PeriodSummary?
    @State private var noting: LoggedJewel?

    var body: some View {
        let scope = currentScope
        let stats = store.stats(for: scope)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                todayPanel(scope)
                loadout(scope, stats)
                // A daily scope's period *is* today, and the rail above
                // already shows it.
                if !scope.cadence.isDaily {
                    periodPanel(store.progress(for: scope))
                }
                if scope.isEverything {
                    tagsPanel()
                }
                duePanel(scope)
                statsPanel(scope, stats)
                history(scope, stats)
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
        .wordmarkTitle(scope.name, backButton: true)
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
        .sheet(item: $inspecting) { period in
            let scope = currentScope
            PeriodEntriesSheet(
                period: period,
                title: periodLabel(period, scope),
                scope: scope
            )
        }
        .sheet(item: $noting) { entry in
            NoteEditor(entry: entry)
        }
    }

    // MARK: Helpers

    private var currentScope: Scope {
        tagID == nil ? store.scope(span) : store.scope(tagID)
    }

    /// Today's jewels from the scope's members, chronological.
    private func todayFills(_ scope: Scope) -> [RailJewel] {
        store.entries(on: store.calc.today, in: scope).reversed().map(\.rail)
    }

    private func periodLabel(_ period: PeriodSummary, _ scope: Scope) -> String {
        store.calc.periodLabel(index: period.index, cadence: scope.cadence, anchor: scope.anchor)
    }

    // MARK: The one rail

    private func todayPanel(_ scope: Scope) -> some View {
        let fills = todayFills(scope)
        let capacity = store.dailyCapacity(for: scope)
        let members = store.visibleMembers(of: scope)
        let completed = capacity > 0 && fills.count >= capacity
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
                Text(emptyMessage(scope))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if fills.isEmpty && capacity == 0 {
                // Nothing daily is due and nothing's been logged, so there are
                // no sockets to draw. Everything lives in the period panels below.
                Text("Nothing logged today.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                SlotRail(fills: fills, capacity: capacity, size: 34)
                    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: fills)

                if completed {
                    Label(
                        overflow > 0 ? "Completed — \(overflow) over" : "Completed",
                        systemImage: "star.fill"
                    )
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Chrome.gold)
                }
            }
        }
        .panel()
    }

    private func emptyMessage(_ scope: Scope) -> String {
        if scope.isEverything {
            return store.activities.isEmpty
                ? "Create an activity and its jewels will land here."
                : "Everything's hidden. Unhide one from the sidebar."
        }
        return scope.memberIDs?.isEmpty == true
            ? "This tag has no activities yet. Edit it to add some."
            : "Everything in this tag is hidden. Unhide one from the sidebar."
    }

    // MARK: Every button in one place

    @ViewBuilder
    private func loadout(_ scope: Scope, _ stats: PeriodStats) -> some View {
        let activities = store.visibleMembers(of: scope)
        let todayCount = todayFills(scope).count

        if !activities.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Slot a jewel")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Spacer()
                    Button {
                        noting = store.mostRecentToday(in: scope)
                    } label: {
                        Label("Note", systemImage: "square.and.pencil")
                            .font(.system(.caption, design: .rounded))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(.bordered)
                    .disabled(todayCount == 0)

                    Button {
                        store.removeLastToday(in: scope)
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
                            noting = store.mostRecentToday(in: scope)
                        }
                    }
                }

                // Counted in the scope's own periods: days for Today, weeks
                // for this week, the tag's cadence for a tag.
                StreakBadge(
                    streak: stats.currentStreak,
                    current: stats.current,
                    accent: activities.first?.color.core ?? Chrome.steelHi,
                    unit: scope.periodNoun
                )
                .padding(.top, 2)
            }
            .panel()
        }
    }

    // MARK: This period

    /// The today panel's counter, but for the unit that actually matters to a
    /// non-daily scope: the current period.
    private func periodPanel(_ progress: ScopeProgress) -> some View {
        VStack(alignment: .leading, spacing: 14) {
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
                            CabochonsOrb(color: tally.color, size: 12, glow: 0.5)
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

    // MARK: Where each tag stands

    /// One row per tag, on the calendar spans only — they contain every tag.
    /// Tags are inherently periodic, so this is where "3 of 5 exercise this
    /// week" lives.
    @ViewBuilder
    private func tagsPanel() -> some View {
        let tags = store.tags.map { (tag: $0, progress: store.progress(for: $0)) }

        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tags")
                    .font(.system(.headline, design: .rounded, weight: .semibold))

                LazyVStack(spacing: 0) {
                    ForEach(tags, id: \.tag.id) { item in
                        ProgressRow(item.progress, symbol: item.tag.symbol)

                        if item.tag.id != tags.last?.tag.id {
                            Divider().overlay(Chrome.steel.opacity(0.25))
                        }
                    }
                }
            }
            .panel()
        }
    }

    // MARK: Where each member stands

    /// Carries the weight for non-daily members. A day rail can't say anything
    /// useful about a monthly commitment, so this does.
    @ViewBuilder
    private func duePanel(_ scope: Scope) -> some View {
        let outstanding = store.visibleMembers(of: scope)
            .filter { !$0.cadence.isDaily && !$0.isOpenEnded }
            .map { store.progress(for: $0) }

        if !outstanding.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("This period")
                    .font(.system(.headline, design: .rounded, weight: .semibold))

                LazyVStack(spacing: 0) {
                    ForEach(outstanding) { item in
                        ProgressRow(item)

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

    /// In the scope's own units: days for Today, weeks for this week or a
    /// weekly tag.
    private func statsPanel(_ scope: Scope, _ stats: PeriodStats) -> some View {
        let unit = scope.periodNoun
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

    /// One row per period with anything in it, plus the current one. Tap a
    /// row for its jewels.
    private func history(_ scope: Scope, _ stats: PeriodStats) -> some View {
        let periods = stats.periods.filter { $0.count > 0 || $0.index == stats.current?.index }

        return VStack(alignment: .leading, spacing: 12) {
            Text("By \(String(scope.periodNoun.dropLast()))")
                .font(.system(.headline, design: .rounded, weight: .semibold))

            if stats.total == 0 {
                Text("Nothing logged yet. Press an orb.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(periods) { period in
                        Button {
                            inspecting = period
                        } label: {
                            PeriodRow(period: period, label: periodLabel(period, scope))
                        }
                        .buttonStyle(.plain)

                        if period.id != periods.last?.id {
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

// MARK: - Rows

/// Where one thing stands in its current period: an activity, or a tag. Same
/// shape for both on purpose — the only visible difference should be that a
/// tag's rail is mixed-colour and it wears its symbol.
private struct ProgressRow: View {
    let name: String
    let symbol: String?
    let count: Int
    let target: Int
    let isMet: Bool
    let remaining: Int
    let periodLabel: String
    let daysRemaining: Int
    let fills: [RailJewel]

    init(_ item: PeriodProgress) {
        name = item.name
        symbol = nil
        count = item.count
        target = item.target
        isMet = item.isMet
        remaining = item.remaining
        periodLabel = item.periodLabel
        daysRemaining = item.daysRemaining
        fills = item.fills
    }

    init(_ item: ScopeProgress, symbol: String) {
        name = item.name
        self.symbol = symbol
        count = item.count
        target = item.target
        isMet = item.isMet
        remaining = item.remaining
        periodLabel = item.periodLabel
        daysRemaining = item.daysRemaining
        fills = item.fills
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Text(name)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .lineLimit(1)
                    if isMet {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Chrome.gold)
                    }
                }

                SlotRail(
                    fills: fills,
                    capacity: target,
                    size: 13,
                    maxSlots: 20
                )

                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text("\(count)/\(target)")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isMet ? Chrome.gold : .primary)
        }
        .padding(.vertical, 10)
    }

    private var caption: String {
        if isMet {
            return "\(periodLabel) · done"
        }
        let unit = daysRemaining == 1 ? "day" : "days"
        return "\(periodLabel) · \(remaining) to go, \(daysRemaining) \(unit) left"
    }
}

/// One past period of a scope — a day of Today, a week of a tag: label, mixed
/// rail, count.
private struct PeriodRow: View {
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

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
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

                    CabochonsOrb(color: activity.color, size: 66, glow: 1.2)

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
