import Foundation

// MARK: - A jewel with its provenance attached

/// A jewel plus the activity that produced it. The combined day rail mixes
/// jewels from every activity, so colour and name have to travel with them.
struct LoggedJewel: Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let activityID: UUID
    let activityName: String
    let color: MateriaColor
}

// MARK: - Per-activity

struct DaySummary: Identifiable, Hashable {
    let day: Date
    let count: Int
    let target: Int

    var id: Date { day }
    var isMastered: Bool { target > 0 && count >= target }
    var overflow: Int { max(0, count - target) }
}

struct ActivityStats {
    var total: Int = 0
    var today: Int = 0
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var daysLogged: Int = 0
    var masteredDays: Int = 0
    var best: DaySummary?
    /// Newest first.
    var days: [DaySummary] = []

    var average: Double {
        daysLogged == 0 ? 0 : Double(total) / Double(daysLogged)
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
    /// Sum of every activity's daily target.
    let capacity: Int
    let tallies: [ActivityTally]

    var id: Date { day }
    var count: Int { entries.count }
    var isMastered: Bool { capacity > 0 && count >= capacity }
    var overflow: Int { max(0, count - capacity) }
    var fills: [MateriaColor] { entries.map(\.color) }
}

struct CombinedStats {
    var total: Int = 0
    var capacity: Int = 0
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var daysLogged: Int = 0
    var masteredDays: Int = 0
    /// Newest first.
    var days: [CombinedDay] = []
    var today: CombinedDay?

    var todayCount: Int { today?.count ?? 0 }

    var average: Double {
        daysLogged == 0 ? 0 : Double(total) / Double(daysLogged)
    }
}

// MARK: - Computation

enum Stats {

    // MARK: Single activity

    static func compute(for activity: Activity, calc: DayCalculator) -> ActivityStats {
        var counts: [Date: Int] = [:]
        for jewel in activity.jewels {
            counts[calc.day(for: jewel.timestamp), default: 0] += 1
        }

        let target = activity.dailyTarget
        let summaries = counts.keys.sorted(by: >).map {
            DaySummary(day: $0, count: counts[$0] ?? 0, target: target)
        }

        var stats = ActivityStats()
        stats.total = activity.jewels.count
        stats.today = counts[calc.today] ?? 0
        stats.daysLogged = counts.count
        stats.masteredDays = summaries.filter(\.isMastered).count
        stats.best = summaries.max { $0.count < $1.count }
        stats.days = summaries
        stats.currentStreak = currentStreak(days: Set(counts.keys), calc: calc)
        stats.longestStreak = longestStreak(days: Set(counts.keys), calc: calc)
        return stats
    }

    // MARK: All activities on one rail

    static func combine(activities: [Activity], calc: DayCalculator) -> CombinedStats {
        let capacity = activities.reduce(0) { $0 + $1.dailyTarget }

        var byDay: [Date: [LoggedJewel]] = [:]
        for activity in activities {
            for jewel in activity.jewels {
                let entry = LoggedJewel(
                    id: jewel.id,
                    timestamp: jewel.timestamp,
                    activityID: activity.id,
                    activityName: activity.name,
                    color: activity.color
                )
                byDay[calc.day(for: jewel.timestamp), default: []].append(entry)
            }
        }

        // Preserve sidebar order in the tallies rather than sorting by count,
        // so the legend colours stay in the same place day to day.
        let order = Dictionary(uniqueKeysWithValues: activities.enumerated().map { ($0.element.id, $0.offset) })

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
        return stats
    }

    // MARK: Streaks

    /// Counts back from today. A day with no jewels yet doesn't break the
    /// streak until it's over — so the count anchors at yesterday until you
    /// log, rather than dropping to zero every midnight.
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
