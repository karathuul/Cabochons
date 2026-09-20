internal import Foundation

// APP TARGET ONLY. Do not add to MemoriaWidget.

// MARK: - The thing itself

/// Something worth noticing that a single tap brought about.
///
/// Identity is the `key` alone. That's deliberate: the scanner works by
/// comparing the set of met milestones before and after a tap and keeping the
/// difference, so two milestones are "the same one" when their keys match,
/// regardless of weight or wording. Keys are namespaced by detector —
/// `"tag:<uuid>:period"`, `"total:100"`, `"return:12"` — so two detectors can
/// never collide.
struct Milestone: Hashable {
    /// How big it feels. Not how it was computed — a tag closing its week and
    /// an activity closing its week are the same size of event, and so is a
    /// hundredth jewel that has no period at all.
    enum Weight: Int, Comparable {
        /// A day closed. Happens often; shouldn't feel like a parade.
        case small = 0
        /// A week closed, or a modest lifetime total.
        case medium = 1
        /// A month closed, or a serious total.
        case large = 2
        /// A year. Rare enough to be startling on purpose.
        case huge = 3

        static func < (a: Weight, b: Weight) -> Bool { a.rawValue < b.rawValue }
    }

    let key: String
    let weight: Weight
    /// Plain-language name, for whatever surfaces these — a toast, the day
    /// header, an export.
    let headline: String
    /// The orb colour to tint a banner with. Nil means gold, which is what the
    /// app already uses for "met".
    var tint: MateriaColor? = nil

    static func == (a: Milestone, b: Milestone) -> Bool { a.key == b.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

// MARK: - Detectors

/// What a detector gets to look at. Holds the ID rather than the value, so the
/// same context reads correctly before and after the store mutates.
struct MilestoneContext {
    let store: LogStore
    let activityID: Activity.ID

    var activity: Activity? { store.activity(activityID) }
}

/// One kind of milestone. Implement whichever of the two methods fits; the
/// other defaults to empty.
protocol MilestoneDetector {
    /// Milestones that are **true right now and stay true**. The scanner calls
    /// this before and after the tap and keeps what's newly true. A target met
    /// stays met for the rest of its period, so subtraction is what stops it
    /// firing on every subsequent tap.
    func met(_ context: MilestoneContext) -> Set<Milestone>

    /// Milestones **about this tap specifically**, which were never a lasting
    /// state and never will be again — a return after a gap is the case that
    /// forced this method to exist. Evaluated once, against the *before* state,
    /// because the gap is zero the instant the jewel lands.
    func momentary(_ context: MilestoneContext) -> Set<Milestone>
}

extension MilestoneDetector {
    func met(_ context: MilestoneContext) -> Set<Milestone> { [] }
    func momentary(_ context: MilestoneContext) -> Set<Milestone> { [] }
}

// MARK: - The scanner

/// Brackets a mutation and reports what it crossed. Adding a milestone kind is
/// adding a detector to `standard` — nothing else in the app changes.
struct MilestoneScanner {
    var detectors: [MilestoneDetector]

    static let standard = MilestoneScanner(detectors: [
        PeriodTargetDetector(),
        TagTargetDetector(),
        DayMasteryDetector(),
        TotalCountDetector(),
        ReturnDetector()
    ])

    /// Runs `perform`, and returns every milestone it newly crossed.
    func crossings(
        logging id: Activity.ID,
        in store: LogStore,
        perform: () -> Void
    ) -> Set<Milestone> {
        let context = MilestoneContext(store: store, activityID: id)

        let momentary = detectors.reduce(into: Set<Milestone>()) {
            $0.formUnion($1.momentary(context))
        }
        let before = met(context)
        perform()
        let after = met(context)

        return after.subtracting(before).union(momentary)
    }

    private func met(_ context: MilestoneContext) -> Set<Milestone> {
        detectors.reduce(into: Set<Milestone>()) { $0.formUnion($1.met(context)) }
    }
}

// MARK: - Built-in detectors
//
// Everything that touches the shape of LogStore/Stats lives below this line, so
// when those change there's one file to fix rather than one per view.

/// The activity's own target, for its own cadence.
struct PeriodTargetDetector: MilestoneDetector {
    func met(_ context: MilestoneContext) -> Set<Milestone> {
        guard let activity = context.activity else { return [] }
        // No open-ended guard needed: `isMet` is `target > 0 && count >= target`,
        // so a target of 0 can never report met.
        let progress = context.store.progress(for: activity)
        guard progress.isMet else { return [] }

        return [Milestone(
            key: "activity:\(activity.id):period",
            weight: .init(activity.cadence),
            headline: "\(activity.name) — target met",
            tint: activity.color
        )]
    }
}

/// Every tag this activity belongs to. Only tags containing it can move, so the
/// rest aren't polled — and one tap can close two at once, which the Set
/// handles without special-casing.
struct TagTargetDetector: MilestoneDetector {
    func met(_ context: MilestoneContext) -> Set<Milestone> {
        let store = context.store
        // One `progress` call per tag carries both the verdict and the cadence,
        // so nothing here depends on what `Tag` itself exposes.
        return Set(
            store.tags(containing: context.activityID)
                .map { store.progress(for: $0) }
                .filter(\.isMet)
                .map {
                    Milestone(
                        key: "tag:\($0.tagID):period",
                        weight: .init($0.cadence),
                        headline: "\($0.name) — target met"
                    )
                }
        )
    }
}

/// Today's sockets, all of them. `CombinedDay` already knows what mastery
/// means, so this asks rather than re-deriving it. Keyed by the day so it can
/// re-fire tomorrow.
struct DayMasteryDetector: MilestoneDetector {
    func met(_ context: MilestoneContext) -> Set<Milestone> {
        let calc = context.store.calc
        guard context.store.combined.today?.isMastered == true else { return [] }

        return [Milestone(
            key: "day:\(calc.today.timeIntervalSince1970):mastered",
            weight: .small,
            headline: "Day mastered"
        )]
    }
}

/// Lifetime jewel count for one activity. Add or remove numbers here and
/// nothing else in the app needs to know.
struct TotalCountDetector: MilestoneDetector {
    var thresholds: [(count: Int, weight: Milestone.Weight)] = [
        (50, .medium),
        (67, .medium),
        (100, .large),
        (200, .large),
        (365, .huge)
    ]

    func met(_ context: MilestoneContext) -> Set<Milestone> {
        guard let activity = context.activity else { return [] }
        let total = activity.jewels.count

        return Set(
            thresholds
                .filter { total >= $0.count }
                .map {
                    Milestone(
                        key: "total:\(activity.id):\($0.count)",
                        weight: $0.weight,
                        headline: "\(activity.name) — \($0.count) logged",
                        tint: activity.color
                    )
                }
        )
    }
}

/// Coming back after a gap. The one momentary detector: the gap is real before
/// the jewel lands and gone immediately after, so it can't be found by
/// comparing states.
struct ReturnDetector: MilestoneDetector {
    /// Below this, a gap is just a rest day.
    var minimumDays = 7

    var weights: [(days: Int, weight: Milestone.Weight)] = [
        (7, .small),
        (21, .medium),
        (60, .large)
    ]

    func momentary(_ context: MilestoneContext) -> Set<Milestone> {
        guard let activity = context.activity,
              let last = activity.jewels.map(\.timestamp).max()
        else { return [] }

        let calc = context.store.calc
        let gap = calc.calendar.dateComponents(
            [.day],
            from: calc.day(for: last),
            to: calc.today
        ).day ?? 0

        guard gap >= minimumDays else { return [] }

        let weight = weights.last { gap >= $0.days }?.weight ?? .small
        return [Milestone(
            key: "return:\(activity.id):\(calc.today.timeIntervalSince1970)",
            weight: weight,
            headline: "Back to \(activity.name) after \(gap) days",
            tint: activity.color
        )]
    }
}

// MARK: - Cadence → weight

extension Milestone.Weight {
    /// Bucketed by how many days the period actually spans, which makes
    /// compound cadences fall out for free: every-2-weeks is 14 days and lands
    /// where it should without a special case.
    ///
    /// `lengthInDays` is nil for month-based cadences because months vary; ~30
    /// is close enough when the answer is only ever one of four buckets.
    init(_ cadence: Cadence) {
        switch cadence.lengthInDays ?? cadence.count * 30 {
        case ..<7:   self = .small
        case ..<21:  self = .medium
        case ..<90:  self = .large
        default:     self = .huge
        }
    }
}
