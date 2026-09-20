internal import SwiftUI
#if canImport(CoreHaptics)
import CoreHaptics
#endif

// APP TARGET ONLY. Do not add this file to MemoriaWidget. CoreHaptics has no
// business in a widget process, and the engine's lifecycle is tied to
// scenePhase, which a widget doesn't have.

// MARK: - What happened

/// What a tap earned. `Milestone` and its detectors live in Milestones.swift;
/// this layer knows only how big a thing was, never what kind of thing it was.
enum HapticEvent: Equatable {
    /// An ordinary jewel, no line crossed.
    case slot
    /// A jewel taken back.
    case undo
    /// At least one milestone crossed. `weight` is the largest one; `extras` is
    /// how many *others* the same tap crossed, which shows up as extra knocks
    /// on the tail.
    case milestone(weight: Milestone.Weight, extras: Int)

    /// Picks the biggest crossing and counts the rest. Empty means an ordinary
    /// jewel.
    static func from(crossings: Set<Milestone>) -> HapticEvent {
        guard let biggest = crossings.map(\.weight).max() else { return .slot }
        return .milestone(weight: biggest, extras: crossings.count - 1)
    }
}

/// A trigger value for `.sensoryFeedback` that carries *what* happened, not
/// just *that* something did. The counter makes two identical events in a row
/// still register as a change.
struct HapticPulse: Equatable {
    private(set) var count = 0
    private(set) var event: HapticEvent = .slot

    mutating func fire(_ event: HapticEvent) {
        self.event = event
        count += 1
        Haptics.shared.play(event)
    }
}

// MARK: - Engine

/// Wraps `CHHapticEngine` for the two moments that deserve a composed pattern.
/// Everything it can't do — macOS, iPad, haptics switched off in Settings,
/// engine failed to start — comes back as `isAvailable == false`, and the
/// caller falls back to `.sensoryFeedback`.
final class Haptics {
    static let shared = Haptics()
    private init() {}

    #if canImport(CoreHaptics)
    private var engine: CHHapticEngine?

    private var hardwareSupportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    /// True only once an engine is actually running. Views check this to decide
    /// whether to hand the big events to `.sensoryFeedback` instead.
    var isAvailable: Bool { engine != nil }

    /// Called when the scene becomes active. Starting costs a few milliseconds,
    /// which is exactly why it doesn't happen on the tap.
    func start() {
        guard hardwareSupportsHaptics, engine == nil else { return }
        do {
            let new = try CHHapticEngine()
            new.playsHapticsOnly = true

            // The system stops the engine on backgrounding, phone calls, and
            // audio interruptions, and it does not tell you unless you ask.
            // Without these two handlers haptics silently die mid-session and
            // the pattern gets the blame.
            new.stoppedHandler = { [weak self] _ in
                self?.engine = nil
            }
            new.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }

            try new.start()
            engine = new
        } catch {
            engine = nil
        }
    }

    func stop() {
        engine?.stop(completionHandler: { [weak self] _ in
            self?.engine = nil
        })
    }

    func play(_ event: HapticEvent) {
        guard case .milestone(let weight, let extras) = event, let engine else { return }
        do {
            // Cheap when already running; covers the case where the engine
            // auto-shut-down while idle.
            try engine.start()
            let pattern = try Self.pattern(weight: weight, extras: extras)
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // A failed pattern is not worth interrupting anything over.
        }
    }

    // MARK: Patterns

    private static func pattern(
        weight: Milestone.Weight,
        extras: Int
    ) throws -> CHHapticPattern {
        switch weight {
        case .small:  return try mastery(swell: 0.30, resonant: false, extras: extras)
        case .medium: return try mastery(swell: 0.45, resonant: true, extras: extras)
        case .large:  return try mastery(swell: 0.60, resonant: true, extras: extras)
        case .huge:   return try mastery(swell: 0.85, resonant: true, extras: extras)
        }
    }

    /// A continuous rumble that ramps from barely-there to full over `swell`
    /// seconds, resolving into a sharp transient the instant it peaks — the
    /// haptic shape of something winding up and then landing. `resonant` adds a
    /// softer, duller second transient that reads as ring-out. Each `extra` is
    /// another knock after that, one per additional milestone the same tap
    /// crossed, so closing two tags at once is audibly two things.
    ///
    /// Base intensity stays at 1.0 because the parameter curve is a multiplier
    /// against it; the curve is what does the shaping.
    private static func mastery(
        swell: Double,
        resonant: Bool,
        extras: Int
    ) throws -> CHHapticPattern {
        let rumble = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25),
                CHHapticEventParameter(parameterID: .attackTime, value: 0.1),
                CHHapticEventParameter(parameterID: .releaseTime, value: 0.05)
            ],
            relativeTime: 0,
            duration: swell
        )

        // Deliberately concave: it hangs quiet for the first half so the rise
        // at the end reads as acceleration rather than a straight fade-in.
        let intensityCurve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0, value: 0.12),
                .init(relativeTime: swell * 0.55, value: 0.30),
                .init(relativeTime: swell * 0.85, value: 0.75),
                .init(relativeTime: swell, value: 1.0)
            ],
            relativeTime: 0
        )

        // Dull to crisp over the same span. Sharpness climbing alongside
        // intensity is most of why this reads as "charging" and not "vibrating".
        let sharpnessCurve = CHHapticParameterCurve(
            parameterID: .hapticSharpnessControl,
            controlPoints: [
                .init(relativeTime: 0, value: 0.1),
                .init(relativeTime: swell, value: 0.85)
            ],
            relativeTime: 0
        )

        var events: [CHHapticEvent] = [
            rumble,
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
                ],
                relativeTime: swell
            )
        ]

        if resonant {
            events.append(
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.45),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                    ],
                    relativeTime: swell + 0.09
                )
            )
        }

        // One knock per additional milestone, spaced far enough apart to count.
        // Capped at three: past that it stops reading as "and another" and
        // starts reading as a malfunction.
        for index in 0..<min(extras, 3) {
            events.append(
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
                    ],
                    relativeTime: swell + 0.22 + Double(index) * 0.13
                )
            )
        }

        return try CHHapticPattern(
            events: events,
            parameterCurves: [intensityCurve, sharpnessCurve]
        )
    }

    #else

    var isAvailable: Bool { false }
    func start() {}
    func stop() {}
    func play(_ event: HapticEvent) {}

    #endif
}

// MARK: - View plumbing

extension View {
    /// The one modifier a logging surface needs. Composed patterns are played
    /// by `HapticPulse.fire`; this covers the small events, and stands in for
    /// the big ones wherever the engine isn't available.
    func jewelFeedback(_ pulse: HapticPulse) -> some View {
        sensoryFeedback(trigger: pulse) { _, new in
            switch new.event {
            case .slot:
                return .impact(flexibility: .solid, intensity: 0.75)
            case .undo:
                return .impact(flexibility: .soft, intensity: 0.5)
            case .milestone:
                return Haptics.shared.isAvailable ? nil : .success
            }
        }
    }
}
