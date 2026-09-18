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

    var rail: RailJewel { RailJewel(color, hasNote: hasNote) }
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

struct ActivityStats {
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

    var todayCount: Int { today?.count ?? 0 }

    var average: Double {
        daysLogged == 0 ? 0 : Double(total) / Double(daysLogged)
    }
}

// MARK: - Computation

enum Stats {

    // MARK: Single activity

    static func compute(for activity: Activity, calc: DayCalculator) -> ActivityStats {
        let cadence = activity.cadence
        let anchor = activity.createdAt

        var byPeriod: [Int: [Jewel]] = [:]
        for jewel in activity.jewels {
            let index = calc.periodIndex(for: jewel.timestamp, cadence: cadence, anchor: anchor)
            byPeriod[index, default: []].append(jewel)
        }
        let counts = byPeriod.mapValues(\.count)

        let currentIndex = calc.currentPeriodIndex(cadence: cadence, anchor: anchor)

        func summary(_ index: Int) -> PeriodSummary {
            let jewels = (byPeriod[index] ?? []).sorted { $0.timestamp < $1.timestamp }
            return PeriodSummary(
                index: index,
                start: calc.periodStart(index: index, cadence: cadence, anchor: anchor),
                end: calc.periodEnd(index: index, cadence: cadence, anchor: anchor),
                count: jewels.count,
                target: activity.target,
                fills: jewels.map { RailJewel(activity.color, hasNote: $0.hasNote) }
            )
        }

        // The current period always shows, even empty — it's the one you can
        // still act on.
        var indices = Set(counts.keys)
        indices.insert(currentIndex)
        let summaries = indices.sorted(by: >).map(summary)
        let met = Set(summaries.filter(\.isMet).map(\.index))

        var stats = ActivityStats()
        stats.total = activity.jewels.count
        stats.target = activity.target
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

    static func combine(activities: [Activity], calc: DayCalculator) -> CombinedStats {
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
        return stats
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
            fills: inPeriod.map { RailJewel(activity.color, hasNote: $0.hasNote) }
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
