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

    func stats(for activity: Activity) -> ActivityStats {
        Stats.compute(for: activity, calc: calc)
    }

    func todayCount(for activity: Activity) -> Int {
        let today = calc.today
        return activity.jewels.reduce(into: 0) { total, jewel in
            if calc.day(for: jewel.timestamp) == today { total += 1 }
        }
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

    /// Removes the most recent jewel from today. Misfires happen.
    @discardableResult
    func removeLastToday(_ id: Activity.ID) -> Bool {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return false }
        let today = calc.today
        let candidates = activities[index].jewels
            .enumerated()
            .filter { calc.day(for: $0.element.timestamp) == today }
            .max { $0.element.timestamp < $1.element.timestamp }
        guard let target = candidates else { return false }
        activities[index].jewels.remove(at: target.offset)
        save()
        return true
    }

    func remove(jewel: Jewel.ID, from id: Activity.ID) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[index].jewels.removeAll { $0.id == jewel }
        save()
    }

    func jewels(on day: Date, for activity: Activity) -> [Jewel] {
        activity.jewels
            .filter { calc.day(for: $0.timestamp) == day }
            .sorted { $0.timestamp > $1.timestamp }
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

    /// Plain-text export. Every logged timestamp, one per line.
    func exportCSV() -> String {
        var lines = ["activity,color,target,timestamp"]
        let formatter = ISO8601DateFormatter()
        for activity in activities {
            let name = activity.name.replacingOccurrences(of: "\"", with: "\"\"")
            for jewel in activity.jewels.sorted(by: { $0.timestamp < $1.timestamp }) {
                lines.append("\"\(name)\",\(activity.color.rawValue),\(activity.dailyTarget),\(formatter.string(from: jewel.timestamp))")
            }
        }
        return lines.joined(separator: "\n")
    }
}
