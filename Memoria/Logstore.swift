internal import Foundation
import WidgetKit
import Observation
internal import SwiftUI
internal import AppIntents

@Observable
final class LogStore : Observable {

    static let shared = LogStore()
    
    private(set) var activities: [Activity] = []

    /// Hour at which a new day begins. 0 = midnight.
    var dayStartHour: Int = 0 {
        didSet { if dayStartHour != oldValue, !isLoading { save() } }
    }

    var calc: DayCalculator {
        DayCalculator(dayStartHour: dayStartHour)
    }

    // MARK: Lookup

    /// Everything still in play. Hidden activities keep their jewels but drop
    /// out of every surface that asks you to do something.
    var visibleActivities: [Activity] {
        activities.filter { !$0.isHidden }
    }

    var hiddenActivities: [Activity] {
        activities.filter(\.isHidden)
    }

    func activity(_ id: Activity.ID?) -> Activity? {
        guard let id else { return nil }
        return activities.first { $0.id == id }
    }

    func activityName(_ id: UUID) -> String {
        activities.first { $0.id == id }?.name ?? "Deleted"
    }

    func stats(for activity: Activity) -> ActivityStats {
        Stats.compute(for: activity, calc: calc)
    }

    /// Every activity folded onto one day rail.
    var combined: CombinedStats {
        Stats.combine(activities: activities, calc: calc)
    }

    /// Sockets the day has, from visible daily activities only. A monthly
    /// activity owes nothing in particular today, and a hidden one owes nothing
    /// at all.
    var dailyCapacity: Int {
        activities
            .filter { $0.cadence.isDaily && !$0.isHidden }
            .reduce(0) { $0 + $1.target }
    }

    func todayCount(for activity: Activity) -> Int {
        let today = calc.today
        return activity.jewels.reduce(into: 0) { total, jewel in
            if calc.day(for: jewel.timestamp) == today { total += 1 }
        }
    }

    /// Count within the activity's own current period, which is what its target
    /// is measured against.
    func periodCount(for activity: Activity) -> Int {
        Stats.progress(for: activity, calc: calc).count
    }

    func progress(for activity: Activity) -> PeriodProgress {
        Stats.progress(for: activity, calc: calc)
    }

    /// Every jewel tagged with where it came from, chronological.
    func allEntries() -> [LoggedJewel] {
        activities
            .flatMap { activity in
                activity.jewels.map {
                    LoggedJewel(
                        id: $0.id,
                        timestamp: $0.timestamp,
                        activityID: activity.id,
                        activityName: activity.name,
                        color: activity.color,
                        note: $0.note
                    )
                }
            }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// Newest first, across every activity unless one is named.
    func entries(on day: Date, activityID: UUID? = nil) -> [LoggedJewel] {
        allEntries()
            .filter {
                calc.day(for: $0.timestamp) == day
                    && (activityID == nil || $0.activityID == activityID)
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Newest first, for one activity within one turn of its cadence.
    func entries(in period: PeriodSummary, activityID: UUID) -> [LoggedJewel] {
        allEntries()
            .filter {
                $0.activityID == activityID
                    && $0.timestamp >= period.start
                    && $0.timestamp < period.end
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func jewels(on day: Date, for activity: Activity) -> [Jewel] {
        activity.jewels
            .filter { calc.day(for: $0.timestamp) == day }
            .sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: Mutation

    func add(_ activity: Activity) {
        activities.append(activity)
        save()
    }

    func update(_ activity: Activity) {
        guard let index = activities.firstIndex(where: { $0.id == activity.id }) else { return }
        activities[index] = activity
        save()
    }

    /// Hiding is the reversible option; `delete` is the one that loses jewels.
    func setHidden(_ id: Activity.ID, _ hidden: Bool) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[index].isHidden = hidden
        save()
    }

    func delete(_ id: Activity.ID) {
        activities.removeAll { $0.id == id }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        activities.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// The whole point of the app.
    @discardableResult
    func slot(_ id: Activity.ID, at date: Date = .now, note: String? = nil) -> Bool {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return false }
        activities[index].jewels.append(Jewel(timestamp: date, note: note))
        save()
        return true
    }

    /// Blank or whitespace-only clears the note rather than storing an empty
    /// string, so `hasNote` and the tag can't disagree.
    func setNote(_ text: String, for jewel: Jewel.ID, in id: Activity.ID) {
        guard let activityIndex = activities.firstIndex(where: { $0.id == id }),
              let jewelIndex = activities[activityIndex].jewels.firstIndex(where: { $0.id == jewel })
        else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        activities[activityIndex].jewels[jewelIndex].note = trimmed.isEmpty ? nil : trimmed
        save()
    }

    /// The jewel a "add a note" action should attach to.
    var mostRecentToday: LoggedJewel? {
        entries(on: calc.today).first
    }

    func remove(jewel: Jewel.ID, from id: Activity.ID) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[index].jewels.removeAll { $0.id == jewel }
        save()
    }

    /// Removes today's most recent jewel for one activity.
    @discardableResult
    func removeLastToday(_ id: Activity.ID) -> Bool {
        guard let newest = entries(on: calc.today, activityID: id).first else { return false }
        remove(jewel: newest.id, from: newest.activityID)
        return true
    }

    /// Removes today's most recent jewel whichever activity it came from —
    /// undo on the day rail should pop the last socket you actually filled.
    @discardableResult
    func removeLastToday() -> Bool {
        guard let newest = entries(on: calc.today).first else { return false }
        remove(jewel: newest.id, from: newest.activityID)
        return true
    }

    // MARK: Persistence

    /// Guards the didSet on `dayStartHour` from writing during load, when we're
    /// only mirroring what's already on disk.
    private var isLoading = false

    init() {
        SharedStorage.migrateIfNeeded()
        load()
    }

    func load() {
        isLoading = true
        defer { isLoading = false }
        let file = SharedStorage.load()
        activities = file.activities
        dayStartHour = file.dayStartHour
    }

    func save() {
        guard !isLoading else { return }
        SharedStorage.write(LogFile(dayStartHour: dayStartHour, activities: activities))
        // Read-only widgets show today's progress, so every write is a chance
        // for them to be stale. Cheap to ask for a refresh; WidgetKit coalesces.
        WidgetCenter.shared.reloadAllTimelines()
        MemoriaShortcuts.updateAppShortcutParameters()
    }
    
    func replaceContents(with file: LogFile) {
        dayStartHour = file.dayStartHour
        activities = file.activities
        save()
    }

    /// Chronological across all activities, so it matches the day rail's order.
    func exportCSV() -> String {
        var lines = ["timestamp,activity,colour,note"]
        let formatter = ISO8601DateFormatter()
        for entry in allEntries() {
            let name = entry.activityName.replacingOccurrences(of: "\"", with: "\"\"")
            let note = (entry.note ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            lines.append("\(formatter.string(from: entry.timestamp)),\"\(name)\",\(entry.color.hex),\"\(note)\"")
        }
        return lines.joined(separator: "\n")
    }
}
