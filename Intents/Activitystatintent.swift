internal import AppIntents
internal import Foundation

// MARK: - Which number

/// Kept to numbers only. A Shortcuts action that sometimes returns a date and
/// sometimes an integer forces every downstream block to defend itself, so
/// dates and text get their own actions if they're ever needed.
enum CabochonsStat: String, AppEnum {
    case today
    case period
    case streak
    case total
    case target

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Statistic"

    static var caseDisplayRepresentations: [CabochonsStat: DisplayRepresentation] = [
        .today:  DisplayRepresentation(title: "Jewels today",
                                       subtitle: "Counted against your day-start hour"),
        .period: DisplayRepresentation(title: "Jewels this period",
                                       subtitle: "Within the activity's current cadence window"),
        .streak: DisplayRepresentation(title: "Current streak",
                                       subtitle: "Consecutive periods where the target was met"),
        .total:  DisplayRepresentation(title: "Total jewels",
                                       subtitle: "All time"),
        .target: DisplayRepresentation(title: "Target",
                                       subtitle: "Cabochons goal per period")
    ]
}

// MARK: - Intent

/// Returns a bare `Int` so it drops straight into an If block or a Text action
/// without unwrapping.
struct ActivityStatIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Activity Count"

    static var description = IntentDescription(
        "Returns a number for an activity: today's jewels, jewels this period, streak, all-time total, or target.",
        categoryName: "Reading",
        searchKeywords: ["count", "streak", "total", "progress", "stats"]
    )

    static var openAppWhenRun = false

    static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$stat) for \(\.$activity)")
    }

    @Parameter(title: "Statistic", default: .today)
    var stat: CabochonsStat

    @Parameter(title: "Activity", requestValueDialog: "Which activity?")
    var activity: ActivityEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let value = try IntentBridge.stat(stat, for: activity.id, in: LogStore.shared)

        let dialog: IntentDialog
        switch stat {
        case .today:  dialog = "\(value) today."
        case .period: dialog = "\(value) this period."
        case .streak: dialog = "\(value) periods."
        case .total:  dialog = "\(value) all time."
        case .target: dialog = value == 0 ? "No target — whenever." : "\(value) per period."
        }

        return .result(value: value, dialog: dialog)
    }
}
