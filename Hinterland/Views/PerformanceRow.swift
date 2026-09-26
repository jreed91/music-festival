import SwiftUI

/// One set in a list: artwork, time, artist, stage, and the star that drives My Lineup.
struct PerformanceRow: View {
    let performance: Performance
    var showsConflictWarning = false

    @Environment(ScheduleStore.self) private var store
    @Environment(Favorites.self) private var favorites
    @Environment(Ratings.self) private var ratings
    @Environment(CommunityRatings.self) private var community

    private var artist: Artist? { store.data.artist(id: performance.artistId) }
    private var isStarred: Bool { favorites.contains(performance) }
    private var isLive: Bool { performance.isLive(at: Date()) }

    var body: some View {
        HStack(spacing: 12) {
            ArtistImage(artist: artist, size: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.hairline)
                )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(Format.range(performance.start, performance.end))
                        .appFont(12, weight: .medium, design: .rounded)
                        .foregroundStyle(Theme.secondaryText)
                    if isLive {
                        Text("NOW")
                            .appFont(9, weight: .heavy)
                            .foregroundStyle(Theme.background)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.accent, in: Capsule())
                    }
                }

                Text(performance.artist)
                    .appFont(17, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    StageBadge(stage: Stage(name: performance.stage), compact: true)
                    // One number per row: yours if you gave one, the crowd's if you
                    // didn't. Both at this size is a row nobody can read at a glance.
                    if let rating = ratings.rating(for: performance) {
                        RatingBadge(stars: rating.stars, compact: true)
                    } else if let crowd = community.rating(for: performance) {
                        CrowdBadge(rating: crowd, compact: true)
                    }
                    if showsConflictWarning {
                        Label("Overlaps", systemImage: "exclamationmark.triangle.fill")
                            .appFont(10, weight: .semibold)
                            .foregroundStyle(Theme.warning)
                    }
                }
            }

            Spacer(minLength: 4)

            Button {
                favorites.toggle(performance)
            } label: {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .appFont(18)
                    .foregroundStyle(isStarred ? Theme.accent : Theme.tertiaryText)
                    .frame(width: 44, height: 44)   // keep a comfortable tap target
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isLive ? Theme.accent.opacity(0.55) : Color.clear, lineWidth: 1.5)
        )
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

    private var spokenSummary: String {
        var parts = [performance.artist,
                     Format.spokenRange(performance.start, performance.end),
                     Stage(name: performance.stage).displayName]
        if isLive { parts.append("On now") }
        if isStarred { parts.append("In My Lineup") }
        if let rating = ratings.rating(for: performance) {
            parts.append(RatingBadge.spokenLabel(stars: rating.stars))
        } else if let crowd = community.rating(for: performance) {
            parts.append(CrowdBadge.spokenLabel(for: crowd))
        }
        if showsConflictWarning { parts.append("Overlaps another set in My Lineup") }
        return parts.joined(separator: ", ")
    }
}
