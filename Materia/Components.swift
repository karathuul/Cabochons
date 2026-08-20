internal import SwiftUI

// MARK: - What sits in one socket

enum SlotContent: Hashable {
    case empty
    case filled(MateriaColor, overflow: Bool)
}

// MARK: - The orb

struct MateriaOrb: View {
    let color: MateriaColor
    var size: CGFloat = 30
    /// Jewels past the day's capacity get a gold rim and a star.
    var overflow: Bool = false
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
            Ellipse()
                .fill(.white.opacity(0.75))
                .frame(width: size * 0.26, height: size * 0.17)
                .rotationEffect(.degrees(-24))
                .offset(x: -size * 0.14, y: -size * 0.22)
                .blur(radius: size * 0.035)

            if overflow, size >= 18 {
                Image(systemName: "star.fill")
                    .font(.system(size: size * 0.24))
                    .foregroundStyle(Chrome.gold)
                    .shadow(color: .black.opacity(0.6), radius: 1)
                    .offset(y: size * 0.22)
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

// MARK: - Slot rail

/// One period of sockets, laid out loose.
///
/// These used to be joined in pairs, echoing FF7's linked slots. The bar was
/// dropped because it never varied: in the game a link meant the left materia
/// modified the right one, and reading where links fell was how you judged a
/// weapon. Here every pair was identical and the sockets hold identical taps,
/// so the connector asserted a relationship that didn't exist.
///
/// `fills` is in the order the jewels were earned, so a combined day rail
/// reads left to right as the day progressed and mixes colours from every
/// activity. Anything past capacity extends the rail with gold-rimmed orbs
/// rather than being hidden — over-delivering shouldn't look identical to
/// hitting the number exactly.
struct SlotRail: View {
    let fills: [MateriaColor]
    let capacity: Int
    var size: CGFloat = 30
    var maxSlots: Int = 60

    /// Convenience for a single-activity rail.
    init(count: Int, color: MateriaColor, capacity: Int, size: CGFloat = 30, maxSlots: Int = 60) {
        self.fills = Array(repeating: color, count: max(0, count))
        self.capacity = capacity
        self.size = size
        self.maxSlots = maxSlots
    }

    init(fills: [MateriaColor], capacity: Int, size: CGFloat = 30, maxSlots: Int = 60) {
        self.fills = fills
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
                case .filled(let color, let overflow):
                    MateriaOrb(color: color, size: size, overflow: overflow)
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
