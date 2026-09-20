//
//  Guide.swift
//
//  MARK: - Overview
//  The single source of truth for every word of in-app help.
//
//  `GuideTopicID` is the type-safe key. `GuideContent.topic(_:)` is an
//  exhaustive switch over it, which means adding a case refuses to compile
//  until you write its copy — no silently blank help rows, ever.
//
//  One topic feeds three surfaces: the Guide screen (GuideView.swift), an
//  inline ⓘ sheet, and later the body of a TipKit tip. Copy is written once
//  here and never duplicated at a call site.
//
//  TARGET MEMBERSHIP: app target only. The widget never shows help, so this
//  file does NOT go in MemoriaWidget.
//

internal import Foundation

// MARK: - Topic identity

/// Every explainable concept in the app, exactly once.
enum GuideTopicID: String, CaseIterable, Identifiable {
    case orbs
    case sockets
    case dayRail
    case targets
    case whenever
    case streaks
    case notes
    case glint
    case tags
    case hiding
    case shimmer
    case widgets
    case shortcuts
    case export

    var id: String { rawValue }
}

// MARK: - Models

struct GuideTopic: Identifiable, Hashable {
    let id: GuideTopicID
    /// Row title. Two or three words.
    let title: String
    /// SF Symbol name.
    let symbol: String
    /// One line. It has to stand alone — a tip or a ⓘ row may show nothing else.
    let blurb: String
    /// Optional second beat, for people who tapped in wanting more.
    let detail: String?

    init(_ id: GuideTopicID,
         title: String,
         symbol: String,
         blurb: String,
         detail: String? = nil) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.blurb = blurb
        self.detail = detail
    }
}

struct GuideSection: Identifiable, Hashable {
    let title: String
    let topics: [GuideTopicID]
    var id: String { title }
}

// MARK: - Content

enum GuideContent {

    /// Exhaustive by design. Add a `GuideTopicID` case and the compiler will
    /// sit here with its arms folded until you write the words.
    static func topic(_ id: GuideTopicID) -> GuideTopic {
        switch id {

        case .orbs:
            return GuideTopic(
                .orbs,
                title: "Orbs & Jewels",
                symbol: "circle.circle.fill",
                blurb: "Tap an orb. A jewel drops into today. That's the whole app.",
                detail: "Tap again for a second jewel. Everything else — targets, streaks, tags — is just counting these."
            )

        case .sockets:
            return GuideTopic(
                .sockets,
                title: "Sockets",
                symbol: "circle.dotted",
                blurb: "Empty sockets are what's left in the current period.",
                detail: "Fill them all and the period is done. An orb showing none is either finished or set to Whenever."
            )

        case .dayRail:
            return GuideTopic(
                .dayRail,
                title: "The Day Rail",
                symbol: "rectangle.split.3x1.fill",
                blurb: "Everything you logged today, in the order you logged it.",
                detail: "Colours mix freely. The rail doesn't sort by activity — it sorts by when."
            )

        case .targets:
            return GuideTopic(
                .targets,
                title: "Targets",
                symbol: "target",
                blurb: "Pick a number and a stretch of time. Three a week. One a day.",
                detail: "The sockets show what the current period still wants from you. Nothing carries over — a new period starts clean."
            )

        case .whenever:
            return GuideTopic(
                .whenever,
                title: "Whenever",
                symbol: "infinity",
                blurb: "No target. No sockets. No nagging. Log it when it happens.",
                detail: "For things worth noticing rather than enforcing. Whenever activities still count toward your totals."
            )

        case .streaks:
            return GuideTopic(
                .streaks,
                title: "Streaks",
                symbol: "flame.fill",
                blurb: "A streak counts finished periods, not days in a row.",
                detail: "Miss a Tuesday on a weekly target and nothing breaks, so long as the week lands. Daily targets are stricter. Obviously."
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
                detail: "An activity can wear as many tags as it likes. Tag targets stack on top of the activity's own — \"exercise five times a week\" doesn't care which exercise."
            )

        case .hiding:
            return GuideTopic(
                .hiding,
                title: "Hiding",
                symbol: "eye.slash.fill",
                blurb: "Hide an activity and it stops asking. Its jewels stay.",
                detail: "Nothing is deleted, ever. Hiding only clears the forward-looking surfaces — the history keeps everything."
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
                detail: "Long-press the Home Screen, tap the plus, find Cabochon."
            )

        case .shortcuts:
            return GuideTopic(
                .shortcuts,
                title: "Shortcuts & Siri",
                symbol: "mic.fill",
                blurb: "Log a jewel by voice, or hand one to an automation.",
                detail: "Log, undo, or ask for a count. Automations can fire any of them without you."
            )

        case .export:
            return GuideTopic(
                .export,
                title: "Export",
                symbol: "square.and.arrow.up",
                blurb: "Everything you've logged, out as a file, whenever you want.",
                detail: "Plain, readable, yours. Import is on its way."
            )
        }
    }

    /// Order and grouping of the Guide screen.
    static let sections: [GuideSection] = [
        GuideSection(title: "Basics", topics: [.orbs, .sockets, .dayRail]),
        GuideSection(title: "Keeping Time", topics: [.targets, .whenever, .streaks]),
        GuideSection(title: "Details", topics: [.notes, .glint, .tags, .hiding, .shimmer]),
        GuideSection(title: "Elsewhere", topics: [.widgets, .shortcuts, .export])
    ]
}

// MARK: - Debug coverage check

#if DEBUG
extension GuideContent {
    /// Fails loudly if a topic was added but never placed in a section — which
    /// would make it unreachable from the Guide screen without any visible sign.
    /// Call once from the app's init, or from OrbLab.
    static func assertEveryTopicIsReachable() {
        let placed = sections.flatMap(\.topics)
        let placedSet = Set(placed)

        let orphans = Set(GuideTopicID.allCases).subtracting(placedSet)
        assert(orphans.isEmpty,
               "Guide topics not in any section: \(orphans.map(\.rawValue).sorted())")

        assert(placed.count == placedSet.count,
               "Guide topic listed in more than one section.")
    }
}
#endif
