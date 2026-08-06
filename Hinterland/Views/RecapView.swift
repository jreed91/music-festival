import Combine
import SwiftUI

/// Routes out of the recap that aren't a set or a past year.
enum RecapRoute: Hashable {
    /// The day-by-day schedule, which is a screen you go and look at once the festival is
    /// over rather than the screen you live on.
    case schedule
}

/// The first tab, whichever way round the festival is.
///
/// Owns the navigation stack for both screens so the recap can push the schedule and the
/// schedule can still push everything it always could. Which one is the root is decided by
/// the clock against the last set in `schedule.json` — no flag, no build, and next year's
/// schedule turns it back over on its own.
struct FestivalHomeView: View {
    @Environment(ScheduleStore.self) private var store

    @State private var now = Date()

    /// A minute's granularity on a thing that happens once a year is more than enough, and
    /// it means the phone in someone's pocket at the end of the last set rolls over to the
    /// recap by itself rather than on next launch.
    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Group {
                if store.data.isOver(at: now) {
                    RecapView()
                } else {
                    ScheduleView()
                }
            }
            .navigationDestination(for: Performance.self) { performance in
                ArtistDetailView(artistID: performance.artistId)
            }
            .navigationDestination(for: WeatherRoute.self) { _ in
                WeatherView()
            }
            .navigationDestination(for: RatingsRoute.self) { _ in
                RatingsView()
            }
            .navigationDestination(for: RecapRoute.self) { _ in
                ScheduleView()
            }
            .navigationDestination(for: PastLineupRoute.self) { route in
                switch route {
                case .index:
                    PastLineupsView()
                case .year(let value):
                    if let year = store.pastLineups.year(value) {
                        PastYearView(year: year)
                    }
                }
            }
        }
        .onReceive(ticker) { now = $0 }
        .onAppear { now = Date() }
    }
}

// MARK: - The recap

/// What the first tab becomes once the last band has played: your weekend, the crowd's
/// weekend, and the way back to the bill.
struct RecapView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(Ratings.self) private var ratings
    @Environment(Favorites.self) private var favorites
    @Environment(CommunityRatings.self) private var community

    /// How many ratings a set needs before it can be called one of the festival's best.
    private static let crowdMinimum = 3

    /// Read once per visit. Nothing here is going to change while it's on screen — the
    /// festival is over, which is the entire premise of the screen.
    @State private var now = Date()
    /// Rendered up front so the share sheet has something the moment it's asked for.
    @State private var share: RecapShare?

    private var recap: Recap {
        Recap(data: store.data, ratings: ratings, favorites: favorites, now: now)
    }

    private var crowdTop: [CrowdTopSet] {
        community.topSets(in: store.data, minimum: Self.crowdMinimum)
    }

    /// Built as a `String` rather than interpolated at the call site so it reaches the
    /// title and the share sheet as text. An `Int` interpolated into something that
    /// resolves to a `LocalizedStringKey` gets formatted for the reader, and 2026 comes
    /// out as "2,026".
    private var title: String {
        "\(store.data.festival.name) \(String(store.data.festival.year))"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                banner

                if recap.isEmpty {
                    nothingOfYourOwn
                } else {
                    yourWeekend
                    topSets
                    stillToRate
                    superlatives
                }

                crowdSection
                archive
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let share {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: share, preview: SharePreview("My " + title)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .tint(Theme.accent)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: RecapRoute.schedule) {
                    Image(systemName: "calendar")
                }
                .tint(Theme.accent)
                .accessibilityLabel("Full schedule")
            }
        }
        .onAppear {
            now = Date()
            renderShare()
        }
        // Rating something from here changes what the card says, so it gets redrawn rather
        // than sharing a picture of a recap that's one set out of date.
        .onChange(of: ratings.byPerformanceID) { _, _ in renderShare() }
        .task { await community.refresh() }
        .refreshable { await community.refresh(force: true) }
    }

    // MARK: Header

    private var banner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("THAT'S A WRAP")
                .appFont(11, weight: .heavy)
                .foregroundStyle(Theme.accent)
            Text(title)
                .appFont(30, weight: .heavy, design: .rounded)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .appFont(12)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(colors: [Theme.accent.opacity(0.28), Theme.surface],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .padding(.top, 12)
    }

    /// The weekend in one line: when it was, and how much of it there was.
    private var subtitle: String {
        let festival = store.data.festival
        let sets = store.data.allPerformances.count
        var parts: [String] = []
        if let range = Format.dateRange(festival.startDate, festival.endDate) {
            parts.append(range)
        }
        parts.append("\(sets) sets across \(store.data.days.count) days")
        parts.append(festival.venue)
        return parts.joined(separator: " · ")
    }

    // MARK: Your weekend

    private var yourWeekend: some View {
        HStack(spacing: 10) {
            StatTile(value: "\(recap.attendedCount)",
                     label: recap.attendedCount == 1 ? "set seen" : "sets seen")
            StatTile(value: recap.watchedHours.formatted(.number.precision(.fractionLength(0...1))),
                     label: "hours of music")
            if let average = recap.average {
                StatTile(value: Format.rating(average), label: "your average", tint: Theme.accent)
            } else {
                StatTile(value: "\(recap.ratedCount)", label: "sets rated")
            }
        }
        .padding(.top, 4)
    }

    private var topSets: some View {
        Group {
            if !recap.rated.isEmpty {
                sectionHeading("YOUR BEST SETS")

                ForEach(Array(recap.best(limit: 5).enumerated()), id: \.element.id) { index, entry in
                    NavigationLink(value: entry.performance) {
                        RankedSetRow(rank: index + 1,
                                     performance: entry.performance,
                                     detail: .yours(entry.rating.stars),
                                     crowd: community.rating(for: entry.performance))
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink(value: RatingsRoute.recap) {
                    Label(recap.ratedCount > 5
                          ? "All \(recap.ratedCount) sets you rated"
                          : "Your ratings, with your notes",
                          systemImage: "chevron.right")
                        .labelStyle(TrailingIconLabelStyle())
                        .appFont(13, weight: .semibold)
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The one number on this screen that is a to-do rather than a souvenir.
    private var stillToRate: some View {
        Group {
            if !recap.unrated.isEmpty {
                NavigationLink(value: RatingsRoute.recap) {
                    HStack(spacing: 10) {
                        Image(systemName: "star.leadinghalf.filled")
                            .appFont(18)
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(recap.unrated.count) starred "
                               + "\(recap.unrated.count == 1 ? "set" : "sets") you never rated")
                                .appFont(13, weight: .semibold)
                                .foregroundStyle(.white)
                            Text("Rate them and they join everyone else's averages.")
                                .appFont(11)
                                .foregroundStyle(Theme.tertiaryText)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .appFont(12, weight: .semibold)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    .padding(14)
                    .background(Theme.surface,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }

    /// The numbers that aren't a scoreboard: which day you gave the most to, and where you
    /// spent it.
    private var superlatives: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let busiest = recap.busiestDay {
                factRow(symbol: "calendar",
                        title: "\(busiest.day.weekday) was your biggest day",
                        detail: "\(busiest.count) \(busiest.count == 1 ? "set" : "sets") "
                              + "on \(Format.dayLabel(busiest.day))")
            }

            if !recap.stages.isEmpty {
                factRow(symbol: "music.mic",
                        title: recap.stages.count == 1
                             ? "You spent the weekend at one stage"
                             : "You were at \(recap.stages.count) stages",
                        detail: recap.stages
                            .map { "\($0.stage.displayName) \($0.count)" }
                            .joined(separator: " · "))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 4)
    }

    private func factRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .appFont(14)
                .foregroundStyle(Theme.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(13, weight: .semibold)
                    .foregroundStyle(.white)
                Text(detail)
                    .appFont(11)
                    .foregroundStyle(Theme.tertiaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// For someone who starred nothing and rated nothing, this screen is about the
    /// festival rather than about them — but the way in is still one tap from here.
    private var nothingOfYourOwn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You didn't rate anything this year")
                .appFont(15, weight: .semibold)
                .foregroundStyle(.white)
            Text("If you were there, the sets are all still in the schedule — open one and "
               + "give it your stars. They'll show up here, and in everyone's averages.")
                .appFont(12)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink(value: RecapRoute.schedule) {
                Label("Open the schedule", systemImage: "chevron.right")
                    .labelStyle(TrailingIconLabelStyle())
                    .appFont(13, weight: .semibold)
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 4)
    }

    // MARK: Everyone else

    /// The festival's best sets according to the field. Always on screen, because a
    /// section that comes and goes depending on how the sweep went is a section nobody
    /// can rely on — when there's nothing to rank it says why instead.
    private var crowdSection: some View {
        @Bindable var bindable = community

        return VStack(alignment: .leading, spacing: 10) {
            sectionHeading("THE FESTIVAL'S BEST")

            if crowdTop.isEmpty {
                Text(community.emptyRankingMessage(minimum: Self.crowdMinimum))
                    .appFont(12)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Every set with at least \(Self.crowdMinimum) ratings, best first.")
                    .appFont(11)
                    .foregroundStyle(Theme.tertiaryText)

                ForEach(Array(crowdTop.enumerated()), id: \.element.id) { index, entry in
                    NavigationLink(value: entry.performance) {
                        RankedSetRow(rank: index + 1,
                                     performance: entry.performance,
                                     detail: .crowd(entry.rating),
                                     crowd: nil)
                    }
                    .buttonStyle(.plain)
                }

                if let fetchedAt = community.fetchedAt {
                    Text("As of " + fetchedAt.formatted(date: .abbreviated, time: .shortened)
                       + ". Pull down to check for more.")
                        .appFont(11)
                        .foregroundStyle(Theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Reading the averages never depended on sharing yours, so this isn't why the
            // list above is empty — it's why you're not in it. The full explanation of
            // what gets uploaded stays on My Ratings, which is where you turn it off.
            if !community.isSharing {
                Toggle("Put my ratings in these averages", isOn: $bindable.isSharing)
                    .appFont(13, weight: .semibold)
                    .foregroundStyle(.white)
                    .tint(Theme.accent)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .onChange(of: community.isSharing) { _, _ in
            community.applySharingChange(localRatings: ratings.byPerformanceID)
            Task {
                await community.push()
                await community.refresh(force: true)
            }
        }
    }

    // MARK: The bill

    private var archive: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeading("THE BILL")

            VStack(spacing: 0) {
                NavigationLink(value: PastLineupRoute.year(store.data.festival.year)) {
                    linkRow(symbol: "list.bullet.rectangle.portrait",
                            title: "\(String(store.data.festival.year)) in the archive",
                            detail: "Every act that played, day by day")
                }
                .buttonStyle(.plain)

                Divider().overlay(Theme.hairline).padding(.leading, 46)

                NavigationLink(value: RecapRoute.schedule) {
                    linkRow(symbol: "calendar",
                            title: "The full schedule",
                            detail: "Set times, artists and previews")
                }
                .buttonStyle(.plain)

                Divider().overlay(Theme.hairline).padding(.leading, 46)

                NavigationLink(value: PastLineupRoute.index) {
                    linkRow(symbol: "clock.arrow.circlepath",
                            title: "Every Hinterland",
                            detail: "\(store.pastLineups.years.count) festivals in the archive")
                }
                .buttonStyle(.plain)
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.top, 4)
    }

    private func linkRow(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .appFont(15)
                .foregroundStyle(Theme.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(14, weight: .semibold)
                    .foregroundStyle(.white)
                Text(detail)
                    .appFont(11)
                    .foregroundStyle(Theme.tertiaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .appFont(12, weight: .semibold)
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    private func sectionHeading(_ text: String) -> some View {
        Text(text)
            .appFont(12, weight: .bold)
            .foregroundStyle(Theme.tertiaryText)
            .padding(.top, 12)
            .padding(.horizontal, 4)
    }

    // MARK: Sharing

    /// Draws the share card off-screen and keeps it until something it says changes.
    ///
    /// Done here rather than inside `ShareLink` because `ImageRenderer` is a render pass,
    /// and one of those on every body evaluation is a scroll that stutters for a picture
    /// nobody has asked for yet.
    @MainActor
    private func renderShare() {
        let snapshot = recap
        guard !snapshot.rated.isEmpty else {
            share = nil
            return
        }
        // Nothing in the card reads the environment, so it renders correctly outside the
        // view hierarchy — which is where `ImageRenderer` puts it.
        let renderer = ImageRenderer(content: RecapShareCard(recap: snapshot))
        renderer.scale = 3
        share = RecapShare(text: snapshot.shareText, image: renderer.uiImage?.pngData())
    }
}

// MARK: - Pieces

/// One big number and what it counts.
private struct StatTile: View {
    let value: String
    let label: String
    var tint: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .appFont(24, weight: .heavy, design: .rounded)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .appFont(10, weight: .semibold)
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A set in a ranked list: its position, who played, and the one number the list is
/// ranked on.
private struct RankedSetRow: View {
    enum Detail {
        case yours(Int)
        case crowd(CrowdRating)
    }

    let rank: Int
    let performance: Performance
    let detail: Detail
    /// Shown alongside `detail` when it's the other number and there is one — what
    /// everyone made of a set you rated. Nil on a list that is already the crowd's.
    let crowd: CrowdRating?

    @Environment(ScheduleStore.self) private var store

    private var artist: Artist? { store.data.artist(id: performance.artistId) }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .appFont(15, weight: .heavy, design: .rounded)
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 18)

            ArtistImage(artist: artist, size: 44)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Theme.hairline)
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(performance.artist)
                    .appFont(15, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    switch detail {
                    case .yours(let stars):
                        RatingBadge(stars: stars, compact: true)
                    case .crowd(let rating):
                        CrowdBadge(rating: rating, compact: true)
                        Text("\(rating.count) \(rating.count == 1 ? "rating" : "ratings")")
                            .appFont(10)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    if let crowd {
                        CrowdBadge(rating: crowd, compact: true)
                    }
                    StageBadge(stage: Stage(name: performance.stage), compact: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A label with its icon on the right, for "go and look at this" links that aren't rows.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.appFont(11, weight: .semibold)
        }
    }
}
