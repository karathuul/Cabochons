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
    let color: MateriaColor
    var note: String? = nil

    var hasNote: Bool {
        !(note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var rail: RailJewel { RailJewel(color, note: note) }

    init(id: UUID, timestamp: Date, activityID: UUID, activityName: String, color: MateriaColor, note: String? = nil) {
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
}

/// Everything measured against one cadence: totals, streaks, and every period
/// ever logged. An activity and a tag both produce one of these — the only
/// difference is whose jewels went in.
struct PeriodStats {
    var total: Int = 0
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

// MARK: - Combined across all activities

struct ActivityTally: Identifiable, Hashable {
    let activityID: UUID
    let name: String
    let color: MateriaColor
    let count: Int
    var id: UUID { activityID }
}

/// Every jewel earned on one calendar day, from every activity, in the order
/// they were earned. The rail reads left to right as the day progressed.
struct CombinedDay: Identifiable, Hashable {
    let day: Date
    /// Chronological, earliest first.
    let entries: [LoggedJewel]
    /// Only daily-cadence activities contribute sockets — see `Stats.combine`.
    let capacity: Int
    let tallies: [ActivityTally]

    var id: Date { day }
    var count: Int { entries.count }
    var isMastered: Bool { capacity > 0 && count >= capacity }
    var overflow: Int { max(0, count - capacity) }
    var fills: [RailJewel] { entries.map(\.rail) }
}

/// Where one activity stands in its current period. This is what carries the
/// weight for non-daily activities, which a day rail can't describe.
struct PeriodProgress: Identifiable, Hashable {
    let activityID: UUID
    let name: String
    let color: MateriaColor
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

/// Where one tag stands in its current period. The tag equivalent of
/// `PeriodProgress`, with a mixed-colour rail — the rail *is* the breakdown:
/// you can see which member each jewel came from.
struct TagProgress: Identifiable, Hashable {
    let tagID: UUID
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

    var id: UUID { tagID }
    var isMet: Bool { target > 0 && count >= target }
    var remaining: Int { max(0, target - count) }
    var overflow: Int { max(0, count - target) }
}

struct CombinedStats {
    var total: Int = 0
    /// Sum of targets for daily activities only.
    var capacity: Int = 0
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var daysLogged: Int = 0
    var masteredDays: Int = 0
    /// Newest first.
    var days: [CombinedDay] = []
    var today: CombinedDay?
    var progress: [PeriodProgress] = []
    /// One per tag, in the user's tag order.
    var tagProgress: [TagProgress] = []

    var todayCount: Int { today?.count ?? 0 }

    var average: Double {
        daysLogged == 0 ? 0 : Double(total) / Double(daysLogged)
    }
}

// MARK: - Computation

enum Stats {

    // MARK: Single activity

    static func compute(for activity: Activity, calc: DayCalculator) -> PeriodStats {
        periodStats(
            entries: activity.jewels.map { LoggedJewel($0, of: activity) },
            target: activity.target,
            cadence: activity.cadence,
            anchor: activity.createdAt,
            calc: calc
        )
    }

    // MARK: Single tag

    /// Every member's jewels measured against the tag's own cadence. Hidden
    /// members still contribute — their jewels were earned — it's only the
    /// forward-looking surfaces that drop them.
    static func compute(for tag: Tag, activities: [Activity], calc: DayCalculator) -> PeriodStats {
        periodStats(
            entries: entries(of: tag, in: activities),
            target: tag.target,
            cadence: tag.cadence,
            anchor: tag.createdAt,
            calc: calc
        )
    }

    /// Every jewel belonging to a tag's members, unsorted.
    static func entries(of tag: Tag, in activities: [Activity]) -> [LoggedJewel] {
        activities
            .filter { tag.contains($0.id) }
            .flatMap { activity in activity.jewels.map { LoggedJewel($0, of: activity) } }
    }

    /// The shared engine. Buckets entries into periods of `cadence` counted
    /// from `anchor`, then measures each bucket against `target`. Doesn't care
    /// whether the entries came from one activity or several.
    private static func periodStats(
        entries: [LoggedJewel],
        target: Int,
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
            return PeriodSummary(
                index: index,
                start: calc.periodStart(index: index, cadence: cadence, anchor: anchor),
                end: calc.periodEnd(index: index, cadence: cadence, anchor: anchor),
                count: inPeriod.count,
                target: target,
                fills: inPeriod.map(\.rail)
            )
        }

        // The current period always shows, even empty — it's the one you can
        // still act on.
        var indices = Set(counts.keys)
        indices.insert(currentIndex)
        let summaries = indices.sorted(by: >).map(summary)
        let met = Set(summaries.filter(\.isMet).map(\.index))

        var stats = PeriodStats()
        stats.total = entries.count
        stats.target = target
        stats.cadence = cadence
        stats.periodsLogged = counts.count
        stats.periodsMet = met.count
        stats.best = summaries.max { $0.count < $1.count }
        stats.current = summary(currentIndex)
        stats.periods = summaries
        stats.currentStreak = currentStreak(met: met, current: currentIndex)
        stats.longestStreak = longestStreak(met: met)
        return stats
    }

    // MARK: All activities on one rail

    static func combine(activities: [Activity], tags: [Tag] = [], calc: DayCalculator) -> CombinedStats {
        // Only daily activities can define a day's sockets. A monthly activity
        // owes you nothing in particular today, so folding its target into a
        // daily capacity would invent a debt that doesn't exist. Hidden ones
        // ask for nothing at all.
        let capacity = activities
            .filter { $0.cadence.isDaily && !$0.isHidden }
            .reduce(0) { $0 + $1.target }

        var byDay: [Date: [LoggedJewel]] = [:]
        for activity in activities {
            for jewel in activity.jewels {
                let entry = LoggedJewel(
                    id: jewel.id,
                    timestamp: jewel.timestamp,
                    activityID: activity.id,
                    activityName: activity.name,
                    color: activity.color,
                    note: jewel.note
                )
                byDay[calc.day(for: jewel.timestamp), default: []].append(entry)
            }
        }

        // Preserve sidebar order in the tallies rather than sorting by count,
        // so the legend colours stay in the same place day to day.
        let order = Dictionary(
            uniqueKeysWithValues: activities.enumerated().map { ($0.element.id, $0.offset) }
        )

        let days: [CombinedDay] = byDay.keys.sorted(by: >).map { day in
            let entries = (byDay[day] ?? []).sorted { $0.timestamp < $1.timestamp }
            var counts: [UUID: Int] = [:]
            for entry in entries { counts[entry.activityID, default: 0] += 1 }

            let tallies = activities
                .filter { counts[$0.id] != nil }
                .map {
                    ActivityTally(
                        activityID: $0.id,
                        name: $0.name,
                        color: $0.color,
                        count: counts[$0.id] ?? 0
                    )
                }
                .sorted { (order[$0.activityID] ?? 0) < (order[$1.activityID] ?? 0) }

            return CombinedDay(day: day, entries: entries, capacity: capacity, tallies: tallies)
        }

        var stats = CombinedStats()
        stats.capacity = capacity
        stats.total = activities.reduce(0) { $0 + $1.jewels.count }
        stats.days = days
        stats.daysLogged = days.count
        stats.masteredDays = days.filter(\.isMastered).count
        stats.today = days.first { $0.day == calc.today }
        stats.currentStreak = currentStreak(days: Set(byDay.keys), calc: calc)
        stats.longestStreak = longestStreak(days: Set(byDay.keys), calc: calc)
        // Jewels from hidden activities stay on every rail — they were earned.
        // Only the forward-looking list drops them.
        stats.progress = activities
            .filter { !$0.isHidden }
            .map { progress(for: $0, calc: calc) }
        stats.tagProgress = tags.map { progress(for: $0, activities: activities, calc: calc) }
        return stats
    }

    static func progress(for tag: Tag, activities: [Activity], calc: DayCalculator) -> TagProgress {
        let cadence = tag.cadence
        let anchor = tag.createdAt
        let index = calc.currentPeriodIndex(cadence: cadence, anchor: anchor)

        let inPeriod = entries(of: tag, in: activities)
            .filter { calc.periodIndex(for: $0.timestamp, cadence: cadence, anchor: anchor) == index }
            .sorted { $0.timestamp < $1.timestamp }

        var counts: [UUID: Int] = [:]
        for entry in inPeriod { counts[entry.activityID, default: 0] += 1 }

        // Sidebar order, same as the day rail's tallies.
        let tallies = activities
            .filter { counts[$0.id] != nil }
            .map { ActivityTally(activityID: $0.id, name: $0.name, color: $0.color, count: counts[$0.id] ?? 0) }

        let end = calc.periodEnd(index: index, cadence: cadence, anchor: anchor)

        return TagProgress(
            tagID: tag.id,
            name: tag.name,
            count: inPeriod.count,
            target: tag.target,
            cadence: cadence,
            periodLabel: calc.periodLabel(index: index, cadence: cadence, anchor: anchor),
            daysRemaining: max(0, calc.daysBetween(calc.today, end)),
            fills: inPeriod.map(\.rail),
            tallies: tallies
        )
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

    // MARK: Day streaks, for the combined view

    static func currentStreak(days: Set<Date>, calc: DayCalculator) -> Int {
        var cursor = calc.today
        if !days.contains(cursor) {
            cursor = calc.offsetting(cursor, by: -1)
        }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            cursor = calc.offsetting(cursor, by: -1)
        }
        return streak
    }

    static func longestStreak(days: Set<Date>, calc: DayCalculator) -> Int {
        var longest = 0
        var run = 0
        var previous: Date?

        for day in days.sorted() {
            if let previous, calc.daysBetween(previous, day) == 1 {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }
        return longest
    }

    static func streakAtRisk(currentStreak: Int, today: Int) -> Bool {
        currentStreak > 0 && today == 0
    }
}
