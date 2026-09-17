internal import AppIntents
internal import Foundation


// MARK: - Log

/// The primary action. Everything else in this folder exists to support it.
struct LogJewelIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Jewel"

    static var description = IntentDescription(
        "Slots one or more jewels into an activity and returns its new count for today.",
        categoryName: "Logging",
        searchKeywords: ["memoria", "jewel", "habit", "track", "tally", "count"]
    )

    /// False on purpose: an automation that yanks you into the app every time
    /// it fires is worse than useless. Logging happens in the background.
    static var openAppWhenRun = false

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$count) jewel to \(\.$activity)") {
            \.$note
            \.$date
        }
    }

    @Parameter(title: "Activity", requestValueDialog: "Which activity?")
    var activity: ActivityEntity

    @Parameter(title: "Count", default: 1, inclusiveRange: (1, 99))
    var count: Int

    /// Applied to every jewel in the batch, not just the first — a note
    /// describes the occasion, and all the jewels in one call share it.
    @Parameter(title: "Note", requestValueDialog: "What's the note?")
    var note: String?

    /// Optional so backfilling works ("log yesterday's run"). Empty means now.
    @Parameter(title: "Date")
    var date: Date?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try IntentBridge.log(
            activityID: activity.id,
            count: count,
            note: (trimmed?.isEmpty ?? true) ? nil : trimmed,
            at: date ?? .now,
            in: LogStore.shared
        )

        let dialog: IntentDialog = result.logged == 1
            ? "Slotted a jewel in \(result.name). \(result.todayCount) today."
            : "Slotted \(result.logged) jewels in \(result.name). \(result.todayCount) today."

        return .result(value: result.todayCount, dialog: dialog)
    }
}

// MARK: - Undo

/// Mirrors the Undo button in the app: removes the newest jewel, whenever it
/// was logged.
struct UndoJewelIntent: AppIntent {
    static var title: LocalizedStringResource = "Remove Last Jewel"

    static var description = IntentDescription(
        "Removes the most recent jewel from an activity.",
        categoryName: "Logging",
        searchKeywords: ["undo", "remove", "delete", "mistake"]
    )

    static var openAppWhenRun = false

    static var parameterSummary: some ParameterSummary {
        Summary("Remove the last jewel from \(\.$activity)")
    }

    @Parameter(title: "Activity", requestValueDialog: "Which activity?")
    var activity: ActivityEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let result = try IntentBridge.undoLast(activityID: activity.id, in: LogStore.shared)
        return .result(
            value: result.todayCount,
            dialog: "Removed. \(result.name) is at \(result.todayCount) today."
        )
    }
}
