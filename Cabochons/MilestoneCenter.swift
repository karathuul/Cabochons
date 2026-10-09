internal import SwiftUI

// APP TARGET ONLY. Do not add to CabochonsWidget.

// MARK: - Center

/// One place that knows a milestone was crossed, and fans it out to every
/// surface that cares. Today that's haptics and a banner; an achievements list
/// or a day-header flare would plug in here rather than at the call site.
///
/// Lives at the root and reaches views through the environment, because a
/// banner mounted inside `DayView` would vanish the moment you pushed into an
/// activity — and the haptic trigger may as well sit beside it.
@Observable
final class MilestoneCenter {

    /// What a banner is showing. Collapsed the same way the haptic is: the
    /// biggest crossing leads, the rest are listed under it. Queueing instead
    /// would mean six seconds of banner for one tap.
    struct Banner: Identifiable, Equatable {
        let id = UUID()
        /// Biggest first.
        let milestones: [Milestone]

        var lead: Milestone { milestones[0] }
        var rest: [Milestone] { Array(milestones.dropFirst()) }
    }

    /// Trigger for `.sensoryFeedback`. Composed patterns are played by `fire`.
    private(set) var pulse = HapticPulse()
    private(set) var banner: Banner?

    private var dismissal: Task<Void, Never>?

    // MARK: Input

    /// The one call a logging surface makes after a jewel lands.
    func record(_ crossings: Set<Milestone>) {
        pulse.fire(.from(crossings: crossings))
        guard !crossings.isEmpty else { return }

        let sorted = crossings.sorted {
            $0.weight == $1.weight ? $0.headline < $1.headline : $0.weight > $1.weight
        }
        show(Banner(milestones: sorted))
    }

    /// Undo. Clears any banner still up — celebrating something you just took
    /// back is the kind of detail that makes an app feel like it isn't paying
    /// attention.
    func recordUndo() {
        pulse.fire(.undo)
        dismiss()
    }

    func dismiss() {
        dismissal?.cancel()
        dismissal = nil
        banner = nil
    }

    // MARK: Timing

    private func show(_ new: Banner) {
        dismissal?.cancel()
        banner = new

        // VoiceOver users get nothing from a banner that auto-dismisses, so the
        // headline is spoken as well as drawn.
        #if os(iOS)
        AccessibilityNotification.Announcement(new.lead.headline).post()
        #endif

        let seconds = Self.duration(for: new.lead.weight) + Double(new.rest.count) * 0.7
        dismissal = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.banner = nil }
        }
    }

    /// Bigger things linger. Same instinct as the haptic swell scaling, so the
    /// two read as one event rather than two systems reacting separately.
    private static func duration(for weight: Milestone.Weight) -> Double {
        switch weight {
        case .small:  return 1.9
        case .medium: return 2.5
        case .large:  return 3.2
        case .huge:   return 4.2
        }
    }
}

// MARK: - Banner view

struct MilestoneBanner: View {
    let banner: MilestoneCenter.Banner
    let dismiss: () -> Void

    private var tint: Color {
        banner.lead.tint.map { Color(hue: $0.hue, saturation: $0.saturation, brightness: $0.brightness) }
            ?? Chrome.gold
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [tint, tint.opacity(0.35)],
                            center: UnitPoint(x: 0.34, y: 0.30),
                            startRadius: 0,
                            endRadius: 14
                        )
                    )
                    .overlay(Circle().stroke(tint.opacity(0.5), lineWidth: 1))
                    .frame(width: 18, height: 18)

                Text(banner.lead.headline)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            ForEach(banner.rest, id: \.key) { extra in
                Text(extra.headline)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Chrome.steelHi)
                    .padding(.leading, 28)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Chrome.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(tint.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        )
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { if $0.translation.height < 0 { dismiss() } }
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Mounting

extension View {
    /// Mount once, at the root. Carries both surfaces so a logging screen only
    /// ever talks to `MilestoneCenter.record`.
    func milestoneSurface(_ center: MilestoneCenter) -> some View {
        self
            .jewelFeedback(center.pulse)
            .overlay(alignment: .top) {
                if let banner = center.banner {
                    MilestoneBanner(banner: banner) { center.dismiss() }
                        .transition(
                            .move(edge: .top).combined(with: .opacity)
                        )
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: center.banner)
    }
}
