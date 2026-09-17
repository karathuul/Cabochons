internal import AppIntents

/// App Shortcuts are the ones that exist without the user building anything:
/// they show up in Spotlight, in the Shortcuts gallery, and as Siri phrases the
/// moment the app is installed.
///
/// Two constraints worth knowing before adding more:
/// - Every phrase **must** contain `\(.applicationName)`. The system rejects
///   the whole provider at build time otherwise, not just the bad phrase.
/// - Ten App Shortcuts maximum per app. Everything beyond that is still
///   available as an action in the Shortcuts editor; it just isn't pre-made.
struct MateriaShortcuts: AppShortcutsProvider {

    /// Tints the Spotlight and Shortcuts tiles. Purple is closest to the
    /// gunmetal-and-orb look the app itself uses.
    static var shortcutTileColor: ShortcutTileColor = .purple

    static var appShortcuts: [AppShortcut] {
        // The parameterised phrase is the useful one — "log a jewel in
        // MateriaLog for Pushups" resolves the activity by name through
        // `ActivityQuery`'s string matching. The bare phrase is the fallback
        // that prompts for the activity.
        AppShortcut(
            intent: LogJewelIntent(),
            phrases: [
                "Log a jewel in \(.applicationName)",
                "Slot a jewel in \(.applicationName)",
                "Log \(\.$activity) in \(.applicationName)",
                "Slot \(\.$activity) in \(.applicationName)"
            ],
            shortTitle: "Log Jewel",
            systemImageName: "circle.hexagongrid.fill"
        )

        AppShortcut(
            intent: ActivityStatIntent(),
            phrases: [
                "Check my \(.applicationName) count",
                "How many jewels in \(.applicationName)",
                "Check \(\.$activity) in \(.applicationName)"
            ],
            shortTitle: "Get Count",
            systemImageName: "chart.bar.fill"
        )

        AppShortcut(
            intent: UndoJewelIntent(),
            phrases: [
                "Undo a jewel in \(.applicationName)",
                "Remove a jewel in \(.applicationName)"
            ],
            shortTitle: "Remove Jewel",
            systemImageName: "arrow.uturn.backward"
        )
    }
}
