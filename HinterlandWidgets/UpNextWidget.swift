import SwiftUI
import WidgetKit

/// "What am I watching next" on the Home and Lock Screen.
///
/// The timeline is built entirely from dates already on the phone, so it stays correct
/// through a weekend with no signal — WidgetKit only has to render entries the extension
/// handed it hours earlier.
struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpNextWidget", provider: UpNextProvider()) { entry in
            UpNextWidgetView(entry: entry)
        }
        .configurationDisplayName("Up Next")
        .description("The set you starred that's on now, and what follows it.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryInline, .accessoryRectangular, .accessoryCircular])
    }
}

struct UpNextEntry: TimelineEntry {
    let date: Date
    let focus: LineupFocus
}

struct UpNextProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpNextEntry {
        UpNextEntry(date: Date(), focus: Self.currentFocus())
    }

    func getSnapshot(in context: Context, completion: @escaping (UpNextEntry) -> Void) {
        completion(UpNextEntry(date: Date(), focus: Self.currentFocus()))
    }

    /// One entry now, then one at every remaining set boundary. Nothing changes on this
    /// widget except at the moment a set starts or ends, so there is no reason to wake up
    /// in between — and precomputing them is what makes it work offline.
    func getTimeline(in context: Context, completion: @escaping (Timeline<UpNextEntry>) -> Void) {
        let now = Date()
        guard let data = ScheduleFile.newest() else {
            let entry = UpNextEntry(date: now,
                                    focus: LineupFocus(current: nil, next: nil, isPersonal: false))
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(3600))))
            return
        }

        let starred = Favorites.storedIDs()
        let dates = [now] + Lineup.transitions(in: data, starred: starred, after: now)
        let entries = dates.map {
            UpNextEntry(date: $0, focus: Lineup.focus(in: data, starred: starred, at: $0))
        }

        // Past the last entry the festival is over as far as this phone knows, so there's
        // nothing to come back for until the app itself asks for a reload.
        completion(Timeline(entries: entries, policy: .never))
    }

    private static func currentFocus() -> LineupFocus {
        guard let data = ScheduleFile.newest() else {
            return LineupFocus(current: nil, next: nil, isPersonal: false)
        }
        return Lineup.focus(in: data, starred: Favorites.storedIDs())
    }
}

// MARK: - Views

struct UpNextWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UpNextEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { background }
            // Opens straight to the lineup rather than wherever the app was last left.
            .widgetURL(URL(string: "hinterland://lineup"))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    @ViewBuilder
    private var background: some View {
        switch family {
        case .systemSmall, .systemMedium:
            LinearGradient(colors: [Theme.surface, Theme.background],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            // Accessory families are drawn into the system's own material.
            Color.clear
        }
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let headline = entry.focus.headline {
                SetLabel(focus: entry.focus, performance: headline, at: entry.date)
                Text(headline.artist)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 4)
                Text(Stage(name: headline.stage).displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Stage(name: headline.stage).color)
                    .padding(.top, 2)
                Spacer(minLength: 4)
                CountdownLine(performance: headline, at: entry.date)
            } else {
                EmptyLineup()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            small
            if let following = followingSet {
                Divider().overlay(Theme.hairline)
                VStack(alignment: .leading, spacing: 3) {
                    Text("THEN")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Theme.tertiaryText)
                    Text(following.artist)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                    Text(Stage(name: following.stage).displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Stage(name: following.stage).color)
                    Text(Format.time(following.start))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The one after the headline, when it isn't the headline itself.
    private var followingSet: Performance? {
        guard let next = entry.focus.next, next != entry.focus.headline else { return nil }
        return next
    }

    // MARK: Lock Screen

    @ViewBuilder
    private var inline: some View {
        if let headline = entry.focus.headline {
            Text("\(headline.artist) · \(Format.time(headline.start))")
        } else {
            Text("No sets starred")
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let headline = entry.focus.headline {
                Text(headline.isLive(at: entry.date) ? "ON NOW" : "UP NEXT")
                    .font(.system(size: 11, weight: .bold))
                    .widgetAccentable()
                Text(headline.artist)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text("\(Stage(name: headline.stage).displayName) · \(Format.time(headline.start))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Hinterland")
                    .font(.system(size: 12, weight: .semibold))
                    .widgetAccentable()
                Text("Star a set to see it here")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var circular: some View {
        if let headline = entry.focus.headline, headline.isLive(at: entry.date) {
            // How much of the set is left, which is the one thing worth a glance at this
            // size — the ring drains on its own with no help from the extension.
            ProgressView(timerInterval: headline.start...headline.end, countsDown: true) {
                Image(systemName: Stage(name: headline.stage).symbol)
            } currentValueLabel: {
                Image(systemName: Stage(name: headline.stage).symbol)
                    .font(.system(size: 14))
            }
            .progressViewStyle(.circular)
            .widgetAccentable()
        } else if let headline = entry.focus.headline {
            VStack(spacing: 0) {
                Image(systemName: Stage(name: headline.stage).symbol)
                    .font(.system(size: 12))
                Text(headline.start, style: .time)
                    .font(.system(size: 11, weight: .medium))
            }
            .widgetAccentable()
        } else {
            Image(systemName: "star")
                .font(.system(size: 16))
                .widgetAccentable()
        }
    }
}

/// "ON NOW" while a set is playing, otherwise "YOUR NEXT SET" or "UP NEXT" depending on
/// whether this is the user's own lineup or the app filling in with the festival at large.
private struct SetLabel: View {
    let focus: LineupFocus
    let performance: Performance
    /// The entry's own date rather than `Date()` — WidgetKit renders entries ahead of the
    /// moment they're for, so "now" here is the timeline's now, not the renderer's.
    let at: Date

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 5, height: 5)
                .opacity(performance.isLive(at: at) ? 1 : 0)
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var label: String {
        if performance.isLive(at: at) { return "ON NOW" }
        return focus.isPersonal ? "YOUR NEXT SET" : "UP NEXT"
    }
}

/// Time remaining for a set in progress, start time for one that hasn't. Both are date
/// styles the system ticks itself, so the widget doesn't need waking to stay honest.
/// Laid out rather than concatenated — `Text` built from a timer interval doesn't
/// reliably survive `+`.
private struct CountdownLine: View {
    let performance: Performance
    let at: Date

    var body: some View {
        HStack(spacing: 4) {
            if performance.isLive(at: at) {
                Text(timerInterval: performance.start...performance.end, countsDown: true)
                    .monospacedDigit()
                Text("left")
            } else {
                Text(Format.time(performance.start))
                Text("·")
                Text(performance.start, style: .relative)
            }
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(Theme.secondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

private struct EmptyLineup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "star")
                .font(.system(size: 18))
                .foregroundStyle(Theme.accent)
            Text("Nothing starred")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text("Star sets in the app and they show up here.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
        }
    }
}
