internal import AppIntents
internal import Foundation

// MARK: - Entity

/// Shortcuts' view of an `Activity`.
///
/// `Activity` itself stays out of the intents layer: it's the on-disk schema,
/// and every field added to it is a migration. This is a thin projection that
/// carries only what a picker row needs — identity and a label.
struct ActivityEntity: AppEntity {
    var id: UUID
    var name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Activity", numericFormat: "\(placeholder: .int) activities")
    }

    static var defaultQuery = ActivityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: "circle.hexagongrid.fill"))
    }

    init(_ activity: Activity) {
        self.id = activity.id
        self.name = activity.name
    }
}

// MARK: - Query

/// Reads the shared file directly rather than the live `LogStore`.
///
/// A picker has no business launching the app in the background just to
/// enumerate names, and `LogStore` saves on every mutation, so the file is
/// always current. Same read-only path the widget uses.
struct ActivityQuery: EntityQuery {

    /// Resolving IDs *does* include hidden activities. A shortcut built months
    /// ago against an activity since hidden should keep working — hiding
    /// removes forward-looking surfaces, it doesn't delete anything.
    func entities(for identifiers: [UUID]) async throws -> [ActivityEntity] {
        let all = await SharedStorage.load().activities
        return identifiers.compactMap { id in
            all.first { $0.id == id }.map(ActivityEntity.init)
        }
    }

    /// Suggestions exclude hidden activities, matching the app's own lists.
    func suggestedEntities() async throws -> [ActivityEntity] {
        await SharedStorage.load().activities
            .filter { !$0.isHidden }
            .map(ActivityEntity.init)
    }

    func defaultResult() async -> ActivityEntity? {
        try? await suggestedEntities().first
    }
}

// MARK: - Matching by name

/// Lets Siri and the Shortcuts search field resolve "Pushups" to the entity,
/// which is what makes spoken phrases with a parameter work at all.
extension ActivityQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [ActivityEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return try await suggestedEntities() }

        return await SharedStorage.load().activities
            .filter { !$0.isHidden }
            .filter { $0.name.localizedCaseInsensitiveContains(needle) }
            .map(ActivityEntity.init)
    }
}
