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
    /// Counts presses of the lineup buttons, for their haptic.
    @State private var lineupTaps = 0

    /// So the rating control appears the moment the band goes on, rather than the next
    /// time this page is opened. Same 30s cadence as the NOW badge on the schedule.
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var artist: Artist? { store.data.artist(id: artistID) }
    private var performances: [Performance] { store.data.performances(forArtist: artistID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 24) {
                    setTimes
                    if let bio = artist?.bio, !bio.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ABOUT")
                                .appFont(13, weight: .bold)
                                .tracking(2.4)
                                .foregroundStyle(Theme.inkFaint)
                                .accessibilityAddTraits(.isHeader)
                            Text(bio)
                                .readingFont(17)
                                .foregroundStyle(Theme.ink)
                                .lineSpacing(3)
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
                .padding(.horizontal, 22)
                .padding(.top, 12)

                Horizon()
                    .padding(.top, 48)
            }
        }
        .background(Theme.night)
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

    /// The set the header talks about: the one on air, else the next, else the first.
    private var heroSet: Performance? {
        performances.first { $0.isLive(at: now) }
            ?? performances.first { $0.end > now }
            ?? performances.first
    }

    private var hero: some View {
        let live = heroSet?.isLive(at: now) == true
        return ZStack(alignment: .bottomLeading) {
            ArtistImage(artist: artist)
                .frame(height: 320)
                .frame(maxWidth: .infinity)
                .clipped()
                .accessibilityHidden(true)

            LinearGradient(
                colors: [.clear, Theme.night.opacity(0.75), Theme.night],
                startPoint: .center, endPoint: .bottom)
                .frame(height: 320)

            VStack(alignment: .leading, spacing: 4) {
                if let callsign = heroCallsign {
                    Text(callsign.uppercased())
                        .appFont(13, weight: .bold)
                        .tracking(2.4)
                        .foregroundStyle(live ? Theme.sodium : Theme.ink)
                        .shadow(color: Theme.night, radius: 6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // On air, the name is the screen's one glow, breathing the way the
                // NowPlaying block's does on the schedule. Off air, a `night` shadow keeps
                // it readable over the artwork.
                Text((artist?.name ?? "").uppercased())
                    .marqueeFont(96)
                    .foregroundStyle(live ? Theme.sodium : Theme.ink)
                    .shadow(color: live ? .clear : Theme.night, radius: 12)
                    .fixedSize(horizontal: false, vertical: true)
                    .breathingGlow(live)
                    .lampStrike(live)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 4)
        }
    }

    /// "ON AIR · MAIN STAGE" while they're playing, "SATURDAY · MAIN STAGE" otherwise.
    private var heroCallsign: String? {
        guard let performance = heroSet else { return nil }
        let stage = Stage(name: performance.stage).displayName
        if performance.isLive(at: now) { return "On air · \(stage)" }
        guard let day = store.data.day(containing: performance) else { return stage }
        return "\(day.weekday) · \(stage)"
    }

    private var setTimes: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(performances) { performance in
                VStack(alignment: .leading, spacing: 14) {
                    setHeader(performance)
                    // Only once they're on: there is nothing to say about a set that
                    // hasn't started.
                    if ratings.canRate(performance, at: now) {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                        ratingSection(performance)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.nightRaised)
            }
        }
    }

    private func setHeader(_ performance: Performance) -> some View {
        let day = store.data.day(containing: performance)
        let dayLine = day.map { "\($0.weekday) · \(Format.dayLabel($0))" } ?? ""
        let starred = favorites.contains(performance)
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(dayLine.uppercased())
                    .appFont(13, weight: .bold)
                    .tracking(2.4)
                    .foregroundStyle(Theme.inkMuted)
                Text(readout(performance).uppercased())
                    .appFont(22, weight: .medium)
                    .tracking(0.8)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                FlowLayout(spacing: 10, lineSpacing: 6) {
                    StageBadge(stage: Stage(name: performance.stage))
                    // Absent rather than guessed when the forecast doesn't reach
                    // this set yet.
                    if let hour = weather.snapshot?.hour(containing: performance.start) {
                        SetForecastBadge(hour: hour)
                    }
                }
            }
            // When, where and the weather as one stop, with the times read as a range.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenSetHeader(performance, day: day))

            Button {
                favorites.toggle(performance)
                lineupTaps += 1
            } label: {
                Label(starred ? "In my lineup" : "Add to my lineup", systemImage: "star.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlowButtonStyle(starred ? .on : .primary))
            .sensoryFeedback(.impact(weight: .light), trigger: lineupTaps)
            // "Starred" reads as a state and "Star" as a noun; say what the tap does.
            .accessibilityLabel(starred ? "Remove from My Lineup" : "Add to My Lineup")
        }
    }

    /// "9:30PM — 11:00PM · 75 MIN", the design system's readout.
    private func readout(_ performance: Performance) -> String {
        "\(Format.time(performance.start)) — \(Format.time(performance.end)) · "
            + Format.minutes(performance.duration)
    }

    private func spokenSetHeader(_ performance: Performance, day: FestivalDay?) -> String {
        var parts: [String] = []
        if let day { parts.append("\(day.weekday), \(Format.dayLabel(day))") }
        parts.append(Format.spokenRange(performance.start, performance.end))
        parts.append(Stage(name: performance.stage).displayName)
        if let hour = weather.snapshot?.hour(containing: performance.start) {
            parts.append(SetForecastBadge.spokenLabel(for: hour))
        }
        return parts.joined(separator: ", ")
    }

    /// Rate the set, see what the valley made of it, and once rated write a line about it.
    /// The rating is shared; the note is not, and never leaves the phone.
    private func ratingSection(_ performance: Performance) -> some View {
        let rating = ratings.rating(for: performance)
        let crowd = community.rating(for: performance)
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rating == nil ? "RATE IT" : "YOUR RATING")
                    .appFont(13, weight: .bold)
                    .tracking(2.4)
                    .foregroundStyle(Theme.inkFaint)
                    .accessibilityHidden(true)
                StarRating(stars: rating?.stars ?? 0) { value in
                    ratings.rate(performance, stars: value)
                }
            }

            if let crowd {
                // The count is the part that says how much the average is worth —
                // 4.6 from three people and 4.6 from three hundred are different
                // claims, and only one of them is worth planning a night around.
                VStack(alignment: .leading, spacing: 6) {
                    Text("THE VALLEY")
                        .appFont(13, weight: .bold)
                        .tracking(2.4)
                        .foregroundStyle(Theme.inkFaint)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        CrowdBadge(rating: crowd)
                        Text("from \(crowd.count) \(crowd.count == 1 ? "person" : "people")")
                            .appFont(13)
                            .foregroundStyle(Theme.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(CrowdBadge.spokenLabel(for: crowd))
            }

            if let note = rating?.note, !note.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("YOUR NOTE")
                        .appFont(13, weight: .bold)
                        .tracking(2.4)
                        .foregroundStyle(Theme.inkFaint)
                    Text(note)
                        .readingFont(17)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            }

            if rating != nil {
                Button {
                    noteTarget = performance
                } label: {
                    Label(rating?.note.isEmpty == false ? "Edit note" : "Add a note",
                          systemImage: "square.and.pencil")
                }
                .buttonStyle(GlowButtonStyle(.quiet))
            }
        }
    }

    @ViewBuilder
    private var links: some View {
        if let artist {
            VStack(alignment: .leading, spacing: 10) {
                Text("LISTEN & FOLLOW")
                    .appFont(13, weight: .bold)
                    .tracking(2.4)
                    .foregroundStyle(Theme.inkFaint)
                    .accessibilityAddTraits(.isHeader)

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
                // Each service's name as the service writes it, not in the button's
                // usual capitals.
                Label(title, systemImage: symbol)
                    .textCase(nil)
            }
            .buttonStyle(GlowButtonStyle(.quiet))
        }
    }
}
