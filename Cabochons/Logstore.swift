internal import Foundation
import WidgetKit
import Observation
internal import SwiftUI
internal import AppIntents

@Observable
final class LogStore : Observable {

    static let shared = LogStore()
    
    private(set) var activities: [Activity] = []
    /// Categories laid across activities, in the user's order. Membership is
    /// on the tag (`Tag.activityIDs`), not the activity.
    private(set) var tags: [Tag] = []

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

    func stats(for activity: Activity) -> PeriodStats {
        Stats.compute(for: activity, calc: calc)
    }

    // MARK: Tags

    func tag(_ id: Tag.ID?) -> Tag? {
        guard let id else { return nil }
        return tags.first { $0.id == id }
    }

    /// Every tag this activity belongs to, in tag order.
    func tags(containing id: Activity.ID) -> [Tag] {
        tags.filter { $0.contains(id) }
    }

    func stats(for tag: Tag) -> PeriodStats {
        Stats.compute(for: tag, activities: activities, calc: calc)
    }

    func progress(for tag: Tag) -> TagProgress {
        Stats.progress(for: tag, activities: activities, calc: calc)
    }

    /// Members that still have a button: visible ones, in sidebar order.
    func visibleMembers(of tag: Tag) -> [Activity] {
        tag.visibleMembers(of: activities)
    }

    /// Sockets today's rail has for this tag.
    func dailyCapacity(for tag: Tag) -> Int {
        tag.dailyCapacity(of: activities)
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

    /// Newest first, from a tag's members only.
    func entries(on day: Date, in tag: Tag) -> [LoggedJewel] {
        entries(on: day).filter { tag.contains($0.activityID) }
    }

    /// Newest first, from a tag's members within one of its periods.
    func entries(in period: PeriodSummary, tag: Tag) -> [LoggedJewel] {
        allEntries()
            .filter {
                tag.contains($0.activityID)
                    && $0.timestamp >= period.start
                    && $0.timestamp < period.end
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

    /// Also prunes the activity from every tag, so no tag carries a dangling
    /// member ID around forever.
    func delete(_ id: Activity.ID) {
        activities.removeAll { $0.id == id }
        for index in tags.indices {
            tags[index].activityIDs.removeAll { $0 == id }
        }
        save()
    }

    // MARK: Tag mutation

    func add(_ tag: Tag) {
        tags.append(tag)
        save()
    }

    func update(_ tag: Tag) {
        guard let index = tags.firstIndex(where: { $0.id == tag.id }) else { return }
        tags[index] = tag
        save()
    }

    /// Deleting a tag loses nothing but the tag: every member's jewels are its
    /// own and stay put.
    func delete(tag id: Tag.ID) {
        tags.removeAll { $0.id == id }
        save()
    }

    func moveTags(from source: IndexSet, to destination: Int) {
        tags.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Sets exactly which tags one activity belongs to. Used by the activity
    /// editor, which shows tags as toggles; the source of truth stays on the
    /// tag, this just writes through.
    func setTags(_ tagIDs: Set<Tag.ID>, for activityID: Activity.ID) {
        var changed = false
        for index in tags.indices {
            let should = tagIDs.contains(tags[index].id)
            let does = tags[index].contains(activityID)
            if should, !does {
                tags[index].activityIDs.append(activityID)
                changed = true
            } else if !should, does {
                tags[index].activityIDs.removeAll { $0 == activityID }
                changed = true
            }
        }
        if changed { save() }
    }

    func move(from source: IndexSet, to destination: Int) {
        activities.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Reorders the visible rails among themselves. Hidden activities keep
    /// their slots in the stored list, so unhiding one puts it back where it was.
    func moveVisible(from source: IndexSet, to destination: Int) {
        var reordered = visibleActivities
        reordered.move(fromOffsets: source, toOffset: destination)

        var next = reordered.makeIterator()
        for index in activities.indices where !activities[index].isHidden {
            guard let activity = next.next() else { break }
            activities[index] = activity
        }
        save()
    }

    /// The whole point of the app. Notes arriving here (Siri, Shortcuts) get
    /// the same trim-and-clamp as ones typed in the editor.
    @discardableResult
    func slot(_ id: Activity.ID, at date: Date = .now, note: String? = nil) -> Bool {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return false }
        activities[index].jewels.append(Jewel(timestamp: date, note: NoteRules.normalized(note)))
        save()
        return true
    }

    /// Blank or whitespace-only clears the note rather than storing an empty
    /// string, so `hasNote` and the tag can't disagree. Over-long text is cut
    /// at `NoteRules.limit` — the editor should already prevent that, this is
    /// the backstop.
    func setNote(_ text: String, for jewel: Jewel.ID, in id: Activity.ID) {
        guard let activityIndex = activities.firstIndex(where: { $0.id == id }),
              let jewelIndex = activities[activityIndex].jewels.firstIndex(where: { $0.id == jewel })
        else { return }

        activities[activityIndex].jewels[jewelIndex].note = NoteRules.normalized(text)
        save()
    }

    /// The jewel a tag's "add a note" action should attach to: today's
    /// newest from its members.
    func mostRecentToday(in tag: Tag) -> LoggedJewel? {
        entries(on: calc.today, in: tag).first
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

    /// Undo on a tag-scoped rail should pop the last jewel *on that rail*, not
    /// whatever was logged most recently anywhere.
    @discardableResult
    func removeLastToday(in tag: Tag) -> Bool {
        guard let newest = entries(on: calc.today, in: tag).first else { return false }
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
        tags = file.tags
        dayStartHour = file.dayStartHour
    }

    func save() {
        guard !isLoading else { return }
        SharedStorage.write(LogFile(dayStartHour: dayStartHour, activities: activities, tags: tags))
        // Read-only widgets show today's progress, so every write is a chance
        // for them to be stale. Cheap to ask for a refresh; WidgetKit coalesces.
        WidgetCenter.shared.reloadAllTimelines()
        CabochonsShortcuts.updateAppShortcutParameters()
    }
    
    func replaceContents(with file: LogFile) {
        dayStartHour = file.dayStartHour
        activities = file.activities
        tags = file.tags
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
