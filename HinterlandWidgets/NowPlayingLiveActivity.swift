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
                .activityBackgroundTint(Theme.background)
                .activitySystemActionForegroundColor(Theme.accent)
                .widgetURL(URL(string: "hinterland://lineup"))
        } dynamicIsland: { context in
            let state = context.state
            let stage = state.stage

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(stage.displayName, systemImage: stage.symbol)
                        .appFont(12, weight: .semibold)
                        .foregroundStyle(stage.color)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: state)
                        .appFont(13, weight: .semibold, design: .rounded)
                        .foregroundStyle(Theme.accent)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.artist)
                        .appFont(17, weight: .bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
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
                Image(systemName: stage.symbol)
                    .foregroundStyle(stage.color)
            } compactTrailing: {
                Countdown(state: state)
                    .appFont(12, weight: .semibold, design: .rounded)
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: 58)
            } minimal: {
                Image(systemName: stage.symbol)
                    .foregroundStyle(stage.color)
            }
            .keylineTint(Theme.accent)
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
                    .foregroundStyle(Theme.tertiaryText)
                Spacer(minLength: 8)
                Text(state.isStarred ? "YOUR LINEUP" : "ON NOW")
                    .appFont(10, weight: .heavy)
                    .foregroundStyle(Theme.accent)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(state.artist)
                    .appFont(22, weight: .bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 4)
                Countdown(state: state)
                    .appFont(15, weight: .semibold, design: .rounded)
                    .foregroundStyle(Theme.accent)
            }

            HStack(spacing: 6) {
                Image(systemName: state.stage.symbol)
                    .appFont(10, weight: .semibold)
                Text(state.stage.displayName)
                    .appFont(12, weight: .semibold)
                Text("·")
                    .foregroundStyle(Theme.tertiaryText)
                Text(Format.range(state.start, state.end))
                    .appFont(12)
                    .foregroundStyle(Theme.secondaryText)
            }
            .foregroundStyle(state.stage.color)

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
            .tint(state.stage.color)
        }
    }
}
