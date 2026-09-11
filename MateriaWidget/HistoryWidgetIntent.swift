import AppIntents
import WidgetKit

// MARK: - Configuration

/// What the user picks when they long-press the widget and tap Edit.
///
/// This lives in the WIDGET target, not the app target — the opposite of the
/// Shortcuts intents. The system runs a widget's configuration intent inside
/// the widget extension, so nothing here may use `@Dependency` or touch
/// `LogStore`. It reads the shared file like the timeline provider does.
struct HistoryWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "History" }
    static var description: IntentDescription { "Choose which activity the grid shows." }

    /// Optional on purpose: a freshly added widget has no pick yet, and the
    /// provider falls back to the first visible activity until the user
    /// chooses. `defaultResult()` on the query fills this in most of the time.
    @Parameter(title: "Activity")
    var activity: HistoryActivityEntity?
}

// MARK: - Entity

/// A widget-side stand-in for `Activity`. Deliberately distinct from the app
/// target's `ActivityEntity`, whose query resolves through the live store.
struct HistoryActivityEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Activity" }
    static var defaultQuery: HistoryActivityQuery { HistoryActivityQuery() }

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(_ activity: Activity) {
        id = activity.id
        name = activity.name
    }
}

// MARK: - Query

struct HistoryActivityQuery: EntityQuery {

    /// Resolves saved picks. Includes hidden activities so an existing widget
    /// keeps working if its activity is hidden later — history is
    /// backward-looking, and hiding only removes forward-looking surfaces.
    func entities(for identifiers: [UUID]) async throws -> [HistoryActivityEntity] {
        SharedStorage.load().activities
            .filter { identifiers.contains($0.id) }
            .map(HistoryActivityEntity.init)
    }

    /// What the picker lists. Hidden activities stay out of the menu; the
    /// user can unhide one in the app if they want it back on a widget.
    func suggestedEntities() async throws -> [HistoryActivityEntity] {
        SharedStorage.load().activities
            .filter { !$0.isHidden }
            .map(HistoryActivityEntity.init)
    }

    /// Pre-fills the parameter when the widget is first added, so it shows
    /// real data immediately instead of waiting to be configured.
    func defaultResult() async -> HistoryActivityEntity? {
        try? await suggestedEntities().first
    }
}
