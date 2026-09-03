internal import SwiftUI

// MARK: - What sits in one socket

/// One filled socket's worth of information. The rail needs more than a colour
/// now that a jewel can carry a note.
struct RailJewel: Hashable {
    var color: MateriaColor
    var hasNote: Bool = false

    init(_ color: MateriaColor, hasNote: Bool = false) {
        self.color = color
        self.hasNote = hasNote
    }
}

enum SlotContent: Hashable {
    case empty
    case filled(RailJewel, overflow: Bool)
}

private struct TiltedSpecular: View {
    let size: CGFloat

    @AppStorage("shimmerEnabled") private var shimmerEnabled = true
    @AppStorage("shimmerIntensity") private var shimmerIntensity = 0.5
    @Environment(TiltSource.self) private var motion: TiltSource?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var travel: CGSize {
        guard shimmerEnabled, !reduceMotion, let motion else { return .zero }
        let d = size * 0.22 * shimmerIntensity
        return CGSize(width: -motion.tilt.x * d, height: -motion.tilt.y * d)
    }

    var body: some View {
        Ellipse()
            .fill(.white.opacity(0.75))
            .frame(width: size * 0.26, height: size * 0.17)
            .rotationEffect(.degrees(-24))
            .offset(x: -size * 0.14 + travel.width,
                    y: -size * 0.22 + travel.height)
            .blur(radius: size * 0.035)
    }
}

// MARK: - The orb

struct MateriaOrb: View {
    let color: MateriaColor
    var size: CGFloat = 30
    /// Jewels past the day's capacity get a gold rim and a star.
    var overflow: Bool = false
    /// Something worth writing about happened.
    var hasNote: Bool = false
    var glow: CGFloat = 1

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.rim, color.core, color.deep],
                        center: UnitPoint(x: 0.34, y: 0.28),
                        startRadius: size * 0.02,
                        endRadius: size * 0.78
                    )
                )

            // Light bounced off the socket floor, back through the glass.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.rim.opacity(0.5), .clear],
                        center: UnitPoint(x: 0.68, y: 0.82),
                        startRadius: 0,
                        endRadius: size * 0.42
                    )
                )
                .blendMode(.plusLighter)

            Circle()
                .strokeBorder(
                    overflow ? Chrome.gold.opacity(0.95) : color.rim.opacity(0.7),
                    lineWidth: max(1, size * 0.045)
                )

            // Specular highlight.
            TiltedSpecular(size: size)

            if overflow, size >= 18 {
                Image(systemName: "star.fill")
                    .font(.system(size: size * 0.24))
                    .foregroundStyle(Chrome.gold)
                    .shadow(color: .black.opacity(0.6), radius: 1)
                    .offset(y: size * 0.22)
            }

            if hasNote {
                NoteGlint(size: size)
            }
        }
        .compositingGroup()
        .frame(width: size, height: size)
        .shadow(color: color.core.opacity(0.55 * glow), radius: size * 0.30)
        .shadow(color: color.core.opacity(0.30 * glow), radius: size * 0.70)
    }
}

// MARK: - The empty socket

struct MateriaSocket: View {
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

            Circle()
                .inset(by: size * 0.11)
                .stroke(Color.black.opacity(0.55), lineWidth: max(1, size * 0.05))
                .blur(radius: size * 0.03)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Note glint

/// A four-point lens flare where the sphere catches the light. Materia in FF7
/// sparkles; a jewel worth writing about sparkles harder.
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

    var body: some View {
        ZStack {
            // Soft under-flare.
            GlintShape()
                .fill(.white.opacity(0.30))
                .frame(width: size * 0.92, height: size * 0.92)

            // The glint itself. The faint shadow buys separation on very light
            // gems, where white-on-white would otherwise vanish.
            GlintShape()
                .fill(.white.opacity(0.95))
                .frame(width: size * 0.62, height: size * 0.62)
                .shadow(color: .black.opacity(0.35), radius: max(0.5, size * 0.02))
        }
        .rotationEffect(.degrees(-15))
        .offset(x: -size * 0.14, y: -size * 0.22)
        .overlay {
            // Secondary reflection, lens-flare style. Only at button scale —
            // it's noise at rail size.
            if size >= 24 {
                Circle()
                    .fill(.white.opacity(0.5))
                    .frame(width: size * 0.10, height: size * 0.10)
                    .offset(x: size * 0.32, y: size * 0.32)
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
    init(count: Int, color: MateriaColor, capacity: Int, size: CGFloat = 30, maxSlots: Int = 60) {
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
                ? .filled(fills[index], overflow: index >= capacity)
                : .empty
        }
    }

    var body: some View {
        FlowLayout(spacing: size * 0.34, lineSpacing: size * 0.34) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, content in
                switch content {
                case .empty:
                    MateriaSocket(size: size)
                case .filled(let jewel, let overflow):
                    MateriaOrb(
                        color: jewel.color,
                        size: size,
                        overflow: overflow,
                        hasNote: jewel.hasNote
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
    let today: Int
    let accent: Color
    /// "days", "weeks", "months" — a streak counts periods, not days.
    var unit: String = "days"

    var body: some View {
        let atRisk = Stats.streakAtRisk(currentStreak: streak, today: today)

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
            ? "\(singular) streak — nothing yet"
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
