import ActivityKit
import Foundation
import Observation

/// Keeps a Lock Screen Live Activity pointed at the set you're about to watch.
///
/// The hard constraint is that a phone in the valley has no signal, so there are no push
/// updates to lean on: everything the card shows has to be either already in its state or
/// derivable from a date the system can tick on its own. That shapes the design — the app
/// re-syncs whenever it's in the foreground, the card counts down locally from the set
/// times it was handed, and `staleDate` tells iOS to dim it rather than keep showing a
/// stale answer confidently.
@Observable
final class LiveActivityController {
    /// How early a starred set may put a card on the Lock Screen. Earlier than this and
    /// it's clutter rather than information.
    private static let lookahead: TimeInterval = 90 * 60
    private static let storageKey = "liveActivityEnabled"

    /// On by default: it only ever appears for a set the user starred themselves, it ends
    /// on its own, and a feature you have to go and find in settings is one nobody has on
    /// the Saturday it would have helped. iOS still gates it behind its own system switch.
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.storageKey) }
    }

    private(set) var isRunning = false
    /// Set when ActivityKit refuses a request, so the settings screen can say why the
    /// card never appeared instead of leaving it a mystery.
    private(set) var failureReason: String?

    private var activity: Activity<NowPlayingAttributes>?

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: Self.storageKey) as? Bool ?? true
    }

    /// Whether iOS will allow activities at all — the per-app switch in Settings.
    var isPermittedBySystem: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Start, update or end the card to match the schedule as it stands right now.
    ///
    /// Safe to call often: it's a no-op when the content hasn't moved, which is what lets
    /// the caller run it on every foreground and every change to the lineup.
    @MainActor
    func sync(data: FestivalData, starred: Set<String>, now: Date = Date()) async {
        adoptRunningActivity()

        guard isEnabled, isPermittedBySystem else {
            await stop()
            return
        }

        let focus = Lineup.focus(in: data, starred: starred, at: now)
        // Only ever the user's own lineup. When nothing is starred the widget falls back
        // to the festival at large, but the Lock Screen is not the place to volunteer
        // that — an activity nobody asked for is an activity they turn off.
        guard focus.isPersonal,
              let state = NowPlayingAttributes.ContentState(focus: focus),
              state.start.timeIntervalSince(now) <= Self.lookahead else {
            await stop()
            return
        }

        let content = ActivityContent(state: state, staleDate: state.staleDate)

        if let activity {
            guard activity.content.state != state else { return }
            await activity.update(content)
            isRunning = true
        } else {
            do {
                let festival = "\(data.festival.name) \(data.festival.year)"
                activity = try Activity<NowPlayingAttributes>.request(
                    attributes: NowPlayingAttributes(festivalName: festival),
                    content: content,
                    pushType: nil)
                isRunning = true
                failureReason = nil
            } catch {
                // Most often "the app is in the background" or the system switch flipping
                // off between the check above and here. Neither is worth interrupting for.
                failureReason = error.localizedDescription
                isRunning = false
            }
        }
    }

    /// Ends the card now — the toggle going off, or nothing left to show.
    @MainActor
    func stop() async {
        adoptRunningActivity()
        guard let activity else {
            isRunning = false
            return
        }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
        isRunning = false
    }

    /// After a cold launch the app has no handle on a card iOS is still showing. Pick it
    /// back up rather than requesting a second one on top of it.
    private func adoptRunningActivity() {
        guard activity == nil else { return }
        activity = Activity<NowPlayingAttributes>.activities.first
        isRunning = activity != nil
    }
}
