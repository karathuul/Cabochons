import Foundation
import Observation
internal import SwiftUI

/// On-disk shape. Versioned so the format can change later without guessing.
private struct LogFile: Codable {
    var version: Int = 1
    var dayStartHour: Int = 0
    var activities: [Activity] = []
}

@Observable
final class LogStore {

    private(set) var activities: [Activity] = []

    /// Hour at which a new day begins. 0 = midnight.
    var dayStartHour: Int = 0 {
        didSet { if dayStartHour != oldValue { save() } }
    }

    var calc: DayCalculator {
        DayCalculator(dayStartHour: dayStartHour)
    }

    // MARK: Lookup

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

    /// Every socket the day has, summed across activities. The day's loadout is
    /// the union of what each activity contributes.
    var dailyCapacity: Int {
        activities.reduce(0) { $0 + $1.dailyTarget }
    }

    func todayCount(for activity: Activity) -> Int {
        let today = calc.today
        return activity.jewels.reduce(into: 0) { total, jewel in
            if calc.day(for: jewel.timestamp) == today { total += 1 }
        }
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
                        color: activity.color
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
    func slot(_ id: Activity.ID, at date: Date = .now) -> Bool {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return false }
        activities[index].jewels.append(Jewel(timestamp: date))
        save()
        return true
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

    private static let fileName = "materialog.json"

    private var fileURL: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.documentsDirectory

        let folder = base.appendingPathComponent("MateriaLog", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(Self.fileName)
    }

    init() {
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(LogFile.self, from: data) else { return }
        activities = file.activities
        dayStartHour = file.dayStartHour
    }

    func save() {
        let file = LogFile(dayStartHour: dayStartHour, activities: activities)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Chronological across all activities, so it matches the day rail's order.
    func exportCSV() -> String {
        var lines = ["timestamp,activity,colour"]
        let formatter = ISO8601DateFormatter()
        for entry in allEntries() {
            let name = entry.activityName.replacingOccurrences(of: "\"", with: "\"\"")
            lines.append("\(formatter.string(from: entry.timestamp)),\"\(name)\",\(entry.color.hex)")
        }
        return lines.joined(separator: "\n")
    }
}
