import WidgetKit
internal import SwiftUI

/// A single render's worth of state, computed from the shared file. Everything
/// the views need is precomputed here so the views stay dumb and fast — widget
/// bodies are snapshotted and shouldn't be doing work.
struct CabochonsEntry: TimelineEntry {
    let date: Date
    let todayCount: Int
    let capacity: Int
    let streak: Int
    let fills: [RailJewel]
    let progress: [PeriodProgress]
    let hasActivities: Bool

    /// Undefined when no daily activities exist, so the gauge is suppressed.
    var fraction: Double {
        capacity > 0 ? min(1, Double(todayCount) / Double(capacity)) : 0
    }
    var isMastered: Bool { capacity > 0 && todayCount >= capacity }

    static func build(from file: LogFile, date: Date = .now) -> CabochonsEntry {
        let calc = DayCalculator(dayStartHour: file.dayStartHour)
        let combined = Stats.combine(activities: file.activities, calc: calc)
        return CabochonsEntry(
            date: date,
            todayCount: combined.todayCount,
            capacity: combined.capacity,
            streak: combined.currentStreak,
            fills: combined.today?.fills ?? [],
            progress: combined.progress,
            hasActivities: !file.activities.filter { !$0.isHidden }.isEmpty
        )
    }

    /// Shown in the gallery and while real data loads. Deliberately plausible
    /// rather than empty, so the widget doesn't look broken when previewed.
    static let placeholder = CabochonsEntry(
        date: .now,
        todayCount: 3,
        capacity: 4,
        streak: 5,
        fills: [
            RailJewel(.magic),
            // Long enough to show a real flare, not the "ok" minimum.
            RailJewel(.summon, note: "Finally got the tempo right on the second movement, twice in a row."),
            RailJewel(.support)
        ],
        progress: [],
        hasActivities: true
    )
}

struct CabochonsProvider: TimelineProvider {
    func placeholder(in context: Context) -> CabochonsEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (CabochonsEntry) -> Void) {
        completion(context.isPreview ? .placeholder : .build(from: SharedStorage.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CabochonsEntry>) -> Void) {
        let file = SharedStorage.load()
        let entry = CabochonsEntry.build(from: file)

        // The only thing that changes without an app write is the day rolling
        // over — "today" becomes empty. Refresh at the next day boundary; app
        // writes trigger their own reload in between.
        let calc = DayCalculator(dayStartHour: file.dayStartHour)
        let nextDay = calc.offsetting(calc.today, by: 1)
        let refresh = max(nextDay, entry.date.addingTimeInterval(60 * 60))

        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}
