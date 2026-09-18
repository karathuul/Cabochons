//
//  OrbLab.swift
//  MateriaLog
//
//  Debug-only tuning harness. Sliders drive a live orb; the panel at the
//  bottom prints the values as Swift you can paste into OrbShading.
//
//  TARGET MEMBERSHIP: Materia only. Not the widget.
//

#if DEBUG
internal import SwiftUI

struct OrbLab: View {

    @State private var sh = OrbShading()
    @State private var motion = TiltSource()
    @State private var swatch = 0
    @State private var showCode = false
    /// Note-glint strength, 0 = no note. Matches what `NoteRules.glint`
    /// hands the orb, so you can tune the flare's range without writing notes.
    @State private var glint: CGFloat = 1

    // Swap this for however you actually vend a set of MateriaColors.
    private var colors: [MateriaColor] { [MateriaColor.magic] }

    private var color: MateriaColor { colors[swatch % colors.count] }

    var body: some View {
        VStack(spacing: 0) {
            stage
            Divider()
            controls
        }
        .background(Color.black)
        .environment(\.orbShading, sh)
        .environment(motion)
        .preferredColorScheme(.dark)
    }

    // MARK: Stage

    private var stage: some View {
        VStack(spacing: 22) {
            // Drag on the big orb to fake a tilt — the Simulator has no gyro,
            // so this stands in for holding the phone.
            MateriaOrb(color: color, size: 160, glint: glint)
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            motion.debugSetTilt(
                                CGPoint(x: max(-1, min(1, (v.location.x - 80) / 80)),
                                        y: max(-1, min(1, (v.location.y - 80) / 80)))
                            )
                        }
                        .onEnded { _ in
                            withAnimation(.easeOut(duration: 0.5)) {
                                motion.debugSetTilt(.zero)
                            }
                        }
                )

            // Small sizes are where shading usually falls apart.
            HStack(spacing: 16) {
                ForEach([12, 18, 24, 30, 44], id: \.self) { s in
                    MateriaOrb(color: color, size: CGFloat(s), glint: glint)
                }
            }

            HStack(spacing: 10) {
                ForEach(colors.indices, id: \.self) { i in
                    Button { swatch = i } label: {
                        Circle()
                            .fill(colors[i].core)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(.white.opacity(i == swatch ? 0.9 : 0)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: Controls

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {

                heading("Note glint")
                slide("strength", $glint, 0...1)

                heading("Body")
                slide("center x", $sh.bodyCenter.x, 0...1)
                slide("center y", $sh.bodyCenter.y, 0...1)
                slide("outer radius", $sh.bodyOuter, 0.3...1.4)

                heading("Bounce")
                slide("opacity", $sh.bounceOpacity, 0...1)
                slide("center x", $sh.bounceCenter.x, 0...1)
                slide("center y", $sh.bounceCenter.y, 0...1)
                slide("radius", $sh.bounceRadius, 0.1...1)

                heading("Rim")
                slide("opacity", $sh.rimOpacity, 0...1)
                slide("width", $sh.rimWidth, 0...0.15)

                heading("Specular")
                slide("width", $sh.specWidth, 0.05...0.6)
                slide("height", $sh.specHeight, 0.03...0.5)
                slide("angle", $sh.specAngle, -90...90)
                slide("offset x", $sh.specX, -0.4...0.4)
                slide("offset y", $sh.specY, -0.4...0.4)
                slide("blur", $sh.specBlur, 0...0.2)
                slide("opacity", $sh.specOpacity, 0...1)
                slide("tilt travel", $sh.specTravel, 0...0.5)

                heading("Glow")
                slide("near opacity", $sh.glowNearOpacity, 0...1)
                slide("near radius", $sh.glowNearRadius, 0...1)
                slide("far opacity", $sh.glowFarOpacity, 0...1)
                slide("far radius", $sh.glowFarRadius, 0...1.5)

                HStack {
                    Button("Reset") { sh = .standard }
                    Spacer()
                    Button(showCode ? "Hide values" : "Show values") { showCode.toggle() }
                }
                .padding(.vertical, 10)

                if showCode {
                    Text(literal)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 8))
                }
            }
            .padding(16)
        }
        .frame(maxHeight: 340)
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 12)
    }

    private func slide(_ label: String, _ value: Binding<CGFloat>, _ range: ClosedRange<CGFloat>) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.caption).frame(width: 92, alignment: .leading)
            Slider(value: value, in: range)
            Text(fmt(Double(value.wrappedValue)))
                .font(.system(.caption2, design: .monospaced))
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func slide(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.caption).frame(width: 92, alignment: .leading)
            Slider(value: value, in: range)
            Text(fmt(value.wrappedValue))
                .font(.system(.caption2, design: .monospaced))
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func fmt(_ v: Double) -> String { String(format: "%.3f", v) }

    private var literal: String {
        """
        var bodyCenter = UnitPoint(x: \(fmt(Double(sh.bodyCenter.x))), y: \(fmt(Double(sh.bodyCenter.y))))
        var bodyOuter: CGFloat = \(fmt(Double(sh.bodyOuter)))

        var bounceOpacity: Double = \(fmt(sh.bounceOpacity))
        var bounceCenter = UnitPoint(x: \(fmt(Double(sh.bounceCenter.x))), y: \(fmt(Double(sh.bounceCenter.y))))
        var bounceRadius: CGFloat = \(fmt(Double(sh.bounceRadius)))

        var rimOpacity: Double = \(fmt(sh.rimOpacity))
        var rimWidth: CGFloat = \(fmt(Double(sh.rimWidth)))

        var specWidth: CGFloat = \(fmt(Double(sh.specWidth)))
        var specHeight: CGFloat = \(fmt(Double(sh.specHeight)))
        var specAngle: Double = \(fmt(sh.specAngle))
        var specX: CGFloat = \(fmt(Double(sh.specX)))
        var specY: CGFloat = \(fmt(Double(sh.specY)))
        var specBlur: CGFloat = \(fmt(Double(sh.specBlur)))
        var specOpacity: Double = \(fmt(sh.specOpacity))
        var specTravel: CGFloat = \(fmt(Double(sh.specTravel)))

        var glowNearOpacity: Double = \(fmt(sh.glowNearOpacity))
        var glowNearRadius: CGFloat = \(fmt(Double(sh.glowNearRadius)))
        var glowFarOpacity: Double = \(fmt(sh.glowFarOpacity))
        var glowFarRadius: CGFloat = \(fmt(Double(sh.glowFarRadius)))
        """
    }
}

#Preview {
    OrbLab()
}
#endif
