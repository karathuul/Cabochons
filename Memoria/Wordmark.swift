// MARK: - Wordmark
// The app's name in the sidebar's navigation bar. Draws the vector "Wordmark"
// asset if one is in Assets.xcassets; until then, falls back to the title as
// text with a split fill: solid gold above the letters' midline, a gradient
// below it that deepens toward the baseline.
//
// Wordmark          the view: asset if present, split-fill text if not
// SplitFill         the TextRenderer behind the fallback
// .wordmarkTitle    drop-in replacement for .navigationTitle on iOS
//
// APP TARGET ONLY. Do not add to MemoriaWidget. Uses Chrome and Color(hex:)
// from Components.swift.

internal import SwiftUI
internal import CoreText
#if os(macOS)
internal import AppKit
#else
internal import UIKit
#endif

// MARK: - View

struct Wordmark: View {
    let title: String
    var asset = "Wordmark"
    /// Drawn height of the artwork, and the point size of the fallback text.
    var height: CGFloat = 22
    /// PostScript name of the fallback's font, e.g. "Didot-Bold". Nil is
    /// SF Rounded Heavy. Must be built into the OS or bundled with the app.
    var fontName: String? = nil

    var body: some View {
        if Self.exists(asset) {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(height: height)
                .accessibilityLabel(title)
        } else {
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
                    capRatio: fontName.map { SplitFill.capRatio(named: $0) } ?? SplitFill.sanFrancisco
                ))
                .accessibilityLabel(title)
        }
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
    var top = Color(hex: 0xFAFFF0)
    var bottom = [Color(hex: 0xE2F2C4), Color(hex: 0xCCE09D)]    
    /// Cap height ÷ ascent. San Francisco's, at every weight and in Rounded.
    var capRatio = SplitFill.sanFrancisco

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        let gradient = Gradient(stops: stops)
        for line in layout {
            let bounds = line.typographicBounds
            let baseline = bounds.origin.y
            let cap = bounds.ascent * capRatio
            var paint = ctx
            paint.clipToLayer { $0.draw(line) }
            paint.fill(
                Path(bounds.rect.insetBy(dx: -cap, dy: -cap)),
                with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: 0, y: baseline - cap),
                    endPoint: CGPoint(x: 0, y: baseline)
                )
            )
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
    /// Keeps the plain title for VoiceOver, the back button and the Mac
    /// window. On iOS the wordmark sits at the bar's leading edge and the
    /// centred title text is blanked so the name doesn't appear twice.
    func wordmarkTitle(_ title: String, fontName: String? = nil, height: CGFloat = 22) -> some View {
        self
            .navigationTitle(title)
            #if os(iOS)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Bar items get proposed a narrow width and Text truncates
                    // to "…" rather than overflowing. Ask for its full size.
                    Wordmark(title: title, height: height, fontName: fontName)
                        .lineLimit(1)
                        .fixedSize()
                }
                // No glass capsule behind it: it's a logo, not a button.
                .sharedBackgroundVisibility(.hidden)

                // A principal item takes the title's slot; an empty one
                // keeps the system from centring "Memoria" in plain text.
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                }
            }
            #endif
    }
}

// MARK: - Previews

#Preview("Fallback faces") {
    VStack(alignment: .leading, spacing: 18) {
        Wordmark(title: "Memoria", asset: "no-such-asset", height: 26)
        Wordmark(title: "Memoria", asset: "no-such-asset", height: 26, fontName: "Didot-Bold")
        Wordmark(title: "Memoria", asset: "no-such-asset", height: 26, fontName: "Copperplate-Bold")
        Wordmark(title: "Memoria", asset: "no-such-asset", height: 26, fontName: "BodoniSvtyTwoITCTT-Bold")
    }
    .padding(40)
    .background(Chrome.panel)
}

#Preview("In the bar") {
    NavigationStack {
        List { Text("Today") }
            .scrollContentBackground(.hidden)
            .background(Chrome.panel)
            .wordmarkTitle("Memoria")
    }
}
