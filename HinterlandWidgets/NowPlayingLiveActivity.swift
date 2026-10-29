import ActivityKit
import SwiftUI
import WidgetKit

/// The Lock Screen card and Dynamic Island presentation for a set that's on.
///
/// Every changing number here is a date the system animates by itself — a timer interval
/// or a relative style — because the app that started this card may well be closed, in a
/// pocket, in a field with no signal, and unable to send it a single update.
struct NowPlayingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPlayingAttributes.self) { context in
            LockScreenCard(state: context.state, festival: context.attributes.festivalName)
                .activityBackgroundTint(Theme.night)
                .activitySystemActionForegroundColor(Theme.sodium)
                .widgetURL(URL(string: "hinterland://lineup"))
        } dynamicIsland: { context in
            let state = context.state
            let stage = state.stage

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        StageGlyph(stage: stage, size: 8)
                        Text(stage.displayName.uppercased())
                            .appFont(11, weight: .bold)
                            .tracking(1.2)
                            .foregroundStyle(stage.color)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: state)
                        .appFont(14, weight: .bold)
                        .foregroundStyle(Theme.sodium)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.artist.uppercased())
                        .marqueeFont(34)
                        .foregroundStyle(Theme.sodium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        SetProgress(state: state)
                        if let following = state.nextArtist, let start = state.nextStart {
                            Text("Then \(following) · \(Format.time(start))")
                                .appFont(11)
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                StageGlyph(stage: stage, size: 12)
                    .accessibilityElement()
                    .accessibilityLabel("\(state.artist), \(stage.displayName)")
            } compactTrailing: {
                Countdown(state: state)
                    .appFont(13, weight: .bold)
                    .foregroundStyle(Theme.sodium)
                    .frame(maxWidth: 58)
            } minimal: {
                StageGlyph(stage: stage, size: 12)
                    .accessibilityElement()
                    .accessibilityLabel("\(state.artist), \(stage.displayName)")
            }
            .keylineTint(Theme.sodium)
            .widgetURL(URL(string: "hinterland://lineup"))
        }
    }
}

// MARK: - Lock Screen

private struct LockScreenCard: View {
    let state: NowPlayingAttributes.ContentState
    let festival: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(festival.uppercased())
                    .appFont(10, weight: .heavy)
                    .tracking(1.6)
                    .foregroundStyle(Theme.inkFaint)
                Spacer(minLength: 8)
                Text(state.isStarred ? "YOUR LINEUP" : "ON AIR")
                    .appFont(10, weight: .heavy)
                    .tracking(1.6)
                    .foregroundStyle(Theme.sodium)
            }

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(state.artist.uppercased())
                    .marqueeFont(52)
                    .foregroundStyle(Theme.sodium)
                    .onAirGlow()
                    // The card can't grow, so a long name shrinks rather than losing its end.
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Spacer(minLength: 4)
                Countdown(state: state)
                    .appFont(18, weight: .bold)
                    .foregroundStyle(Theme.ink)
            }

            HStack(spacing: 6) {
                StageGlyph(stage: state.stage, size: 8)
                Text(state.stage.displayName.uppercased())
                    .appFont(11, weight: .bold)
                    .tracking(1.4)
                Text("·")
                    .foregroundStyle(Theme.tertiaryText)
                Text(Format.range(state.start, state.end))
                    .appFont(12)
                    .foregroundStyle(Theme.secondaryText)
            }
            .foregroundStyle(state.stage.color)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(state.stage.displayName), "
                              + Format.spokenRange(state.start, state.end))

            SetProgress(state: state)

            if let following = state.nextArtist, let start = state.nextStart {
                Text("Then \(following)"
                     + (state.nextStage.map { " · \($0.displayName)" } ?? "")
                     + " · \(Format.time(start))")
                    .appFont(11)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(14)
        // The whole card is one set, so it's one stop on the Lock Screen. Combined rather
        // than given a written label, because a string can't carry the live countdown.
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Pieces

/// Time left in a set that's running, time until one that hasn't started.
private struct Countdown: View {
    let state: NowPlayingAttributes.ContentState

    var body: some View {
        // `Date()` is fine here in a way it isn't in a widget timeline: a Live Activity is
        // only ever rendered for the moment it's actually on screen.
        if state.isLive(at: Date()) {
            Text(timerInterval: state.start...state.end, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        } else {
            Text(state.start, style: .timer)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

/// A bar that drains across the set. Hidden before the set starts, where it would just be
/// an empty track.
private struct SetProgress: View {
    let state: NowPlayingAttributes.ContentState

    var body: some View {
        if state.isLive(at: Date()) {
            ProgressView(timerInterval: state.start...state.end, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(Theme.sodium)
        }
    }
}
