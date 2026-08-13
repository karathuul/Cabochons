internal import SwiftUI

// MARK: - The orb

struct MateriaOrb: View {
    let color: MateriaColor
    var size: CGFloat = 30
    /// Jewels past the daily target get a gold rim and a star.
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

            if overflow {
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

// MARK: - Linked pair

/// Two sockets joined by a connector bar. This is the shape the whole app is
/// built around — sockets always come in pairs, and the bar is what makes a
/// half-filled pair read as unfinished.
struct LinkedPair: View {
    /// 1 or 2. An odd capacity ends in a single unlinked socket, which is how
    /// FF7 equipment actually looks — don't pad it out to an even pair.
    let slotCount: Int
    let filledCount: Int      // 0, 1 or 2
    let overflowCount: Int    // how many of the filled ones are past target
    let color: MateriaColor
    var size: CGFloat = 30

    private var spacing: CGFloat { size * 0.62 }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<max(1, slotCount), id: \.self) { index in
                slot(index: index)
            }
        }
        .background(alignment: .center) {
            if slotCount > 1 {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Chrome.steel.opacity(0.75), Chrome.steelHi.opacity(0.35)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: spacing + size * 0.5, height: size * 0.17)
                    .overlay(
                        Capsule()
                            .stroke(Color.black.opacity(0.45), lineWidth: 0.5)
                    )
            }
        }
    }

    @ViewBuilder
    private func slot(index: Int) -> some View {
        if index < filledCount {
            MateriaOrb(
                color: color,
                size: size,
                overflow: index >= (filledCount - overflowCount)
            )
        } else {
            MateriaSocket(size: size)
        }
    }
}

// MARK: - Slot rail

/// A full day of sockets. Capacity comes from the activity's target; anything
/// logged past capacity extends the rail with gold-rimmed orbs rather than
/// being hidden, because over-delivering shouldn't be invisible.
struct SlotRail: View {
    let filled: Int
    let capacity: Int
    let color: MateriaColor
    var size: CGFloat = 30
    var maxSlots: Int = 60

    private var totalSlots: Int {
        min(max(capacity, filled), maxSlots)
    }

    private var truncated: Int {
        max(0, filled - maxSlots)
    }

    var body: some View {
        let slots = max(totalSlots, 1)
        let starts = stride(from: 0, to: slots, by: 2).map { $0 }

        FlowLayout(spacing: size * 0.44, lineSpacing: size * 0.40) {
            ForEach(starts, id: \.self) { start in
                let slotsHere = min(2, slots - start)
                let filledHere = min(slotsHere, max(0, filled - start))
                let overflowHere = min(filledHere, max(0, (start + filledHere) - capacity))
                LinkedPair(
                    slotCount: slotsHere,
                    filledCount: filledHere,
                    overflowCount: overflowHere,
                    color: color,
                    size: size
                )
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

/// Wraps subviews onto as many lines as needed. Used so linked pairs never get
/// split across a line break.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: maxWidth.isFinite ? min(widest, maxWidth) : widest,
                      height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
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

// MARK: - Press feedback

struct OrbButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: configuration.isPressed)
    }
}
