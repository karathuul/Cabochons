//
//  TiltSource.swift
//  Cabochons
//
//  Reads device tilt for the jewel shimmer. iOS uses CoreMotion;
//  macOS compiles to a no-op that always reports level, so view
//  code needs no #if.
//

internal import SwiftUI
import Observation

#if os(iOS)
import CoreMotion
#endif

/// Which way the device is leaning, in *screen* coordinates:
///   x > 0  →  the right edge of the screen is physically lower
///   y > 0  →  the bottom edge of the screen is physically lower
/// Magnitude is roughly 0...1, saturating at about 25° of lean.
@Observable
@MainActor
final class TiltSource {

    private(set) var tilt: CGPoint = .zero

    /// Driven from the user's setting AND scene phase, so the gyro
    /// isn't left spinning in the background.
    var isActive: Bool = false {
        didSet {
            guard isActive != oldValue else { return }
            isActive ? start() : stop()
        }
    }

    /// True only where real motion hardware exists. Use this to hide
    /// the settings row on macOS.
    static var isSupported: Bool {
        #if os(iOS)
        CMMotionManager().isDeviceMotionAvailable
        #else
        false
        #endif
    }

    // Tuning
    private let updateHz: Double = 30      // plenty for a slow shimmer, half the cost of 60
    private let gain: Double = 2.4         // lean → highlight travel
    private let glide: Double = 0.18       // output smoothing; lower = more languid
    private let recentre: Double = 0.004   // ≈8s to adopt a new resting angle

    #if os(iOS)
    private let motion = CMMotionManager()
    private var neutral: CMAcceleration?
    #endif

    private func start() {
        #if os(iOS)
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / updateHz
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let g = data?.gravity else { return }
            self.consume(gravity: g)
        }
        #endif
    }

    private func stop() {
        #if os(iOS)
        motion.stopDeviceMotionUpdates()
        neutral = nil
        #endif
        withAnimation(.easeOut(duration: 0.4)) { tilt = .zero }
    }

    #if os(iOS)
    private func consume(gravity g: CMAcceleration) {
        // Whatever angle you habitually hold the phone at drifts toward being
        // "level", so the highlight sits near its rest position instead of
        // pinned to one edge.
        if neutral == nil { neutral = g }
        neutral!.x += (g.x - neutral!.x) * recentre
        neutral!.y += (g.y - neutral!.y) * recentre

        // CoreMotion +y points to the top of the device; SwiftUI +y points down
        // the screen, hence the negation. If the highlight slides the wrong way
        // on device, flip these two signs — that's the usual culprit.
        let target = CGPoint(
            x:  clamp((g.x - neutral!.x) * gain),
            y: -clamp((g.y - neutral!.y) * gain)
        )

        tilt.x += (target.x - tilt.x) * glide
        tilt.y += (target.y - tilt.y) * glide
    }

    private func clamp(_ v: Double) -> Double { min(max(v, -1), 1) }
    #endif

    #if DEBUG
    /// Simulator has no motion hardware, so drive it by hand to tune the look.
    func debugSetTilt(_ p: CGPoint) { tilt = p }
    #endif
}
