import SwiftUI

/// How After Dark moves: slowly, and only where something is alive. The on-air glow
/// breathes, fireflies blink and drift over the corn, something that has just become
/// yours strikes on like a sodium lamp, readouts roll like a clock radio as the minutes
/// change, and dead air drops out now and then like a station that isn't quite there.
///
/// With Reduce Motion on, all of it holds still: the glow at full strength, fireflies at
/// 60%, and every change lands at once. App only: a widget or a Live Activity is a still
/// picture, and keeps the steady `onAirGlow`.
enum Motion {
    /// The clock ticking over: readouts roll to the new minute and a set that has just
    /// started fades into its on-air row, rather than either jumping.
    static let tick = Animation.smooth(duration: 0.6)

    /// A new day coming in, or the schedule finding now.
    static let tune = Animation.smooth(duration: 0.4)
}

extension View {
    /// The on-air glow, breathing between 70% and 100% over four seconds. One per screen,
    /// on whatever is on air right now; off, it draws nothing.
    func breathingGlow(_ isOn: Bool = true) -> some View {
        modifier(BreathingGlow(isOn: isOn))
    }

    /// Strikes on like a sodium lamp when `isOn` turns true, a flicker and then steady,
    /// rather than snapping on. For the moment something becomes yours (a starred set, a
    /// rating, the day you picked) or goes on air. Going dark is instant, as a lamp's is.
    /// `delay` staggers a row of them, so five fireflies light one after another.
    func lampStrike(_ isOn: Bool, delay: Double = 0) -> some View {
        modifier(LampStrike(isOn: isOn, delay: delay))
    }

    /// Every few seconds, cuts out for a moment and stutters back. For DEAD AIR only.
    func signalDropout() -> some View {
        modifier(SignalDropout())
    }
}

private struct BreathingGlow: ViewModifier {
    let isOn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Always the same view, paused when there's nothing to breathe, so a set going on
        // air doesn't swap out what's underneath it (and any lamp strike playing on it).
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !isOn || reduceMotion)) { context in
            content.shadow(color: Theme.sodiumGlow.opacity(strength(at: context.date)), radius: 15)
        }
    }

    /// 70% to 100% and back over four seconds, eased at both ends.
    private func strength(at date: Date) -> Double {
        guard isOn else { return 0 }
        guard !reduceMotion else { return 1 }
        let phase = date.timeIntervalSinceReferenceDate * Double.pi * 2 / 4
        return 0.85 + 0.15 * sin(phase)
    }
}

private struct LampStrike: ViewModifier {
    let isOn: Bool
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Counts the times the lamp has come on: the flicker plays when this changes, so it
    /// plays on the way on and never on the way off.
    @State private var strikes = 0

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: Lamp(), trigger: strikes) { view, lamp in
                view.opacity(lamp.level)
            } keyframes: { _ in
                KeyframeTrack(\.level) {
                    MoveKeyframe(0.15)
                    LinearKeyframe(0.15, duration: max(delay, 0.01))
                    LinearKeyframe(1, duration: 0.05)
                    LinearKeyframe(0.4, duration: 0.06)
                    LinearKeyframe(1, duration: 0.07)
                    LinearKeyframe(0.7, duration: 0.08)
                    CubicKeyframe(1, duration: 0.24)
                }
            }
            .onChange(of: isOn) { _, nowOn in
                if nowOn && !reduceMotion { strikes += 1 }
            }
    }

    private struct Lamp {
        var level = 1.0
    }
}

private struct SignalDropout: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var level = 1.0

    func body(content: Content) -> some View {
        content
            .opacity(level)
            // Hard cuts rather than fades, set from a sleeping task rather than a frame
            // clock: a signal drops out, it doesn't dim, and this costs nothing in between.
            .task(id: reduceMotion) {
                level = 1
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    for (opacity, wait) in Self.stutter {
                        try? await Task.sleep(for: .seconds(wait))
                        if Task.isCancelled { return }
                        level = opacity
                    }
                }
            }
    }

    /// Steady for a few seconds, then out, half back, out, and back: (level, after how long).
    private static let stutter: [(Double, Double)] = [
        (0.25, 6.5), (1, 0.07), (0.5, 0.06), (0.25, 0.05), (1, 0.08),
    ]
}
