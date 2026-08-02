import Combine
import SwiftUI

/// Artist artwork, bio, set times, the rating for each of them, their top songs on Apple
/// Music, and links out to Apple Music, Spotify and Instagram.
struct ArtistDetailView: View {
    let artistID: String

    @Environment(ScheduleStore.self) private var store
    @Environment(WeatherStore.self) private var weather
    @Environment(Favorites.self) private var favorites
    @Environment(Ratings.self) private var ratings
    @Environment(CommunityRatings.self) private var community
    @Environment(AppleMusicStore.self) private var music
    @Environment(PreviewPlayer.self) private var preview

    @State private var now = Date()
    /// The set whose note is being written, which is what the sheet is presenting.
    @State private var noteTarget: Performance?

    /// So the rating control appears the moment the band goes on, rather than the next
    /// time this page is opened. Same 30s cadence as the NOW badge on the schedule.
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var artist: Artist? { store.data.artist(id: artistID) }
    private var performances: [Performance] { store.data.performances(forArtist: artistID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 20) {
                    setTimes
                    if let bio = artist?.bio, !bio.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About")
                                .appFont(13, weight: .bold)
                                .foregroundStyle(Theme.tertiaryText)
                            Text(bio)
                                .appFont(15)
                                .foregroundStyle(.white.opacity(0.86))
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    // Nothing at all for the handful the schedule says aren't on Apple
                    // Music: a heading explaining why is worse than the space it takes.
                    if let artist, artist.isOnAppleMusic {
                        AppleMusicSection(artist: artist)
                    }
                    links
                }
                .padding(20)
            }
        }
        .background(Theme.background)
        .navigationTitle(artist?.name ?? "Artist")
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(edges: .top)
        .onReceive(ticker) { now = $0 }
        // A preview belongs to the page that started it: walking back to the schedule
        // should leave the field quiet, not trailing 30 seconds of someone's single.
        .onDisappear { preview.stop() }
        .sheet(item: $noteTarget) { performance in
            SetNoteView(performance: performance,
                        note: ratings.rating(for: performance)?.note ?? "")
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            ArtistImage(artist: artist)
                .frame(height: 320)
                .frame(maxWidth: .infinity)
                .clipped()

            LinearGradient(
                colors: [.clear, Theme.background.opacity(0.75), Theme.background],
                startPoint: .center, endPoint: .bottom)
                .frame(height: 320)

            Text(artist?.name ?? "")
                .appFont(32, weight: .heavy)
                .foregroundStyle(.white)
                .shadow(radius: 12)
                .padding(20)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var setTimes: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(performances) { performance in
                VStack(alignment: .leading, spacing: 12) {
                    setHeader(performance)
                    // Only once they're on: there is nothing to say about a set that
                    // hasn't started.
                    if ratings.canRate(performance, at: now) {
                        Divider().overlay(Theme.hairline)
                        ratingSection(performance)
                    }
                }
                .padding(14)
                .background(Theme.surface,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func setHeader(_ performance: Performance) -> some View {
        let day = store.data.day(containing: performance)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(day.map { "\($0.weekday) · \(Format.dayLabel($0))" } ?? "")
                    .appFont(11, weight: .bold)
                    .foregroundStyle(Theme.tertiaryText)
                Text(Format.range(performance.start, performance.end))
                    .appFont(17, weight: .semibold)
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    StageBadge(stage: Stage(name: performance.stage))
                    // Absent rather than guessed when the forecast doesn't reach
                    // this set yet.
                    if let hour = weather.snapshot?.hour(containing: performance.start) {
                        SetForecastBadge(hour: hour)
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                favorites.toggle(performance)
            } label: {
                let starred = favorites.contains(performance)
                Label(starred ? "Starred" : "Star",
                      systemImage: starred ? "star.fill" : "star")
                    .appFont(13, weight: .semibold)
                    .foregroundStyle(starred ? Theme.background : Theme.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(starred ? Theme.accent : Theme.accent.opacity(0.16),
                                in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    /// Rate the set, see what everyone else made of it, and once rated write a line about
    /// it. The stars are shared; the note is not, and never leaves the phone.
    private func ratingSection(_ performance: Performance) -> some View {
        let rating = ratings.rating(for: performance)
        let crowd = community.rating(for: performance)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(rating == nil ? "How was it?" : "Your rating")
                    .appFont(11, weight: .bold)
                    .foregroundStyle(Theme.tertiaryText)
                Spacer(minLength: 0)
                if let crowd {
                    // The count is the part that says how much the average is worth —
                    // 4.6 from three people and 4.6 from three hundred are different
                    // claims, and only one of them is worth planning a night around.
                    HStack(spacing: 5) {
                        CrowdBadge(rating: crowd)
                        Text("\(crowd.count) \(crowd.count == 1 ? "rating" : "ratings")")
                            .appFont(11)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }
            }

            HStack(spacing: 8) {
                StarRating(stars: rating?.stars ?? 0) { value in
                    ratings.rate(performance, stars: value)
                }
                Spacer(minLength: 0)
                if rating != nil {
                    Button {
                        noteTarget = performance
                    } label: {
                        Label(rating?.note.isEmpty == false ? "Edit note" : "Add note",
                              systemImage: "square.and.pencil")
                            .appFont(12, weight: .semibold)
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let note = rating?.note, !note.isEmpty {
                Text(note)
                    .appFont(13)
                    .foregroundStyle(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Theme.surfaceRaised,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var links: some View {
        if let artist {
            VStack(alignment: .leading, spacing: 8) {
                Text("Listen & follow")
                    .appFont(13, weight: .bold)
                    .foregroundStyle(Theme.tertiaryText)

                // Three buttons now, and they grow with Dynamic Type — a row that wraps
                // beats one whose third button is off the right edge.
                FlowLayout(spacing: 10) {
                    // Their page in Apple Music once we've found them there, a search for
                    // their name until then, so this is never a dead button.
                    LinkButton(title: "Apple Music", symbol: "music.note",
                               url: music.artistURL(for: artist))
                    if let spotify = artist.spotifyArtistID {
                        // Opens the Spotify app when installed, the web player otherwise.
                        LinkButton(title: "Spotify", symbol: "waveform",
                                   url: URL(string: "https://open.spotify.com/artist/\(spotify)"))
                    }
                    if let instagram = artist.instagram {
                        LinkButton(title: "Instagram", symbol: "camera",
                                   url: URL(string: "https://www.instagram.com/\(instagram)/"))
                    }
                }
            }
        }
    }
}

private struct LinkButton: View {
    let title: String
    let symbol: String
    let url: URL?

    var body: some View {
        if let url {
            Link(destination: url) {
                Label(title, systemImage: symbol)
                    .appFont(14, weight: .semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Theme.surfaceRaised, in: Capsule())
            }
        }
    }
}
