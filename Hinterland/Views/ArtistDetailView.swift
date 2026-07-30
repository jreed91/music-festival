import SwiftUI

/// Artist artwork, bio, set times, and links out to Spotify and Instagram.
struct ArtistDetailView: View {
    let artistID: String

    @Environment(ScheduleStore.self) private var store
    @Environment(WeatherStore.self) private var weather
    @Environment(Favorites.self) private var favorites

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
                    links
                }
                .padding(20)
            }
        }
        .background(Theme.background)
        .navigationTitle(artist?.name ?? "Artist")
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(edges: .top)
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
                let day = store.data.day(containing: performance)
                HStack(spacing: 12) {
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
                .padding(14)
                .background(Theme.surface,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var links: some View {
        let spotify = artist?.spotifyArtistID
        let instagram = artist?.instagram

        if spotify != nil || instagram != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("Listen & follow")
                    .appFont(13, weight: .bold)
                    .foregroundStyle(Theme.tertiaryText)

                HStack(spacing: 10) {
                    if let spotify {
                        // Opens the Spotify app when installed, the web player otherwise.
                        LinkButton(title: "Spotify", symbol: "music.note",
                                   url: URL(string: "https://open.spotify.com/artist/\(spotify)"))
                    }
                    if let instagram {
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
