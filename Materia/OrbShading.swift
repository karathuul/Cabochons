//
//  OrbShading.swift
//  MateriaLog
//
//  Every magic number in MateriaOrb's shading, in one place.
//  Lengths are fractions of the orb's diameter, so they hold at any size.
//

internal import SwiftUI

struct OrbShading: Equatable {

    // Body — the main radial gradient, rim → core → deep.
    var bodyCenter = UnitPoint(x: 0.34, y: 0.28)
    var bodyOuter: CGFloat = 0.78

    // Bounce — light off the socket floor, back up through the glass.
    var bounceOpacity: Double = 0.50
    var bounceCenter = UnitPoint(x: 0.68, y: 0.82)
    var bounceRadius: CGFloat = 0.42

    // Rim — the containing edge of the sphere.
    var rimOpacity: Double = 0.70
    var rimWidth: CGFloat = 0.045

    // Specular — the moving highlight.
    var specWidth: CGFloat = 0.26
    var specHeight: CGFloat = 0.17
    var specAngle: Double = -24
    var specX: CGFloat = -0.14
    var specY: CGFloat = -0.22
    var specBlur: CGFloat = 0.035
    var specOpacity: Double = 0.75
    /// How far the highlight travels at full tilt.
    var specTravel: CGFloat = 0.22

    // Glow — two stacked shadows in the jewel's own colour.
    var glowNearOpacity: Double = 0.55
    var glowNearRadius: CGFloat = 0.30
    var glowFarOpacity: Double = 0.30
    var glowFarRadius: CGFloat = 0.70

    static let standard = OrbShading()
}

private struct OrbShadingKey: EnvironmentKey {
    static let defaultValue = OrbShading.standard
}

extension EnvironmentValues {
    var orbShading: OrbShading {
        get { self[OrbShadingKey.self] }
        set { self[OrbShadingKey.self] = newValue }
    }
}
