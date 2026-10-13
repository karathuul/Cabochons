// MARK: - Guide
// Every word of in-app help, in one place. `GuideTopicID` is the key and
// `GuideContent.topic(_:)` is an exhaustive switch over it, so adding a case
// refuses to compile until its copy exists — no silently blank help rows.
// `sections` decides what the Guide screen shows and in what order. A topic
// may carry worked examples (a trigger and what it does), shown when the
// row is expanded.
//
// One topic, several surfaces: the Guide sheet, an inline ⓘ, and later the
// body of a tip. The copy is written once, here, never at a call site.
//
// TARGET MEMBERSHIP: app target only. The widget shows no help.

internal import Foundation

// MARK: - Topic identity

/// Every explainable idea in the app, exactly once.
enum GuideTopicID: String, CaseIterable, Identifiable {
    case orbs
    case sockets
    case dayRail
    case star
    case targets
    case whenever
    case streaks
    case dayStart
    case notes
    case glint
    case tags
    case hiding
    case shimmer
    case widgets
    case shortcuts
    case automations
    case data

    var id: String { rawValue }
}

// MARK: - Models

/// A worked example: something that happens, and what the app does about it.
struct GuideExample: Hashable {
    /// The cause. "Leave the gym."
    let trigger: String
    /// The effect. "Log a jewel on Exercise."
    let action: String
}

struct GuideTopic: Identifiable, Hashable {
    let id: GuideTopicID
    /// Row title. Two or three words.
    let title: String
    /// SF Symbol name.
    let symbol: String
    /// One line. It has to stand alone — a tip or an ⓘ may show nothing else.
    let blurb: String
    /// Optional second beat, for whoever tapped in wanting more.
    let detail: String?
    /// Worked examples, shown after the detail. Most topics have none.
    let examples: [GuideExample]

    /// True when there's anything beyond the blurb worth expanding into.
    var hasMore: Bool { detail != nil || !examples.isEmpty }

    init(_ id: GuideTopicID,
         title: String,
         symbol: String,
         blurb: String,
         detail: String? = nil,
         examples: [GuideExample] = []) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.blurb = blurb
        self.detail = detail
        self.examples = examples
    }
}

struct GuideSection: Identifiable, Hashable {
    let title: String
    let topics: [GuideTopicID]
    var id: String { title }
}

// MARK: - Content

enum GuideContent {

    /// Exhaustive on purpose. A dictionary would be shorter and would hand back
    /// an optional, which means a missing entry ships as a blank row. This way
    /// the compiler stops you first.
    static func topic(_ id: GuideTopicID) -> GuideTopic {
        switch id {

        case .orbs:
            return GuideTopic(
                .orbs,
                title: "Orbs & Jewels",
                symbol: "circle.circle.fill",
                blurb: "Press an orb. A jewel drops into today. That's the whole app.",
                detail: "Press again for another. Everything else — targets, streaks, tags — is only ever counting these."
            )

        case .sockets:
            return GuideTopic(
                .sockets,
                title: "Sockets",
                symbol: "circle.dotted",
                blurb: "Empty sockets are what this period still wants from you.",
                detail: "Fill them all and you're done until the period turns over."
            )

        case .dayRail:
            return GuideTopic(
                .dayRail,
                title: "The Day Rail",
                symbol: "rectangle.split.3x1.fill",
                blurb: "Everything logged today, in the order it happened.",
                detail: "Colours mix freely. The rail doesn't sort by activity — it sorts by when."
            )

        case .star:
            return GuideTopic(
                .star,
                title: "The Gold Star",
                symbol: "star.fill",
                blurb: "A gold star means that target is met for the period.",
                detail: "Tags get one too, and their glyph turns gold with it. Keep going past it if you like — nothing stops you."
            )

        case .targets:
            return GuideTopic(
                .targets,
                title: "Targets",
                symbol: "target",
                blurb: "Pick a number and a stretch of time. Three a week. One a day.",
                detail: "The rail is sized to that number, so a glance tells you where the period stands."
            )

        case .whenever:
            return GuideTopic(
                .whenever,
                title: "Whenever",
                symbol: "infinity",
                blurb: "No target. No sockets. No nagging. Log it when it happens.",
                detail: "For things worth noticing rather than enforcing. They still count toward your totals."
            )

        case .streaks:
            return GuideTopic(
                .streaks,
                title: "Streaks",
                symbol: "flame.fill",
                blurb: "A streak counts finished periods, not days in a row.",
                detail: "Miss a Tuesday on a weekly target and nothing breaks, so long as the week lands. Daily targets are stricter. Obviously."
            )

        case .dayStart:
            return GuideTopic(
                .dayStart,
                title: "When a Day Starts",
                symbol: "moon.stars.fill",
                blurb: "Your day doesn't have to start at midnight.",
                detail: "Set it later and anything logged in the small hours counts toward the day you were actually still living. Found under Settings."
            )

        case .notes:
            return GuideTopic(
                .notes,
                title: "Notes",
                symbol: "text.alignleft",
                blurb: "Any jewel can carry a note. Three hundred characters, no more.",
                detail: "Brevity is the point. If it needs a paragraph, it probably wanted its own activity."
            )

        case .glint:
            return GuideTopic(
                .glint,
                title: "The Glint",
                symbol: "sparkle",
                blurb: "A four-point flare on a jewel means there's a note inside.",
                detail: "Longer note, bigger flare. It rides the same light as everything else, so it moves when you tilt."
            )

        case .tags:
            return GuideTopic(
                .tags,
                title: "Tags",
                symbol: "tag.fill",
                blurb: "Group activities, then give the group its own target.",
                detail: "An activity can wear as many tags as it likes. Tag targets stack on top of each activity's own — \"exercise five times a week\" doesn't care which exercise."
            )

        case .hiding:
            return GuideTopic(
                .hiding,
                title: "Hiding",
                symbol: "eye.slash.fill",
                blurb: "Hide an activity and it stops asking. Its jewels stay.",
                detail: "Nothing is deleted. Hiding only clears the forward-looking surfaces — previous days keep every jewel."
            )

        case .shimmer:
            return GuideTopic(
                .shimmer,
                title: "Shimmer",
                symbol: "gyroscope",
                blurb: "Orbs catch the light as you move. Entirely decorative.",
                detail: "It's real tilt, not a loop. Enjoy it."
            )

        case .widgets:
            return GuideTopic(
                .widgets,
                title: "Widgets",
                symbol: "square.grid.2x2.fill",
                blurb: "Put today on the Home Screen, small or medium.",
                detail: "Long-press the Home Screen, tap the plus, and look for the app by name."
            )

        case .shortcuts:
            return GuideTopic(
                .shortcuts,
                title: "Shortcuts & Siri",
                symbol: "mic.fill",
                blurb: "Log, undo, or ask for a count — out loud.",
                detail: "Every action also shows up in the Shortcuts app, ready to build with."
            )

        case .automations:
            return GuideTopic(
                .automations,
                title: "Automations",
                symbol: "bolt.fill",
                blurb: "Let something else press the orb for you.",
                detail: "Build these in the Shortcuts app, under Automation. A few to steal:",
                examples: [
                    GuideExample(trigger: "Leave the gym",
                                 action: "Log a jewel on Exercise"),
                    GuideExample(trigger: "Stop the morning alarm",
                                 action: "Log a jewel on Up Early"),
                    GuideExample(trigger: "Tap an NFC sticker on the piano",
                                 action: "Log a jewel on Practice"),
                    GuideExample(trigger: "Double-tap the back of the phone",
                                 action: "Undo the last jewel"),
                    GuideExample(trigger: "Sunday, 8 PM",
                                 action: "Speak this week's count for Reading")
                ]
            )

        case .data:
            return GuideTopic(
                .data,
                title: "Import & Export",
                symbol: "square.and.arrow.up",
                blurb: "Your whole log, out as a file — and back in again.",
                detail: "Plain, readable, yours. Found under Settings."
            )
        }
    }

    /// Order and grouping of the Guide screen.
    static let sections: [GuideSection] = [
        GuideSection(title: "Basics", topics: [.orbs, .sockets, .dayRail, .star]),
        GuideSection(title: "Keeping Time", topics: [.targets, .whenever, .streaks, .dayStart]),
        GuideSection(title: "Details", topics: [.notes, .glint, .tags, .hiding, .shimmer]),
        GuideSection(title: "Elsewhere", topics: [.widgets, .shortcuts, .automations, .data])
    ]
}

// MARK: - Debug coverage check

#if DEBUG
extension GuideContent {
    /// Catches a topic that exists but was never placed in a section, which
    /// would make it unreachable from the Guide with no visible sign. `assert`
    /// compiles out of release builds — this is a check on you, not on the user.
    /// Call once from the app's `init`.
    static func assertEveryTopicIsReachable() {
        let placed = sections.flatMap(\.topics)
        let placedSet = Set(placed)

        let orphans = Set(GuideTopicID.allCases).subtracting(placedSet)
        assert(orphans.isEmpty,
               "Guide topics in no section: \(orphans.map(\.rawValue).sorted())")

        assert(placed.count == placedSet.count,
               "A Guide topic is listed in more than one section.")
    }
}
#endif
