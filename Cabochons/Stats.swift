internal import Foundation


// MARK: - Weekday affinity

/// How jewels spread across the week, corrected for how many of each weekday
/// the activity has actually lived through. `rate` is the number you show.
struct WeekdayProfile: Hashable {
    struct Entry: Identifiable, Hashable {
        /// Calendar weekday: 1 = Sunday … 7 = Saturday.
        let weekday: Int
        let count: Int
        /// Occurrences of this weekday from creation day through today, inclusive.
        let opportunities: Int

        var id: Int { weekday }
        /// Jewels per occurrence. Can exceed 1 for multi-target activities.
        var rate: Double { opportunities == 0 ? 0 : Double(count) / Double(opportunities) }
    }

    /// Always seven, Sunday through Saturday.
    let entries: [Entry]

    var total: Int { entries.reduce(0) { $0 + $1.count } }
    var best: Entry? { entries.filter { $0.count > 0 }.max { $0.rate < $1.rate } }

    /// Same seven entries rotated to start on the user's first weekday.
    func ordered(firstWeekday: Int) -> [Entry] {
        let start = max(0, min(6, firstWeekday - 1))
        return Array(entries[start...] + entries[..<start])
    }
}

// MARK: - A jewel with its provenance attached

/// A jewel plus the activity that produced it. The combined day rail mixes
/// jewels from every activity, so colour and name have to travel with them.
struct LoggedJewel: Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let activityID: UUID
    let activityName: String
    let color: CabochonsColor
    var note: String? = nil

    var hasNote: Bool {
        !(note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var rail: RailJewel { RailJewel(color, note: note) }

    init(id: UUID, timestamp: Date, activityID: UUID, activityName: String, color: CabochonsColor, note: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.activityID = activityID
        self.activityName = activityName
        self.color = color
        self.note = note
    }

    /// A jewel stamped with the activity it came from.
    init(_ jewel: Jewel, of activity: Activity) {
        self.init(
            id: jewel.id,
            timestamp: jewel.timestamp,
            activityID: activity.id,
            activityName: activity.name,
            color: activity.color,
            note: jewel.note
        )
    }
}

// MARK: - Per-activity

/// One turn of an activity's cadence.
struct PeriodSummary: Identifiable, Hashable, Equatable {
    let index: Int
    let start: Date
    /// Exclusive.
    let end: Date
    let count: Int
    let target: Int
    /// Chronological. Carried here so history rows don't each re-query.
    var fills: [RailJewel] = []

    var id: Int { index }
    var isMet: Bool { target > 0 && count >= target }
    var overflow: Int { max(0, count - target) }
    var remaining: Int { max(0, target - count) }
    /// What a streak counts. A target makes it "met"; with no target there's
    /// nothing to meet, so showing up at all is the bar.
    var keepsStreak: Bool { target == 0 ? count > 0 : isMet }
}

/// Everything measured against one cadence: totals, streaks, and every period
/// ever logged. An activity and a scope both produce one of these — the only
/// difference is whose jewels went in.
struct PeriodStats {
    var total: Int = 0
    /// The current period's. A span's target can change period to period.
    var target: Int = 1
    var cadence: Cadence = .daily
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var periodsLogged: Int = 0
    var periodsMet: Int = 0
    var best: PeriodSummary?
    var current: PeriodSummary?
    /// Newest first. Includes the current period even when it's empty.
    var periods: [PeriodSummary] = []

    var currentCount: Int { current?.count ?? 0 }
    /// No target, no sockets. Mirrors `Activity.isOpenEnded`.
    var isOpenEnded: Bool { target == 0 }

    var average: Double {
        periodsLogged == 0 ? 0 : Double(total) / Double(periodsLogged)
    }
}

/// The old name. Existing call sites (`ActivityDetailView`) keep compiling.
typealias ActivityStats = PeriodStats

// MARK: - Scopes

/// Some activities, measured against one cadence and one target. A tag is a
/// scope; so are Today, this week, this month and this year — every activity,
/// with what its members ask for in that span as the target. Everything that
/// counts a group of activities goes through here, so they can't drift apart.
struct Scope: Hashable {
    /// The calendar's own periods, each covering every activity.
    enum Span: CaseIterable, Hashable {
        case day, week, month, year

        var name: String {
            switch self {
            case .day:   "Today"
            case .week:  "This week"
            case .month: "This month"
            case .year:  "This year"
            }
        }

        var symbol: String {
            switch self {
            case .day:   "square.grid.2x2.fill"
            case .week:  "calendar.day.timeline.left"
            case .month: "calendar"
            case .year:  "circle.grid.3x3.fill"
            }
        }

        var cadence: Cadence {
            switch self {
            case .day:   .daily
            case .week:  .weekly
            case .month: .monthly
            case .year:  Cadence(count: 12, unit: .month)
            }
        }

        /// "days", "weeks", … — what a streak in this span counts.
        var periodNoun: String {
            switch self {
            case .day:   "days"
            case .week:  "weeks"
            case .month: "months"
            case .year:  "years"
            }
        }

        /// A date the span's periods tile from: a first weekday for weeks, a
        /// January for years. Days and months tile the same from anywhere.
        func anchor(_ calc: DayCalculator) -> Date {
            let today = calc.today
            switch self {
            case .day, .month:
                return today
            case .week:
                let offset = (calc.calendar.component(.weekday, from: today) - calc.calendar.firstWeekday + 7) % 7
                return calc.offsetting(today, by: -offset)
            case .year:
                let year = calc.calendar.component(.year, from: today)
                // Mid-month, so a late day start can't tip it into December.
                return calc.calendar.date(from: DateComponents(year: year, month: 1, day: 15)) ?? today
            }
        }
    }

    enum Kind: Hashable {
        case span(Span)
        case tag(Tag.ID)
    }

    /// One activity's ask, to be scaled to whatever period is being measured.
    struct Quota: Hashable {
        let cadence: Cadence
        let target: Int

        /// How many whole turns of this cadence fit in a period of `days`
        /// days spanning `months` calendar months. A daily activity fits 7
        /// times in a week; a weekly one fits 4 times in any month; a monthly
        /// one fits no times in a week.
        func fits(days: Int, months: Int) -> Int {
            if let length = cadence.lengthInDays { return days / length }
            return months / cadence.count
        }
    }

    enum Goal: Hashable {
        /// A tag's: the same every period.
        case fixed(Int)
        /// A span's: every visible activity's target, scaled to the period —
        /// so February asks for less than March.
        case scaled([Quota])
    }

    let kind: Kind
    let name: String
    let symbol: String
    /// Nil means every activity.
    let memberIDs: [UUID]?
    let goal: Goal
    let cadence: Cadence
    /// Period anchor.
    let anchor: Date

    var tagID: Tag.ID? {
        if case .tag(let id) = kind { id } else { nil }
    }

    var span: Span? {
        if case .span(let span) = kind { span } else { nil }
    }

    /// True for the calendar spans, which hold every activity — and so every tag.
    var isEverything: Bool { memberIDs == nil }

    /// "days" / "weeks" / "months" for a plain cadence; "periods" for a
    /// compound one like every 2 weeks, where none of those is honest.
    var periodNoun: String {
        if let span { return span.periodNoun }
        return cadence.count == 1 ? cadence.unit.label(count: 2) : "periods"
    }

    func contains(_ id: Activity.ID) -> Bool {
        memberIDs?.contains(id) ?? true
    }

    /// Visible members, in sidebar order: the ones that get a button.
    func visibleMembers(of activities: [Activity]) -> [Activity] {
        activities.filter { !$0.isHidden && contains($0.id) }
    }

    /// The target for the period running from `start` to `end` (exclusive).
    func target(from start: Date, to end: Date, calc: DayCalculator) -> Int {
        switch goal {
        case .fixed(let target):
            return target
        case .scaled(let quotas):
            let days = calc.daysBetween(start, end)
            let months = calc.calendar.dateComponents([.month], from: start, to: end).month ?? 0
            return quotas.reduce(0) { $0 + $1.target * $1.fits(days: days, months: months) }
        }
    }

    /// Sockets today's rail has: today's target when the scope is daily,
    /// otherwise the daily targets of its visible members. A monthly activity
    /// owes nothing in particular today, and a hidden one owes nothing at all.
    func dailyCapacity(of activities: [Activity], calc: DayCalculator) -> Int {
        if cadence.isDaily {
            return target(from: calc.today, to: calc.offsetting(calc.today, by: 1), calc: calc)
        }
        return visibleMembers(of: activities)
            .filter { $0.cadence.isDaily }
            .reduce(0) { $0 + $1.target }
    }

    init(_ tag: Tag) {
        kind = .tag(tag.id)
        name = tag.name
        symbol = tag.symbol
        memberIDs = tag.activityIDs
        goal = .fixed(tag.target)
        cadence = tag.cadence
        anchor = tag.createdAt
    }

    /// Every activity, one span at a time. With nothing that fits the span —
    /// no daily activities, for Today — the target is 0 and it's open-ended.
    init(_ span: Span, activities: [Activity], calc: DayCalculator) {
        kind = .span(span)
        name = span.name
        symbol = span.symbol
        memberIDs = nil
        goal = .scaled(
            activities
                .filter { !$0.isHidden && !$0.isOpenEnded }
                .map { Quota(cadence: $0.cadence, target: $0.target) }
        )
        cadence = span.cadence
        anchor = span.anchor(calc)
    }
}

struct ActivityTally: Identifiable, Hashable {
    let activityID: UUID
    let name: String
    let color: CabochonsColor
    let count: Int
    var id: UUID { activityID }
}

/// Where one activity stands in its current period. This is what carries the
/// weight for non-daily activities, which a day rail can't describe.
struct PeriodProgress: Identifiable, Hashable {
    let activityID: UUID
    let name: String
    let color: CabochonsColor
    let count: Int
    let target: Int
    let cadence: Cadence
    let periodLabel: String
    let daysRemaining: Int
    /// Chronological, so this rail shows note tags like every other one.
    var fills: [RailJewel] = []

    var id: UUID { activityID }
    var isOpenEnded: Bool { target == 0 }
    var isMet: Bool { target > 0 && count >= target }
    var remaining: Int { max(0, target - count) }
}

/// Where one scope stands in its current period — a tag this week, or Today
/// today. The rail is mixed-colour, and the rail *is* the breakdown: you can
/// see which member each jewel came from.
struct ScopeProgress: Identifiable, Hashable {
    /// Nil is Today.
    let tagID: Tag.ID?
    let name: String
    let count: Int
    let target: Int
    let cadence: Cadence
    let periodLabel: String
    let daysRemaining: Int
    /// Chronological across every member.
    var fills: [RailJewel] = []
    /// Members with at least one jewel this period, in sidebar order.
    var tallies: [ActivityTally] = []

    var id: Tag.ID? { tagID }
    var isMet: Bool { target > 0 && count >= target }
    var remaining: Int { max(0, target - count) }
    var overflow: Int { max(0, count - target) }
}

// MARK: - Computation

enum Stats {

    // MARK: Single activity

    static func compute(for activity: Activity, calc: DayCalculator) -> PeriodStats {
        periodStats(
            entries: activity.jewels.map { LoggedJewel($0, of: activity) },
            target: { _, _ in activity.target },
            cadence: activity.cadence,
            anchor: activity.createdAt,
            calc: calc
        )
    }

    // MARK: A scope

    /// Every member's jewels measured against the scope's own cadence. Hidden
    /// members still contribute — their jewels were earned — it's only the
    /// forward-looking surfaces that drop them.
    static func compute(for scope: Scope, activities: [Activity], calc: DayCalculator) -> PeriodStats {
        periodStats(
            entries: entries(of: scope, in: activities),
            target: { scope.target(from: $0, to: $1, calc: calc) },
            cadence: scope.cadence,
            anchor: scope.anchor,
            calc: calc
        )
    }

    /// Every jewel belonging to a scope's members, unsorted.
    static func entries(of scope: Scope, in activities: [Activity]) -> [LoggedJewel] {
        activities
            .filter { scope.contains($0.id) }
            .flatMap { activity in activity.jewels.map { LoggedJewel($0, of: activity) } }
    }

    /// The shared engine. Buckets entries into periods of `cadence` counted
    /// from `anchor`, then measures each bucket against its `target` (given
    /// the period's start and exclusive end, since a month's can differ from
    /// the next). Doesn't care whether the entries came from one activity or
    /// several.
    private static func periodStats(
        entries: [LoggedJewel],
        target: (Date, Date) -> Int,
        cadence: Cadence,
        anchor: Date,
        calc: DayCalculator
    ) -> PeriodStats {
        var byPeriod: [Int: [LoggedJewel]] = [:]
        for entry in entries {
            let index = calc.periodIndex(for: entry.timestamp, cadence: cadence, anchor: anchor)
            byPeriod[index, default: []].append(entry)
        }
        let counts = byPeriod.mapValues(\.count)

        let currentIndex = calc.currentPeriodIndex(cadence: cadence, anchor: anchor)

        func summary(_ index: Int) -> PeriodSummary {
            let inPeriod = (byPeriod[index] ?? []).sorted { $0.timestamp < $1.timestamp }
            let start = calc.periodStart(index: index, cadence: cadence, anchor: anchor)
            let end = calc.periodEnd(index: index, cadence: cadence, anchor: anchor)
            return PeriodSummary(
                index: index,
                start: start,
                end: end,
                count: inPeriod.count,
                target: target(start, end),
                fills: inPeriod.map(\.rail)
            )
        }

        // The current period always shows, even empty — it's the one you can
        // still act on.
        var indices = Set(counts.keys)
        indices.insert(currentIndex)
        let summaries = indices.sorted(by: >).map(summary)
        let met = Set(summaries.filter(\.isMet).map(\.index))
        let kept = Set(summaries.filter(\.keepsStreak).map(\.index))

        let current = summary(currentIndex)

        var stats = PeriodStats()
        stats.total = entries.count
        stats.target = current.target
        stats.cadence = cadence
        stats.periodsLogged = counts.count
        stats.periodsMet = met.count
        stats.best = summaries.max { $0.count < $1.count }
        stats.current = current
        stats.periods = summaries
        stats.currentStreak = currentStreak(met: kept, current: currentIndex)
        stats.longestStreak = longestStreak(met: kept)
        return stats
    }

    static func progress(for scope: Scope, activities: [Activity], calc: DayCalculator) -> ScopeProgress {
        let cadence = scope.cadence
        let anchor = scope.anchor
        let index = calc.currentPeriodIndex(cadence: cadence, anchor: anchor)

        let inPeriod = entries(of: scope, in: activities)
            .filter { calc.periodIndex(for: $0.timestamp, cadence: cadence, anchor: anchor) == index }
            .sorted { $0.timestamp < $1.timestamp }

        let start = calc.periodStart(index: index, cadence: cadence, anchor: anchor)
        let end = calc.periodEnd(index: index, cadence: cadence, anchor: anchor)

        return ScopeProgress(
            tagID: scope.tagID,
            name: scope.name,
            count: inPeriod.count,
            target: scope.target(from: start, to: end, calc: calc),
            cadence: cadence,
            periodLabel: calc.periodLabel(index: index, cadence: cadence, anchor: anchor),
            daysRemaining: max(0, calc.daysBetween(calc.today, end)),
            fills: inPeriod.map(\.rail),
            tallies: tallies(of: inPeriod, in: activities)
        )
    }

    /// Per-member counts in sidebar order rather than by count, so the legend
    /// colours stay in the same place day to day.
    static func tallies(of entries: [LoggedJewel], in activities: [Activity]) -> [ActivityTally] {
        var counts: [UUID: Int] = [:]
        for entry in entries { counts[entry.activityID, default: 0] += 1 }
        return activities
            .filter { counts[$0.id] != nil }
            .map { ActivityTally(activityID: $0.id, name: $0.name, color: $0.color, count: counts[$0.id] ?? 0) }
    }

    static func progress(for activity: Activity, calc: DayCalculator) -> PeriodProgress {
        let cadence = activity.cadence
        let anchor = activity.createdAt
        let index = calc.currentPeriodIndex(cadence: cadence, anchor: anchor)

        let inPeriod = activity.jewels
            .filter { calc.periodIndex(for: $0.timestamp, cadence: cadence, anchor: anchor) == index }
            .sorted { $0.timestamp < $1.timestamp }

        let end = calc.periodEnd(index: index, cadence: cadence, anchor: anchor)

        return PeriodProgress(
            activityID: activity.id,
            name: activity.name,
            color: activity.color,
            count: inPeriod.count,
            target: activity.target,
            cadence: cadence,
            periodLabel: calc.periodLabel(index: index, cadence: cadence, anchor: anchor),
            daysRemaining: max(0, calc.daysBetween(calc.today, end)),
            fills: inPeriod.map { RailJewel(activity.color, note: $0.note) }
        )
    }
    
    // MARK: Weekday affinity

    static func weekdayProfile(for activity: Activity, calc: DayCalculator) -> WeekdayProfile {
        weekdayProfile(
            timestamps: activity.jewels.map(\.timestamp),
            since: activity.createdAt,
            calc: calc
        )
    }

    /// Every activity on one profile. Opportunities run from the oldest
    /// activity's creation, since that's when the app started asking anything.
    static func weekdayProfile(activities: [Activity], calc: DayCalculator) -> WeekdayProfile {
        weekdayProfile(
            timestamps: activities.flatMap { $0.jewels.map(\.timestamp) },
            since: activities.map(\.createdAt).min() ?? calc.today,
            calc: calc
        )
    }

    private static func weekdayProfile(
        timestamps: [Date],
        since start: Date,
        calc: DayCalculator
    ) -> WeekdayProfile {
        // Index by weekday directly; slot 0 is unused.
        var counts = [Int](repeating: 0, count: 8)
        for timestamp in timestamps {
            counts[calc.weekday(for: timestamp)] += 1
        }

        // How many of each weekday fall in [creation day, today]?
        let firstDay = calc.day(for: start)
        let firstWeekday = calc.weekday(for: firstDay)
        let daysLived = max(0, calc.daysBetween(firstDay, calc.today)) + 1

        let entries = (1...7).map { weekday -> WeekdayProfile.Entry in
            let offset = (weekday - firstWeekday + 7) % 7   // days until first occurrence
            let occurrences = offset < daysLived ? (daysLived - offset + 6) / 7 : 0
            return WeekdayProfile.Entry(
                weekday: weekday,
                count: counts[weekday],
                opportunities: occurrences
            )
        }
        return WeekdayProfile(entries: entries)
    }
    
    // MARK: Hour affinity

    static func hourProfile(for activity: Activity, calc: DayCalculator) -> HourProfile {
        hourProfile(timestamps: activity.jewels.map(\.timestamp), calc: calc)
    }

    static func hourProfile(activities: [Activity], calc: DayCalculator) -> HourProfile {
        hourProfile(timestamps: activities.flatMap { $0.jewels.map(\.timestamp) }, calc: calc)
    }

    private static func hourProfile(timestamps: [Date], calc: DayCalculator) -> HourProfile {
        var counts = [Int](repeating: 0, count: 24)
        for timestamp in timestamps {
            counts[calc.hour(for: timestamp)] += 1
        }
        return HourProfile(counts: counts)
    }
    
    // MARK: - Hour affinity

    /// Jewels by hour of day. No opportunity correction — every day has every
    /// hour — so counts are the truth here. Reflects when you logged, not when
    /// you did the thing; batch-loggers will get a batch-logging chart.
    struct HourProfile: Hashable {
        /// Index is the hour, 0…23.
        let counts: [Int]

        struct Window: Hashable {
            let start: Int
            let width: Int
            let count: Int
            /// Exclusive, wrapped.
            var end: Int { (start + width) % 24 }
            func contains(_ hour: Int) -> Bool {
                (0..<width).contains { (start + $0) % 24 == hour }
            }
        }

        var total: Int { counts.reduce(0, +) }
        var peak: Int { counts.max() ?? 0 }

        /// The busiest run of `width` consecutive hours, allowed to cross midnight.
        func busiestWindow(width: Int = 2) -> Window? {
            guard total > 0 else { return nil }
            var best: Window?
            for start in 0..<24 {
                let count = (0..<width).reduce(0) { $0 + counts[(start + $1) % 24] }
                if count > (best?.count ?? -1) {
                    best = Window(start: start, width: width, count: count)
                }
            }
            return best
        }
    }

    // MARK: Streaks

    /// Consecutive periods in which the target was met.
    ///
    /// The current period is skipped rather than counted as a miss — it isn't
    /// over yet. That's what stops a monthly streak from collapsing at midnight
    /// on the 1st, and it's the same rule that used to keep a daily streak
    /// alive until the day actually ended.
    static func currentStreak(met: Set<Int>, current: Int) -> Int {
        var cursor = current
        if !met.contains(cursor) { cursor -= 1 }

        var streak = 0
        while met.contains(cursor) {
            streak += 1
            cursor -= 1
        }
        return streak
    }

    static func longestStreak(met: Set<Int>) -> Int {
        var longest = 0
        var run = 0
        var previous: Int?

        for index in met.sorted() {
            if let previous, index == previous + 1 {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = index
        }
        return longest
    }

    /// A streak is at risk while the period that would extend it hasn't
    /// kept it yet.
    static func streakAtRisk(currentStreak: Int, current: PeriodSummary?) -> Bool {
        currentStreak > 0 && current?.keepsStreak != true
    }
}

// MARK: - Sidebar order

/// How the sidebar lists activities. `custom` is the order they're stored in;
/// the rest are computed on every draw and never written back.
enum ActivityOrder: String, CaseIterable, Identifiable {
    case custom
    case period
    case recentlyUpdated
    case leastRecentlyUpdated
    case longestToComplete
    case shortestToComplete

    var id: String { rawValue }

    var label: String {
        switch self {
        case .custom:               "Custom"
        case .period:               "Period"
        case .recentlyUpdated:      "Last updated"
        case .leastRecentlyUpdated: "Least recently updated"
        case .longestToComplete:    "Longest to complete"
        case .shortestToComplete:   "Shortest to complete"
        }
    }

    func sorted(_ activities: [Activity], calc: DayCalculator) -> [Activity] {
        if self == .custom { return activities }

        // Open-ended activities ask for no period, so nothing about them can be
        // measured against the others. They go last, by name, whatever the order.
        let bounded = activities.filter { !$0.isOpenEnded }
        let openEnded = activities
            .filter(\.isOpenEnded)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let ranked: [Activity]
        switch self {
        case .custom:
            ranked = bounded
        case .period:
            ranked = Self.sort(bounded, key: { Self.days(in: $0.cadence) }, ascending: true)
        case .recentlyUpdated:
            ranked = Self.sort(bounded, key: { Self.lastUpdated($0) }, ascending: false)
        case .leastRecentlyUpdated:
            ranked = Self.sort(bounded, key: { Self.lastUpdated($0) }, ascending: true)
        case .longestToComplete:
            ranked = Self.sort(bounded, key: { Self.timeToComplete($0, calc: calc) }, ascending: false)
        case .shortestToComplete:
            ranked = Self.sort(bounded, key: { Self.timeToComplete($0, calc: calc) }, ascending: true)
        }
        return ranked + openEnded
    }

    // MARK: Keys

    /// Rough length of a cadence, so "every 2 weeks" falls between weekly and
    /// monthly. Months are counted as 30 days: only their order matters here.
    private static func days(in cadence: Cadence) -> Int {
        switch cadence.unit {
        case .day:   cadence.count
        case .week:  cadence.count * 7
        case .month: cadence.count * 30
        }
    }

    /// The newest jewel, or when the activity was made if it has none yet.
    private static func lastUpdated(_ activity: Activity) -> Date {
        activity.jewels.map(\.timestamp).max() ?? activity.createdAt
    }

    /// How long, on average, a met period took from its opening to the jewel
    /// that met its target. Nil when there's no target or no met period yet.
    private static func timeToComplete(_ activity: Activity, calc: DayCalculator) -> TimeInterval? {
        guard activity.target > 0 else { return nil }

        let byPeriod = Dictionary(grouping: activity.jewels) {
            calc.periodIndex(for: $0.timestamp, cadence: activity.cadence, anchor: activity.createdAt)
        }

        let durations: [TimeInterval] = byPeriod.compactMap { index, jewels in
            guard jewels.count >= activity.target else { return nil }
            let opening = calc.periodStart(index: index, cadence: activity.cadence, anchor: activity.createdAt)
            let met = jewels.map(\.timestamp).sorted()[activity.target - 1]
            return met.timeIntervalSince(opening)
        }
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }

    /// Nil keys sort last in either direction, so an activity with nothing to
    /// measure doesn't float to the top of "shortest".
    private static func sort<Key: Comparable>(
        _ activities: [Activity],
        key: (Activity) -> Key?,
        ascending: Bool
    ) -> [Activity] {
        activities.sorted { lhs, rhs in
            switch (key(lhs), key(rhs)) {
            case let (l?, r?) where l != r:
                return ascending ? l < r : l > r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }
}
