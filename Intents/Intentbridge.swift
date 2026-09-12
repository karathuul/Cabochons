internal import Foundation

// MARK: - Errors surfaced to Shortcuts

/// Shortcuts shows the localized string to the user and stops the shortcut.
/// A real error type (rather than a sentinel like `-1`) means an "if" block
/// downstream can't silently treat a failure as data.
enum MateriaIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case activityNotFound
    case nothingToUndo(activityName: String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .activityNotFound:
            return "That activity no longer exists in MateriaLog."
        case .nothingToUndo(let name):
            return "\(name) has no jewels to remove."
        }
    }
}

// MARK: - The bridge

/// **The only file in the intents layer that touches `LogStore`.**
///
/// Every intent goes through here, so if the store changes shape this is the
/// one file to update — the intent definitions, entity, and shortcut phrases
/// stay put. Same reasoning as `SharedStorage` being the one place that knows
/// where the data file lives.
///
/// Mutations go through the live `LogStore`, never the file directly. App
/// Intents declared in the app target run *in the app's process*, so the UI
/// and the intent share one store: a jewel logged by Siri appears in an open
/// window immediately, and two copies of the data can't overwrite each other.
enum IntentBridge {

    // MARK: Mutations

    /// Slots `count` jewels and returns the activity's name plus its new count
    /// for today.
    ///
    /// Timestamps are staggered a second apart. Identical timestamps would
    /// make the day rail's sort unstable, so "log 3" would reshuffle its own
    /// jewels on every redraw.
    @MainActor
    static func log(
        activityID: UUID,
        count: Int,
        note: String?,
        at date: Date,
        in store: LogStore
    ) throws -> (name: String, todayCount: Int, logged: Int) {
        guard let activity = store.activity(activityID) else {
            throw MateriaIntentError.activityNotFound
        }

        var logged = 0
        for offset in 0..<max(1, count) {
            let stamp = date.addingTimeInterval(Double(offset))
            if store.slot(activityID, at: stamp, note: note) { logged += 1 }
        }
        guard logged > 0 else { throw MateriaIntentError.activityNotFound }

        return (activity.name, try stat(.today, for: activityID, in: store), logged)
    }

    /// Removes the newest jewel, whenever it was logged.
    ///
    /// Deliberately *not* `removeLastToday`: an undo that silently no-ops
    /// because you crossed the day boundary is worse than one that reaches
    /// back a few hours.
    @MainActor
    static func undoLast(
        activityID: UUID,
        in store: LogStore
    ) throws -> (name: String, todayCount: Int) {
        guard let activity = store.activity(activityID) else {
            throw MateriaIntentError.activityNotFound
        }
        guard let newest = activity.jewels.max(by: { $0.timestamp < $1.timestamp }) else {
            throw MateriaIntentError.nothingToUndo(activityName: activity.name)
        }

        store.remove(jewel: newest.id, from: activityID)
        return (activity.name, try stat(.today, for: activityID, in: store))
    }

    // MARK: Reads

    /// Every number comes from a `LogStore` method the app itself uses, so the
    /// Shortcuts action and the screen can never disagree.
    @MainActor
    static func stat(_ kind: MateriaStat, for activityID: UUID, in store: LogStore) throws -> Int {
        guard let activity = store.activity(activityID) else {
            throw MateriaIntentError.activityNotFound
        }

        switch kind {
        case .today:  return store.todayCount(for: activity)
        case .period: return store.periodCount(for: activity)
        case .target: return activity.target
        case .total:  return activity.jewels.count
        case .streak: return streak(for: activity, in: store)
        }
    }

    // MARK: - ⚠️ The one property name I'm guessing at

    /// `store.stats(for:)` returns `ActivityStats`; I'm assuming its streak
    /// field is `currentStreak`. If not, fix the name here and nothing else.
    @MainActor
    private static func streak(for activity: Activity, in store: LogStore) -> Int {
        store.stats(for: activity).currentStreak
    }
}
