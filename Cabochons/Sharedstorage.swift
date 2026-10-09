internal import Foundation

/// The identifier for the App Group container the app and its widget share.
///
/// A widget runs in its own process with its own sandbox, so it cannot see the
/// app's private Application Support directory. An App Group is the shared box
/// both processes can reach — the data file lives there and both read it.
///
/// SET THIS to the group you create in Signing & Capabilities (App Groups),
/// on BOTH the app target and the widget-extension target. The string must
/// match in all three places (here and both entitlements) exactly, or the
/// container URL comes back nil and the widget falls back to an empty read.
enum AppGroup {
    static let identifier = "group.com.qibasin.Cabochons"

    /// The group before the rename. Still listed in the app's entitlements, but
    /// only so `SharedStorage.migrateIfNeeded()` can move the data out of it.
    static let legacyIdentifier = "group.com.qibasin.Memoria"
}

/// On-disk shape. Versioned so the format can change later without guessing.
/// Shared between targets because the widget decodes the same file the app
/// writes.
struct LogFile: Codable {
    /// 1: activities only. 2: adds `tags`.
    var version: Int = 2
    var dayStartHour: Int = 0
    var activities: [Activity] = []
    var tags: [Tag] = []

    init(
        version: Int = 2,
        dayStartHour: Int = 0,
        activities: [Activity] = [],
        tags: [Tag] = []
    ) {
        self.version = version
        self.dayStartHour = dayStartHour
        self.activities = activities
        self.tags = tags
    }

    private enum CodingKeys: String, CodingKey {
        case version, dayStartHour, activities, tags
    }

    /// Written by hand because synthesised decoding treats a non-optional
    /// property as required even when it has a default — the default only
    /// serves the memberwise init. A v1 file has no `tags` key, so without
    /// this it would throw, `SharedStorage.load()` would swallow the throw,
    /// and every jewel would appear to vanish. `encode(to:)` stays synthesised.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        dayStartHour = try container.decodeIfPresent(Int.self, forKey: .dayStartHour) ?? 0
        activities = try container.decodeIfPresent([Activity].self, forKey: .activities) ?? []
        tags = try container.decodeIfPresent([Tag].self, forKey: .tags) ?? []
    }
}

/// The one place that knows where the data file lives and how it's coded.
/// Both `LogStore` (read/write) and the widget (read-only) go through here, so
/// there's a single source of truth for the location and the JSON settings.
enum SharedStorage {
    static let fileName = "cabochons.json"

    /// The data file's name before the rename.
    static let legacyFileName = "memoria.json"

    /// The folder holding the data file: the App Group container when it's
    /// configured, otherwise the app's own Application Support. The fallback
    /// means the app still runs before the group is set up in Xcode — it just
    /// won't share with the widget until then.
    static var containerFolder: URL {
        let base: URL
        if let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.identifier
        ) {
            base = group
        } else {
            base = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? URL.documentsDirectory
        }
        return base.appendingPathComponent("Cabochons", isDirectory: true)
    }

    static var fileURL: URL {
        let folder = containerFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName)
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// Read-only load. Returns an empty file rather than throwing, so a missing
    /// or unreadable file just shows an empty widget instead of crashing it.
    static func load() -> LogFile {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? makeDecoder().decode(LogFile.self, from: data)
        else { return LogFile() }
        return file
    }

    static func write(_ file: LogFile) {
        guard let data = try? makeEncoder().encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Moves data into the current shared container on first launch. Two places
    /// can hold it from before: the pre-rename App Group (`memoria.json`), and
    /// Application Support, used before any group was configured. The first
    /// one that exists is copied across. Without this, the rename would strand
    /// every jewel logged before the upgrade. The old file is left in place.
    /// Runs once: it no-ops as soon as the shared file exists.
    static func migrateIfNeeded() {
        let destination = fileURL
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }

        var candidates: [URL] = []
        if let oldGroup = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.legacyIdentifier
        ) {
            candidates.append(oldGroup
                .appendingPathComponent("Cabochons", isDirectory: true)
                .appendingPathComponent(legacyFileName))
        }
        if let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) {
            candidates.append(appSupport
                .appendingPathComponent("Cabochons", isDirectory: true)
                .appendingPathComponent(legacyFileName))
        }

        guard let source = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else { return }

        try? FileManager.default.copyItem(at: source, to: destination)
    }
}
