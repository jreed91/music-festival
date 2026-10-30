import SwiftUI

/// One set in a list: start time, the artist in heavy Barlow, stage and rating, and the
/// star that drives My Lineup. The SetRow of the After Dark design system.
///
/// The set on air is the one full-bleed `sodium` fill in a list; a starred set's time
/// and star are `sodium`; a set that's over fades to `inkFaint`. Names wrap rather than
/// truncate, however long and however large the reader's text is.
struct PerformanceRow: View {
    let performance: Performance
    var showsConflictWarning = false
    /// "9:30pm" rather than "9:30", for lists with no hour numeral beside them.
    var showsFullTime = false

    @Environment(ScheduleStore.self) private var store
    @Environment(Favorites.self) private var favorites
    @Environment(Ratings.self) private var ratings
    @Environment(CommunityRatings.self) private var community

    /// Counts taps on this row's star, for the haptic: keyed to the tap rather than to
    /// whether the set is starred, so starring it elsewhere doesn't tick every list it's in.
    @State private var starTaps = 0

    private var isStarred: Bool { favorites.contains(performance) }
    private var isLive: Bool { performance.isLive(at: Date()) }
    private var isOver: Bool { performance.end <= Date() }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(showsFullTime ? Format.time(performance.start) : Format.clock(performance.start))
                .appFont(20, weight: .bold)
                .monospacedDigit()
                .foregroundStyle(timeColor)
                .frame(minWidth: 52, alignment: .leading)
                .fixedSize()

            VStack(alignment: .leading, spacing: 5) {
                Text(performance.artist.uppercased())
                    .listNameFont()
                    .foregroundStyle(isLive ? Theme.onSodium : (isOver ? Theme.inkFaint : Theme.ink))
                    .fixedSize(horizontal: false, vertical: true)

                FlowLayout(spacing: 10, lineSpacing: 6) {
                    if isLive {
                        Text("ON AIR")
                            .appFont(12, weight: .heavy)
                            .tracking(1.6)
                            .foregroundStyle(Theme.onSodium)
                    }
                    if isLive {
                        Text(Stage(name: performance.stage).displayName.uppercased())
                            .appFont(12, weight: .bold)
                            .tracking(1.4)
                            .foregroundStyle(Theme.onSodium)
                    } else {
                        StageBadge(stage: Stage(name: performance.stage), compact: true)
                    }
                    // How long it runs is part of deciding whether to go, so it's
                    // muted rather than faint, until the set is over.
                    Text(Format.minutes(performance.duration))
                        .appFont(12, weight: .bold)
                        .tracking(1.4)
                        .foregroundStyle(lengthColor)
                    // One number per row: yours if you gave one, the crowd's if you
                    // didn't. Both at this size is a row nobody can read at a glance.
                    if !isLive {
                        if let rating = ratings.rating(for: performance) {
                            RatingBadge(stars: rating.stars, compact: true)
                        } else if let crowd = community.rating(for: performance) {
                            CrowdBadge(rating: crowd, compact: true)
                        }
                    }
                }

                if showsConflictWarning, let minutes = clashMinutes {
                    Text("CLASH · \(minutes) MIN")
                        .appFont(12, weight: .heavy)
                        .tracking(1.4)
                        .foregroundStyle(Theme.onCaution)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Theme.caution)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                favorites.toggle(performance)
                starTaps += 1
            } label: {
                Image(systemName: "star.fill")
                    .appFont(18)
                    .foregroundStyle(starColor)
                    .lampStrike(isStarred)
                    .frame(width: 44, height: 44)   // keep a comfortable tap target
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: starTaps)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, isLive ? 12 : 0)
        .padding(.leading, showsConflictWarning ? 12 : 0)
        .background(isLive ? Theme.sodium : Color.clear)
        .overlay(alignment: .leading) {
            if showsConflictWarning {
                Rectangle().fill(Theme.caution).frame(width: 3)
            }
        }
        .overlay(alignment: .bottom) {
            if !isLive {
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
        }
        // A set starting while you watch the list strikes its row on.
        .lampStrike(isLive)
        .contentShape(Rectangle())
        // One stop per set for VoiceOver, artist first. Left to itself VoiceOver builds
        // the row's label from its pieces in drawing order — "8:00pm – 9:15pm, NOW",
        // then the artist — and the star button inside it is hard to reach at all.
        // Every caller wraps this in a link to the artist, so double-tap opens them, and
        // the star becomes an action on the row: swipe up or down to it, as in Mail.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
        .accessibilityAction(named: isStarred ? "Remove from My Lineup" : "Add to My Lineup") {
            favorites.toggle(performance)
        }
        .accessibilityInputLabels([performance.artist])
    }

    private var timeColor: Color {
        if isLive { return Theme.onSodium }
        if isOver { return Theme.inkFaint }
        return isStarred ? Theme.sodium : Theme.inkMuted
    }

    private var lengthColor: Color {
        if isLive { return Theme.onSodium }
        return isOver ? Theme.inkFaint : Theme.inkMuted
    }

    private var starColor: Color {
        if isLive { return isStarred ? Theme.onSodium : Theme.onSodium.opacity(0.35) }
        return isStarred ? Theme.sodium : Theme.unlit
    }

    /// The longest overlap this set has with another starred set, in minutes.
    private var clashMinutes: Int? {
        let overlaps = favorites.conflicts(in: store.data).compactMap { pair -> TimeInterval? in
            guard pair.0 == performance || pair.1 == performance else { return nil }
            return min(pair.0.end, pair.1.end).timeIntervalSince(max(pair.0.start, pair.1.start))
        }
        guard let longest = overlaps.max() else { return nil }
        return Int((longest / 60).rounded())
    }

    private var spokenSummary: String {
        var parts = [performance.artist,
                     Format.spokenRange(performance.start, performance.end),
                     Stage(name: performance.stage).displayName]
        if isLive { parts.append("On air") }
        if isStarred { parts.append("In My Lineup") }
        if let rating = ratings.rating(for: performance) {
            parts.append(RatingBadge.spokenLabel(stars: rating.stars))
        } else if let crowd = community.rating(for: performance) {
            parts.append(CrowdBadge.spokenLabel(for: crowd))
        }
        if showsConflictWarning {
            parts.append(clashMinutes.map { "Clashes with another set in My Lineup by \($0) minutes" }
                         ?? "Overlaps another set in My Lineup")
        }
        return parts.joined(separator: ", ")
    }
}
