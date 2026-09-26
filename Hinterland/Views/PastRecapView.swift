import SwiftUI

/// A year you were at, after `schedule.json` has moved on: the recap and your ratings as
/// they stood, rebuilt from its `FestivalMemory` rather than the live schedule.
///
/// Read-only on purpose. The sets aren't in the schedule any more, so there's no artist
/// page to open and nothing left to rate — this is the souvenir, not the scoreboard.
struct PastRecapView: View {
    let memory: FestivalMemory

    private var recap: Recap { memory.recap }

    /// `String(year)`, not interpolation, or 2026 reaches the screen as "2,026".
    private var title: String {
        "\(memory.schedule.festival.name) \(String(memory.year))"
    }

    /// Starred and over but never rated — you were there, it just didn't get stars.
    private var alsoSeen: [Performance] {
        let rated = Set(recap.rated.map(\.id))
        return recap.attended.filter { !rated.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                banner

                HStack(spacing: 10) {
                    StatTile(value: "\(recap.attendedCount)",
                             label: recap.attendedCount == 1 ? "set seen" : "sets seen")
                    StatTile(value: recap.watchedHours
                                .formatted(.number.precision(.fractionLength(0...1))),
                             label: "hours of music")
                    if let average = recap.average {
                        StatTile(value: Format.rating(average), label: "your average",
                                 tint: Theme.accent)
                    } else {
                        StatTile(value: "\(recap.ratedCount)", label: "sets rated")
                    }
                }
                .padding(.top, 4)

                if !recap.rated.isEmpty {
                    sectionHeading("YOUR SETS")
                    ForEach(Array(recap.rated.enumerated()), id: \.element.id) { index, entry in
                        setRow(entry.performance, rank: index + 1, stars: entry.rating.stars,
                               note: entry.rating.note)
                    }
                }

                if !alsoSeen.isEmpty {
                    sectionHeading("STARRED, NEVER RATED")
                    ForEach(alsoSeen) { performance in
                        setRow(performance, rank: nil, stars: nil, note: "")
                    }
                }

                superlatives
                crowdSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Your " + String(memory.year))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !recap.rated.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: recap.shareText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .tint(Theme.accent)
                    .accessibilityLabel("Share this recap")
                }
            }
        }
    }

    // MARK: Pieces

    private var banner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR WEEKEND")
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
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(colors: [Theme.accent.opacity(0.28), Theme.surface],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .padding(.top, 12)
    }

    private var subtitle: String {
        let festival = memory.schedule.festival
        var parts: [String] = []
        if let range = Format.dateRange(festival.startDate, festival.endDate) {
            parts.append(range)
        }
        parts.append("\(memory.setCount) sets across \(memory.dayCount) days")
        parts.append(festival.venue)
        return parts.joined(separator: " · ")
    }

    /// One set: who, where, when, your stars and everyone's, and your note. Nothing taps
    /// through — the artist page belongs to a schedule that has since been replaced.
    private func setRow(_ performance: Performance, rank: Int?, stars: Int?,
                        note: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let rank {
                    Text("\(rank)")
                        .appFont(15, weight: .heavy, design: .rounded)
                        .foregroundStyle(Theme.tertiaryText)
                        .frame(width: 18)
                }
                ArtistImage(artist: memory.schedule.artist(id: performance.artistId), size: 44)
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
                        if let stars {
                            RatingBadge(stars: stars, compact: true)
                        }
                        if let crowd = memory.crowd[performance.id] {
                            CrowdBadge(rating: crowd, compact: true)
                        }
                        StageBadge(stage: Stage(name: performance.stage), compact: true)
                    }
                    Text(when(performance))
                        .appFont(10)
                        .foregroundStyle(Theme.tertiaryText)
                }
                Spacer(minLength: 0)
            }
            // One stop per set, the same shape as the rows on this year's recap. The
            // note stays its own stop underneath.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenSet(performance, rank: rank, stars: stars))
            if !note.isEmpty {
                Text(note)
                    .appFont(12)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func spokenSet(_ performance: Performance, rank: Int?, stars: Int?) -> String {
        var parts: [String] = []
        if let rank { parts.append("Number \(rank)") }
        parts.append(performance.artist)
        if let stars { parts.append(RatingBadge.spokenLabel(stars: stars)) }
        if let crowd = memory.crowd[performance.id] {
            parts.append(CrowdBadge.spokenLabel(for: crowd))
        }
        parts.append(Stage(name: performance.stage).displayName)
        if let day = memory.schedule.day(containing: performance) {
            parts.append("\(day.weekday), \(Format.dayLabel(day))")
        }
        parts.append(Format.spokenRange(performance.start, performance.end))
        return parts.joined(separator: ", ")
    }

    private func when(_ performance: Performance) -> String {
        let day = memory.schedule.day(containing: performance)
        let prefix = day.map { "\($0.shortWeekday) \(Format.dayLabel($0)) · " } ?? ""
        return prefix + Format.range(performance.start, performance.end)
    }

    private var superlatives: some View {
        Group {
            if recap.busiestDay != nil || !recap.stages.isEmpty {
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
                .background(Theme.surface,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 14)
            }
        }
    }

    private func factRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .appFont(14)
                .foregroundStyle(Theme.accent)
                .frame(width: 20)
                .accessibilityHidden(true)
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
        .accessibilityElement(children: .combine)
    }

    /// The festival's best as the crowd had it when this year was put away. Left out
    /// entirely when nothing was ever downloaded: there's no "pull to refresh" for a year
    /// whose ratings nobody is fetching any more.
    private var crowdSection: some View {
        Group {
            if !memory.crowdTop.isEmpty {
                sectionHeading("THE FESTIVAL'S BEST")
                ForEach(Array(memory.crowdTop.enumerated()), id: \.element.id) { index, entry in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .appFont(15, weight: .heavy, design: .rounded)
                            .foregroundStyle(Theme.tertiaryText)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.performance.artist)
                                .appFont(15, weight: .semibold)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                CrowdBadge(rating: entry.rating, compact: true)
                                Text("\(entry.rating.count) "
                                   + "\(entry.rating.count == 1 ? "rating" : "ratings")")
                                    .appFont(10)
                                    .foregroundStyle(Theme.tertiaryText)
                                StageBadge(stage: Stage(name: entry.performance.stage),
                                           compact: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Theme.surface,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Number \(index + 1), \(entry.performance.artist), "
                                      + CrowdBadge.spokenLabel(for: entry.rating) + ", "
                                      + Stage(name: entry.performance.stage).displayName)
                }
                if let fetchedAt = memory.crowdFetchedAt {
                    Text("Everyone's ratings as of "
                       + fetchedAt.formatted(date: .abbreviated, time: .omitted) + ".")
                        .appFont(11)
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private func sectionHeading(_ text: String) -> some View {
        Text(text)
            .appFont(12, weight: .bold)
            .foregroundStyle(Theme.tertiaryText)
            .padding(.top, 12)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}
