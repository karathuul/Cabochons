internal import SwiftUI

// MARK: - What sits in one socket

/// One filled socket's worth of information. The rail needs more than a colour
/// now that a jewel can carry a note.
struct RailJewel: Hashable {
    var color: CabochonsColor
    /// 0 = no note. Anything above is how hard the glint flares.
    var glint: CGFloat = 0

    var hasNote: Bool { glint > 0 }

    init(_ color: CabochonsColor, note: String? = nil) {
        self.color = color
        self.glint = NoteRules.glint(for: note)
    }
}

// MARK: - Note rules

/// The one place that decides what a note is worth. Store, editor, and orb all
/// read from here so the cap and the flare can't drift apart.
enum NoteRules {
    /// Hard ceiling on note length, in characters. The store truncates on the
    /// way in; the editor stops you typing past it.
    static let limit = 300

    /// Full flare arrives well short of the cap. A real sentence or two should
    /// already earn it; the last hundred-odd characters are for people who
    /// like writing, not a hurdle everyone has to clear.
    static let saturation = 160

    /// Trim, then clamp. Blank becomes nil so `hasNote` and the tag agree.
    static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(limit))
    }

    /// 0 for no note, otherwise 0.35…1. Square root so growth is front-loaded:
    /// "ok" barely glints, forty characters is already a clear step up, and
    /// the curve flattens as you approach `saturation`.
    static func glint(for note: String?) -> CGFloat {
        guard let note, !note.isEmpty else { return 0 }
        let t = min(1, Double(note.count) / Double(saturation))
        return CGFloat(0.35 + 0.65 * t.squareRoot())
    }
}

enum SlotContent: Hashable {
    case empty
    case filled(RailJewel, overflow: Bool)
}

// MARK: - The orb

/// A jewel. This is the public face; it picks a render tier by size.
///
/// At or above `liveThreshold` the orb is *live*: it reads device tilt so the
/// specular slides, and it spends the render passes (a blur, a two-stop glow)
/// that make a 30–108pt sphere read as glass. Below that none of it survives
/// the pixel grid — a 14pt rail orb was paying for a highlight it couldn't
/// show, and re-rendering it on every CoreMotion tick. Small orbs are drawn
/// static: no tilt subscription, no blur passes, one glow instead of two.
struct CabochonsOrb: View {
    let color: CabochonsColor
    var size: CGFloat = 30
    /// Jewels past the day's capacity get a gold rim and a star.
    var overflow: Bool = false
    /// Something worth writing about happened. 0 = nothing; otherwise how
    /// hard the note glint flares (see `NoteRules.glint`).
    var glint: CGFloat = 0
    var glow: CGFloat = 1

    /// Orbs this size and up are live. History rails draw at 14; everything
    /// else is 30 or larger, so nothing tuned in OrbLab changes.
    static let liveThreshold: CGFloat = 20

    var body: some View {
        if size >= Self.liveThreshold {
            LiveOrb(color: color, size: size, overflow: overflow, glint: glint, glow: glow)
        } else {
            OrbFace(
                color: color, size: size, overflow: overflow, glint: glint, glow: glow,
                travel: .zero, live: false
            )
        }
    }
}

/// The only view that reads the tilt source. Observation tracks what a body
/// *accesses*, so an orb that never touches `motion.tilt` never gets
/// invalidated by it — which is why the tilt read and the shimmer settings
/// live here rather than in `CabochonsOrb`, where every orb would carry them.
private struct LiveOrb: View {
    let color: CabochonsColor
    let size: CGFloat
    let overflow: Bool
    let glint: CGFloat
    let glow: CGFloat

    @AppStorage("shimmerEnabled") private var shimmerEnabled = true
    @AppStorage("shimmerIntensity") private var shimmerIntensity = 0.5
    @Environment(TiltSource.self) private var motion: TiltSource?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.orbShading) private var sh

    private var travel: CGSize {
        guard shimmerEnabled, !reduceMotion, let motion else { return .zero }
        let d = size * sh.specTravel * shimmerIntensity
        return CGSize(width: -motion.tilt.x * d, height: -motion.tilt.y * d)
    }

    var body: some View {
        OrbFace(
            color: color, size: size, overflow: overflow, glint: glint, glow: glow,
            travel: travel, live: true
        )
    }
}

/// The drawing, shared by both tiers so a gem is the same gem at any size.
/// `travel` is the specular's displacement from tilt (always zero when
/// static); `live` gates the passes that only pay off at button scale.
private struct OrbFace: View {
    let color: CabochonsColor
    let size: CGFloat
    let overflow: Bool
    let glint: CGFloat
    let glow: CGFloat
    let travel: CGSize
    let live: Bool

    @Environment(\.orbShading) private var sh

    var body: some View {
        // Whate the orb is gonna be looking like
        let orb = ZStack {
            Circle().fill(RadialGradient(
                    colors: [color.rim, color.core, color.deep],
                    center: sh.bodyCenter,
                    startRadius: size * 0.02,
                    endRadius: size * sh.bodyOuter))

            Circle().fill(RadialGradient(
                    colors: [color.rim.opacity(sh.bounceOpacity), .clear],
                    center:
                        UnitPoint(
                            x: sh.bounceCenter.x - travel.width*0.01,
                            y: sh.bounceCenter.y - travel.height*0.01),
                    startRadius: 0,
                    endRadius: size * sh.bounceRadius))
                .blendMode(.plusLighter)

            Circle().strokeBorder(
                    overflow ? Chrome.gold.opacity(0.95) : color.rim.opacity(sh.rimOpacity),
                    lineWidth: max(1, size * sh.rimWidth))

            Specular(size: size, travel: travel, blurred: live)

            if overflow, size >= 18 {
                Image(systemName: "star.fill")
                    .font(.system(size: size * 0.24))
                    .foregroundStyle(Chrome.gold)
                    .shadow(color: .black.opacity(0.6), radius: 1)
                    .offset(y: size * 0.22)
            }

            if glint > 0 {
                NoteGlint(size: size, strength: glint, travel: travel)
            }
        }
        .compositingGroup()
        .frame(width: size, height: size)
        .shadow(color: color.core.opacity(sh.glowNearOpacity * glow), radius: size * sh.glowNearRadius)

        // The far glow is a second full blur pass for a few pixels of haze.
        // At rail size it vanishes into the panel gradient, so it's skipped.
        if live {
            orb.shadow(color: color.core.opacity(sh.glowFarOpacity * glow), radius: size * sh.glowFarRadius)
        } else {
            orb
        }
    }
}

/// The highlight where the glass catches light.
///
/// Live orbs blur a flat ellipse: the softness is real and it tracks tilt.
/// Static orbs get the softness baked into an elliptical gradient instead —
/// indistinguishable at 14pt, and a gradient is one fill where a blur is a
/// whole offscreen pass.
private struct Specular: View {
    let size: CGFloat
    let travel: CGSize
    let blurred: Bool
    @Environment(\.orbShading) private var sh

    private var fill: AnyShapeStyle {
        let white = Color.white.opacity(sh.specOpacity)
        return blurred
            ? AnyShapeStyle(white)
            : AnyShapeStyle(EllipticalGradient(
                colors: [white, white, .clear],
                center: .center,
                startRadiusFraction: 0.3,
                endRadiusFraction: 0.5))
    }

    var body: some View {
        let ellipse = Ellipse()
            .fill(fill)
            .frame(width: size * sh.specWidth, height: size * sh.specHeight)
            .rotationEffect(.degrees(sh.specAngle))
            .offset(x: size * sh.specX + travel.width,
                    y: size * sh.specY + travel.height)

        if blurred {
            ellipse.blur(radius: size * sh.specBlur)
        } else {
            ellipse
        }
    }
}

// MARK: - The empty socket

struct CabochonsSocket: View {
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Chrome.socketVoid, Color(hex: 0x121722)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.6
                    )
                )

            // Machined ring: bright on the top-left lip, dark on the underside.
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Chrome.steelHi.opacity(0.85), Chrome.steel.opacity(0.25), Chrome.steelHi.opacity(0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(1.2, size * 0.075)
                )

            // Inner shadow. Same cutoff as the orb: below it the blur radius
            // is under half a pixel and not worth its own render pass.
            let lip = Circle()
                .inset(by: size * 0.11)
                .stroke(Color.black.opacity(0.55), lineWidth: max(1, size * 0.05))

            if size >= CabochonsOrb.liveThreshold {
                lip.blur(radius: size * 0.03)
            } else {
                lip
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Note glint

/// <*> Becomes very shiny with a big lens flare.
///
/// Sits on the existing specular highlight (top-left), so it reads as the
/// highlight flaring rather than as hardware added to the gem. Clear of the
/// bottom-centre overflow star. Drawn inside the orb's frame (rays overhang by
/// ~3% of size, absorbed by rail spacing), so annotated and plain orbs measure
/// the same and alignment is unaffected.
struct GlintShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let waist = r * 0.18

        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addQuadCurve(
            to: CGPoint(x: c.x + r, y: c.y),
            control: CGPoint(x: c.x + waist, y: c.y - waist)
        )
        path.addQuadCurve(
            to: CGPoint(x: c.x, y: c.y + r),
            control: CGPoint(x: c.x + waist, y: c.y + waist)
        )
        path.addQuadCurve(
            to: CGPoint(x: c.x - r, y: c.y),
            control: CGPoint(x: c.x - waist, y: c.y + waist)
        )
        path.addQuadCurve(
            to: CGPoint(x: c.x, y: c.y - r),
            control: CGPoint(x: c.x - waist, y: c.y - waist)
        )
        path.closeSubpath()
        return path
    }
}

private struct NoteGlint: View {
    let size: CGFloat
    /// 0.35…1 from `NoteRules.glint`. Longer note, bigger flare — the glint
    /// is a lure for actually reflecting rather than typing "ok".
    let strength: CGFloat
    /// The specular's tilt displacement. The flare rides it so the two stay
    /// glued; static orbs pass `.zero` and nothing moves.
    let travel: CGSize

    /// Main flare spans 0.40–0.72 of the orb; the old fixed 0.62 lands at
    /// roughly a 75-character note, so mid-length notes look as they did.
    private var coreScale: CGFloat { 0.40 + 0.32 * strength }
    /// Under-flare grows with it, 0.60–1.0.
    private var haloScale: CGFloat { 0.60 + 0.40 * strength }

    var body: some View {
        ZStack {
            // Soft under-flare.
            GlintShape()
                .fill(.white.opacity(0.18 + 0.14 * strength))
                .frame(width: size * haloScale, height: size * haloScale)

            // The glint itself. The faint shadow buys separation on very light
            // gems, where white-on-white would otherwise vanish. At rail size
            // it's half a pixel of shadow for a full render pass, so static
            // orbs go without.
            let glint = GlintShape()
                .fill(.white.opacity(0.80 + 0.15 * strength))
                .frame(width: size * coreScale, height: size * coreScale)

            if size >= CabochonsOrb.liveThreshold {
                glint.shadow(color: .black.opacity(0.35), radius: max(0.5, size * 0.02))
            } else {
                glint
            }
        }
        .rotationEffect(.degrees(-15))
        .offset(x: -size * 0.14 + travel.width, y: -size * 0.22 + travel.height)
        .overlay {
            // Secondary reflection, lens-flare style. Only at button scale —
            // it's noise at rail size — and only once the flare is bright
            // enough to plausibly throw one. A bare "ok" doesn't.
            //
            // Ghosts in a real lens sit on the far side of the optical axis
            // from the light, so this one slides *against* the tilt while the
            // flare slides with it. Cheap parallax; sells the glass.
            if size >= 24, strength >= 0.5 {
                Circle()
                    .fill(.white.opacity(0.5))
                    .frame(width: size * (0.06 + 0.06 * strength),
                           height: size * (0.06 + 0.06 * strength))
                    .offset(x: size * 0.32 - travel.width * 0.6,
                            y: size * 0.32 - travel.height * 0.6)
            }
        }
    }
}

// MARK: - Slot rail

/// One period of sockets, laid out loose.
///
/// `fills` is in the order the jewels were earned, so a combined day rail reads
/// left to right as the day progressed and mixes colours from every activity.
/// Anything past capacity extends the rail with gold-rimmed orbs rather than
/// being hidden — over-delivering shouldn't look identical to hitting the
/// number exactly.
struct SlotRail: View {
    let fills: [RailJewel]
    let capacity: Int
    var size: CGFloat = 30
    var maxSlots: Int = 60

    init(fills: [RailJewel], capacity: Int, size: CGFloat = 30, maxSlots: Int = 60) {
        self.fills = fills
        self.capacity = capacity
        self.size = size
        self.maxSlots = maxSlots
    }

    /// Convenience for a single-activity rail with no note information.
    init(count: Int, color: CabochonsColor, capacity: Int, size: CGFloat = 30, maxSlots: Int = 60) {
        self.fills = Array(repeating: RailJewel(color), count: max(0, count))
        self.capacity = capacity
        self.size = size
        self.maxSlots = maxSlots
    }

    private var truncated: Int {
        max(0, fills.count - maxSlots)
    }

    private var slots: [SlotContent] {
        let total = min(max(capacity, fills.count), maxSlots)
        guard total > 0 else { return [] }
        return (0..<total).map { index in
            index < fills.count
                ? .filled(fills[index], overflow: capacity > 0 && index >= capacity)
                : .empty
        }
    }

    var body: some View {
        FlowLayout(spacing: size * 0.34, lineSpacing: size * 0.34) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, content in
                switch content {
                case .empty:
                    CabochonsSocket(size: size)
                case .filled(let jewel, let overflow):
                    CabochonsOrb(
                        color: jewel.color,
                        size: size,
                        overflow: overflow,
                        glint: jewel.glint
                    )
                }
            }

            if truncated > 0 {
                Text("+\(truncated)")
                    .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Chrome.gold)
                    .frame(height: size)
            }
        }
    }
}

// MARK: - Flow layout

/// Wraps subviews onto as many lines as needed, so linked pairs never get split
/// across a line break.
///
/// `sizeThatFits` and `placeSubviews` MUST agree on where the breaks fall. They
/// run the same arrangement routine for exactly that reason: computing the
/// wrap twice by different expression orders leaves the two disagreeing by a
/// float ulp, which silently costs you a line of reported height and draws the
/// overflow outside its container.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    /// Slack on the wrap test. Absorbs accumulated float error without being
    /// wide enough to let a real overflow through.
    private let tolerance: CGFloat = 0.5

    private struct Arrangement {
        var offsets: [CGPoint]
        var size: CGSize
    }

    private func arrange(sizes: [CGSize], maxWidth: CGFloat) -> Arrangement {
        var offsets: [CGPoint] = []
        offsets.reserveCapacity(sizes.count)

        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0

        for size in sizes {
            if x > 0, x + size.width > maxWidth + tolerance {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }

            offsets.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }

        return Arrangement(
            offsets: offsets,
            size: CGSize(width: widest, height: y + lineHeight)
        )
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return arrange(sizes: sizes, maxWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let arrangement = arrange(sizes: sizes, maxWidth: bounds.width)

        for (index, subview) in subviews.enumerated() {
            let offset = arrangement.offsets[index]
            subview.place(
                at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y),
                proposal: ProposedViewSize(sizes[index])
            )
        }
    }
}

// MARK: - Panel styling

struct PanelBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Chrome.panelHi, Chrome.panel],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Chrome.steel.opacity(0.35), lineWidth: 1)
                    }
            }
    }
}

extension View {
    func panel(padding: CGFloat = 16) -> some View {
        modifier(PanelBackground(padding: padding))
    }
}

// MARK: - Shared bits

struct StatTile: View {
    let label: String
    let value: String
    var unit: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StreakBadge: View {
    let streak: Int
    /// The period that would extend the streak. Until it keeps the streak,
    /// the badge reads as at risk.
    let current: PeriodSummary?
    let accent: Color
    /// "days", "weeks", "months" — a streak counts periods, not days.
    var unit: String = "days"

    var body: some View {
        let atRisk = Stats.streakAtRisk(currentStreak: streak, current: current)

        HStack(spacing: 8) {
            Image(systemName: streak > 0 ? "flame.fill" : "flame")
                .font(.title3)
                .foregroundStyle(atRisk ? Chrome.steelHi : accent)

            VStack(alignment: .leading, spacing: 0) {
                Text("\(streak)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(caption(atRisk: atRisk))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func caption(atRisk: Bool) -> String {
        if streak == 0 { return "no streak" }
        let singular = String(unit.dropLast())
        return atRisk
            ? "\(singular) streak — not kept yet"
            : "\(singular) streak"
    }
}

struct OrbButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: configuration.isPressed)
    }
}
