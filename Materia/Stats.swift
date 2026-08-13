import Foundation

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

enum Stats {

    static func compute(for activity: Activity, calc: DayCalculator) -> ActivityStats {
        var counts: [Date: Int] = [:]
        for jewel in activity.jewels {
            counts[calc.day(for: jewel.timestamp), default: 0] += 1
        }

        let target = activity.dailyTarget
        let descending = counts.keys.sorted(by: >)
        let summaries = descending.map {
            DaySummary(day: $0, count: counts[$0] ?? 0, target: target)
        }

        var stats = ActivityStats()
        stats.total = activity.jewels.count
        stats.today = counts[calc.today] ?? 0
        stats.daysLogged = counts.count
        stats.masteredDays = summaries.filter(\.isMastered).count
        stats.best = summaries.max { $0.count < $1.count }
        stats.days = summaries
        stats.currentStreak = currentStreak(in: counts, calc: calc)
        stats.longestStreak = longestStreak(in: counts, calc: calc)
        return stats
    }

    /// Counts back from today. A day with no jewels yet doesn't break the
    /// streak until it's over — so the count anchors at yesterday until you
    /// log, rather than dropping to zero every midnight.
    private static func currentStreak(in counts: [Date: Int], calc: DayCalculator) -> Int {
        var cursor = calc.today
        if counts[cursor] == nil {
            cursor = calc.offsetting(cursor, by: -1)
        }
        var streak = 0
        while counts[cursor] != nil {
            streak += 1
            cursor = calc.offsetting(cursor, by: -1)
        }
        return streak
    }

    private static func longestStreak(in counts: [Date: Int], calc: DayCalculator) -> Int {
        let ascending = counts.keys.sorted()
        var longest = 0
        var run = 0
        var previous: Date?

        for day in ascending {
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

    /// True when the streak is alive but today is still empty.
    static func streakAtRisk(_ stats: ActivityStats) -> Bool {
        stats.currentStreak > 0 && stats.today == 0
    }
}
