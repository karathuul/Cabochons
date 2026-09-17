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
    static let identifier = "group.kitty.beautiful.Memoria"
}

/// On-disk shape. Versioned so the format can change later without guessing.
/// Shared between targets because the widget decodes the same file the app
/// writes.
struct LogFile: Codable {
    var version: Int = 1
    var dayStartHour: Int = 0
    var activities: [Activity] = []
}

/// The one place that knows where the data file lives and how it's coded.
/// Both `LogStore` (read/write) and the widget (read-only) go through here, so
/// there's a single source of truth for the location and the JSON settings.
enum SharedStorage {
    static let fileName = "memoria.json"

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

    /// Moves a pre-App-Group data file into the shared container on first launch
    /// after the group is added. Without this, turning on the App Group would
    /// silently strand every jewel logged before the upgrade in the old
    /// location. Runs once: it no-ops as soon as the shared file exists.
    static func migrateIfNeeded() {
        let destination = fileURL
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }

        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }

        let legacy = appSupport
            .appendingPathComponent("Cabochons", isDirectory: true)
            .appendingPathComponent(fileName)

        // If the group isn't configured, destination == legacy and this is a
        // no-op. If it is, copy the old file across.
        guard legacy.path != destination.path,
              FileManager.default.fileExists(atPath: legacy.path)
        else { return }

        try? FileManager.default.copyItem(at: legacy, to: destination)
    }
}
