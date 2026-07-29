import ActivityKit
import Foundation

/// The Live Activity that sits on the Lock Screen while a set you starred is playing.
///
/// Everything here is a plain value because ActivityKit archives the state and hands it
/// to the widget extension to draw — the extension has no access to the app's stores.
struct NowPlayingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var artist: String
        var stageName: String
        var start: Date
        var end: Date
        /// Whether this came out of the user's own lineup, as opposed to the app filling
        /// in with whatever is on when nothing is starred.
        var isStarred: Bool

        var nextArtist: String?
        var nextStageName: String?
        var nextStart: Date?

        var stage: Stage { Stage(name: stageName) }
        var nextStage: Stage? { nextStageName.map(Stage.init(name:)) }

        func isLive(at date: Date) -> Bool { date >= start && date < end }

        /// When the content stops being worth trusting: the end of the set, or the start
        /// of one that hasn't begun. Past it, iOS dims the activity rather than showing
        /// a confident wrong answer — which matters here, because a phone in a field has
        /// no way to receive an update.
        var staleDate: Date { Date() < start ? start : end }
    }

    /// "Hinterland 2026" — fixed for the life of the activity, so it belongs here rather
    /// than in the state.
    var festivalName: String
}

extension NowPlayingAttributes.ContentState {
    /// Nil when there is nothing left to show, which is the signal to end the activity.
    init?(focus: LineupFocus) {
        guard let headline = focus.headline else { return nil }
        // The follow-on line is only interesting when it isn't the set already on top.
        let following: Performance? = focus.next == headline ? nil : focus.next

        self.init(artist: headline.artist,
                  stageName: headline.stage,
                  start: headline.start,
                  end: headline.end,
                  isStarred: focus.isPersonal,
                  nextArtist: following?.artist,
                  nextStageName: following?.stage,
                  nextStart: following?.start)
    }
}
