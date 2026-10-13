// MARK: - Wordmark
// Screen titles in the app's house style: the sidebar's "Cabochons" and each
// page's name. Sets the title in Didot with a split fill cut from an orb's
// three faces: `rim` above the letters' midline, `core` running toward `deep`
// below it. The sidebar can swap in a vector "Wordmark" asset instead, once
// one exists in Assets.xcassets.
//
// Wordmark          the view: text in the house style, or the brand asset
// SplitFill         the TextRenderer behind the text
// .wordmark         the CabochonsColor the titles are cut from
// .capCenter        alignment through the middle of the capitals
// .wordmarkTitle    drop-in replacement for .navigationTitle. On iPhone the
//                   header replaces the navigation bar: back button (on
//                   pushed screens), wordmark and any accessories share one
//                   row pinned above the content, so pushes are plain slides
//                   with nothing in a bar to animate. On iPad the bar stays
//                   for the sidebar toggle; on macOS accessories go in the
//                   toolbar.
//
// APP TARGET ONLY. Do not add to CabochonsWidget. Uses Chrome and CabochonsColor
// from Components.swift.

internal import SwiftUI
internal import CoreText
#if os(macOS)
internal import AppKit
#else
internal import UIKit
#endif

// MARK: - House colour

extension CabochonsColor {
    /// The orb the titles are cut from. Its `core` is exactly the #61D5FF the
    /// wordmark was first hand-tuned with, and its `rim` lands near the old
    /// #C2EFFF.
    static let wordmark = CabochonsColor(hue: 0.544, saturation: 0.62, brightness: 1)
}

// MARK: - Alignment

extension VerticalAlignment {
    /// Halfway up a wordmark's capitals. The title is all caps, so the middle
    /// of its line box sits low (the box keeps room for descenders nothing
    /// uses). Round buttons centred on this line up with the letters instead.
    static let capCenter = VerticalAlignment(CapCenter.self)

    private nonisolated enum CapCenter: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat {
            d[VerticalAlignment.center]
        }
    }
}

// MARK: - View

struct Wordmark: View {
    let title: String
    /// Vector artwork to draw instead of text, if it's in the asset catalog.
    /// Only the sidebar's brand name has one; page titles are always text.
    var asset: String? = nil
    /// Drawn height of the artwork, and the point size of the text.
    var height: CGFloat = 36
    /// PostScript name of the text's font. Nil is SF Rounded Heavy. Must be
    /// built into the OS or bundled with the app.
    var fontName: String? = "Didot-Bold"
    /// The orb the text is cut from: `rim` above the seam, `core` into `deep`
    /// below it.
    var color: CabochonsColor = .wordmark
    /// How far from `core` toward `deep` the baseline gets. All the way is
    /// true to the orb, but `deep` is 1.7:1 against Chrome.panel and the
    /// letters' feet vanish. Halfway keeps the house blue around 4:1.
    var depth: Double = 0.5

    var body: some View {
        if let asset, Self.exists(asset) {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(height: height)
                .accessibilityLabel(title)
        } else {
            let halfCap = capHeight / 2
            Text(title)
                .font(
                    fontName.map { Font.custom($0, fixedSize: height) }
                        ?? Font.system(size: height, weight: .heavy, design: .rounded)
                )
                .tracking(height * 0.06)
                // Only the alpha is used; the renderer paints over it.
                .foregroundStyle(.white)
                .textCase(.uppercase)
                .textRenderer(SplitFill(
                    top: color.rim,
                    bottom: [color.core, color.core.mix(with: color.deep, by: depth)],
                    capRatio: fontName.map { SplitFill.capRatio(named: $0) } ?? SplitFill.sanFrancisco
                ))
                .accessibilityLabel(title)
                .alignmentGuide(.capCenter) { $0[.firstTextBaseline] - halfCap }
        }
    }

    /// Cap height of the text's font at its drawn size.
    private var capHeight: CGFloat {
        let font = fontName.map { CTFontCreateWithName($0 as CFString, height, nil) }
            ?? CTFontCreateUIFontForLanguage(.system, height, nil)
        return font.map(CTFontGetCapHeight) ?? height * 0.7
    }

    private static func exists(_ name: String) -> Bool {
        #if os(macOS)
        NSImage(named: name) != nil
        #else
        UIImage(named: name) != nil
        #endif
    }
}

// MARK: - Renderer

/// Solid `top` above the capitals' midline, a gradient through `bottom` from
/// the midline to the baseline. Measured from each line's real baseline and
/// the font's cap height, so the seam cuts the letters in half rather than
/// the line box (which is what a plain LinearGradient foreground would do).
///
/// `nonisolated` so the MainActor default doesn't stick to it; SwiftUI may
/// call `draw` wherever it renders.
nonisolated struct SplitFill: TextRenderer {
    /// Above the seam.
    var top: Color
    /// From the seam down to the baseline, in order.
    var bottom: [Color]
    /// Cap height ÷ ascent. San Francisco's, at every weight and in Rounded.
    var capRatio = SplitFill.sanFrancisco

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        let gradient = Gradient(stops: stops)
        for line in layout {
            let bounds = line.typographicBounds
            let baseline = bounds.origin.y
            let cap = bounds.ascent * capRatio
            // Paint the gradient only where the glyphs already are. The fill
            // rect is deliberately oversized; .sourceAtop discards everything
            // outside the letters.
            ctx.drawLayer { layer in
                layer.draw(line)
                layer.blendMode = .sourceAtop
                layer.fill(
                    Path(bounds.rect.insetBy(dx: -cap, dy: -cap)),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 0, y: baseline - cap),
                        endPoint: CGPoint(x: 0, y: baseline)
                    )
                )
            }
        }
    }

    /// Two stops share 0.5: that's the hard seam.
    private var stops: [Gradient.Stop] {
        let ramp = bottom.isEmpty ? [top] : bottom
        let step = 0.5 / CGFloat(max(ramp.count - 1, 1))
        var result = [
            Gradient.Stop(color: top, location: 0),
            Gradient.Stop(color: top, location: 0.5),
        ]
        for (i, color) in ramp.enumerated() {
            result.append(Gradient.Stop(color: color, location: 0.5 + step * CGFloat(i)))
        }
        return result
    }

    /// Cap height ÷ ascent for a font by PostScript name.
    static func capRatio(named name: String) -> CGFloat {
        let font = CTFontCreateWithName(name as CFString, 22, nil)
        // Unknown names fall back silently, and you'd be tuning the seam
        // against the wrong typeface.
        assert(CTFontCopyPostScriptName(font) as String == name,
               "\(name) isn't installed or bundled — check the PostScript name and UIAppFonts")
        return CTFontGetCapHeight(font) / CTFontGetAscent(font)
    }

    static let sanFrancisco: CGFloat = {
        guard let sf = CTFontCreateUIFontForLanguage(.system, 22, nil) else { return 0.74 }
        return CTFontGetCapHeight(sf) / CTFontGetAscent(sf)
    }()
}

// MARK: - Navigation title

extension View {
    /// The wordmark alone, for screens with nothing to put beside it.
    func wordmarkTitle(_ title: String, asset: String? = nil, backButton: Bool = false) -> some View {
        wordmarkTitle(title, asset: asset, backButton: backButton) { EmptyView() }
    }

    /// The wordmark with `accessories` (buttons, menus) at the trailing end
    /// of its row. Keeps the plain title for VoiceOver and the Mac window.
    /// Font, size and colour come from `Wordmark`'s defaults, so every screen
    /// matches.
    ///
    /// - Parameters:
    ///   - asset: vector artwork to use instead of text, if it exists.
    ///   - backButton: true on screens that get pushed. On iPhone the header
    ///     replaces the bar, so without it the only way back is the swipe.
    func wordmarkTitle<Accessories: View>(
        _ title: String,
        asset: String? = nil,
        backButton: Bool = false,
        @ViewBuilder accessories: () -> Accessories
    ) -> some View {
        modifier(WordmarkHeader(
            title: title,
            asset: asset,
            backButton: backButton,
            accessories: accessories()
        ))
    }
}

/// Why a header and not the bar: on push, iOS animates whatever is in the
/// bar's leading slot into the incoming back button, and a wordmark there
/// shows up as a box collapsing into the chevron. So in compact width the bar
/// is hidden on every wordmark screen and the header does its job, back
/// button included. Screens then slide in and out whole.
///
/// Because the bar is hidden, `.toolbar` items on these screens don't show on
/// iPhone. Pass buttons as `accessories` instead.
struct WordmarkHeader<Accessories: View>: ViewModifier {
    let title: String
    let asset: String?
    let backButton: Bool
    let accessories: Accessories

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss

    /// The collapsed split view: one screen at a time, pushed and popped.
    private var compact: Bool { sizeClass == .compact }
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            // Regular width (iPad, or a Pro Max in landscape) shows the
            // columns side by side, and the bar holds the sidebar toggle.
            .toolbarVisibility(compact ? .hidden : .visible, for: .navigationBar)
            // safeAreaBar rather than safeAreaInset: it takes part in the
            // scroll edge effect, so content fades out under the header
            // instead of scrolling into it.
            .safeAreaBar(edge: .top) {
                HStack(alignment: .capCenter, spacing: 12) {
                    if backButton && compact {
                        Button { dismiss() } label: {
                            Label("Back", systemImage: "chevron.backward")
                        }
                    }
                    Wordmark(title: title, asset: asset)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    HStack(spacing: 8) { accessories }
                }
                // Icon-only glass circles, so the buttons read like bar items.
                .labelStyle(.iconOnly)
                .menuStyle(.button)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
            }
        #else
        content
            .navigationTitle(title)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) { accessories }
            }
        #endif
    }
}

// MARK: - Previews

#Preview("Fonts") {
    VStack(alignment: .leading, spacing: 18) {
        // House style first, then alternates for comparison.
        Wordmark(title: "Cabochons")
        Wordmark(title: "Cabochons", fontName: nil)
        Wordmark(title: "Cabochons", fontName: "Copperplate-Bold")
        Wordmark(title: "Cabochons", fontName: "BodoniSvtyTwoITCTT-Bold")
    }
    .padding(40)
    .background(Chrome.panel)
}

/// Other orbs, for judging `depth`. Red and violet have the least luminance
/// to spare, so their baselines go dark first.
#Preview("Orb colours") {
    VStack(alignment: .leading, spacing: 14) {
        ForEach([0.02, 0.12, 0.38, 0.544, 0.78], id: \.self) { hue in
            Wordmark(title: "Today", color: CabochonsColor(hue: hue, saturation: 0.7, brightness: 1))
        }
    }
    .padding(40)
    .background(Chrome.panel)
}

/// Mirrors ContentView and DayView: a split view that collapses to a stack on
/// iPhone, so tapping Today runs the same push transition as the app.
#Preview("In the sidebar") {
    NavigationSplitView {
        List {
            NavigationLink("Today") {
                ScrollView {
                    Text("Today view")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
                .background(Chrome.panel.ignoresSafeArea())
                .wordmarkTitle("Today", backButton: true)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Chrome.panel)
        .wordmarkTitle("Cabochons", asset: "Wordmark") {
            Button("New", systemImage: "plus") {}
            Menu {
                Button("Guide…") {}
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
    } detail: {
        Text("Pick something")
    }
}
