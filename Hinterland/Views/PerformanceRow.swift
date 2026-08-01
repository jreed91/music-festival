import SwiftUI

/// One set in a list: artwork, time, artist, stage, and the star that drives My Lineup.
struct PerformanceRow: View {
    let performance: Performance
    var showsConflictWarning = false

    @Environment(ScheduleStore.self) private var store
    @Environment(Favorites.self) private var favorites
    @Environment(Ratings.self) private var ratings

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
                    if let rating = ratings.rating(for: performance) {
                        RatingBadge(stars: rating.stars, compact: true)
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
            .accessibilityLabel(isStarred ? "Remove \(performance.artist) from My Lineup"
                                          : "Add \(performance.artist) to My Lineup")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isLive ? Theme.accent.opacity(0.55) : Color.clear, lineWidth: 1.5)
        )
    }
}
