import SwiftUI

/// Routes into the archive, pushed from the Schedule tab's own navigation stack.
enum PastLineupRoute: Hashable {
    case index
    /// One year's bill, by `PastLineupYear.year`.
    case year(Int)
    /// Your recap and ratings for a year, by `FestivalMemory.year`.
    case yours(Int)
}

/// Every Hinterland before this one, newest first. Bundled like the rest of the app, so it
/// reads in the valley — which is where the argument about who played 2017 tends to start.
struct PastLineupsView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(FestivalMemories.self) private var memories

    private var archive: PastLineupData { store.pastLineups }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("THE ARCHIVE")
                        .appFont(12, weight: .bold)
                        .tracking(2.4)
                        .foregroundStyle(Theme.inkFaint)
                    Text("PAST LINEUPS")
                        .marqueeFont(88)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.ink).frame(height: 2)
                }

                ForEach(yearsOnlyYouHave, id: \.year) { memory in
                    NavigationLink(value: PastLineupRoute.yours(memory.year)) {
                        MemoryOnlyRow(memory: memory)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(archive.years) { year in
                    NavigationLink(value: PastLineupRoute.year(year.year)) {
                        YearRow(year: year, memory: memories.memory(for: year.year))
                    }
                    .buttonStyle(.plain)
                }

                Text(footer)
                    .appFont(13)
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)

                if let source = archive.source, let url = URL(string: source) {
                    Link(destination: url) {
                        Label("Past lineups on hinterlandiowa.com", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(GlowButtonStyle(.quiet))
                    .padding(.top, 16)
                }

                Horizon()
                    .padding(.top, 48)
                    .padding(.horizontal, -22)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
        }
        .background(Theme.night)
        .navigationTitle("Past Lineups")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Years you have a recap for that this build's archive doesn't list yet.
    ///
    /// The archive ships in the binary while the schedule arrives live, so a phone still on
    /// this build when the year after next's schedule lands has a recap for a year the
    /// archive never heard of. Without a row of its own it would be saved and unreachable.
    /// The current year is left out: while it's on, it isn't past, and once it's over the
    /// recap is the first tab.
    private var yearsOnlyYouHave: [FestivalMemory] {
        memories.byYear.values
            .filter { archive.year($0.year) == nil && $0.year != store.data.festival.year }
            .sorted { $0.year > $1.year }
    }

    /// The run of years, and the gap in it. 2020 is missing from the archive because there
    /// was no 2020 festival, and a list that jumps from 2019 to 2021 saying nothing about
    /// it reads like a bug.
    private var footer: String {
        let years = archive.years.map(\.year)
        guard let first = years.min(), let last = years.max() else { return "" }
        // String(first), not "\(first)": an Int interpolated into a string that reaches a
        // Text gets formatted for the reader's locale, and 2015 comes out as "2,015".
        let run = "\(archive.actCount) acts across \(archive.years.count) festivals, "
                + "\(String(first)) to \(String(last))."
        let missing = archive.missingYears
        guard !missing.isEmpty else { return run }
        return run + " No festival in \(missing.map { String($0) }.formatted(.list(type: .and)))."
    }
}

private struct YearRow: View {
    let year: PastLineupYear
    /// Set when you rated or starred anything that year, so the list shows which ones
    /// you were at.
    let memory: FestivalMemory?

    var body: some View {
        ArchiveRow {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(year.year))
                    .marqueeFont(56)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                Text("\(year.acts.count) acts".uppercased())
                    .appFont(12, weight: .bold)
                    .tracking(1.6)
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize()
            }
            // The headliners are what anyone is scanning this list for; the rest of the
            // bill is one tap away.
            Text(year.headliners.joined(separator: " · "))
                .appFont(15)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let memory {
                YoursLine(text: yourLine(memory))
            }
        }
    }

    private func yourLine(_ memory: FestivalMemory) -> String {
        let recap = memory.recap
        guard let average = recap.average else {
            return "You were there · \(recap.attendedCount) "
                 + "\(recap.attendedCount == 1 ? "set" : "sets")"
        }
        return "You were there · \(recap.ratedCount) rated · \(Format.rating(average)) average"
    }
}

/// A year you were at that the bundled archive doesn't have yet: your recap, and a line
/// saying the bill itself comes with an update.
private struct MemoryOnlyRow: View {
    let memory: FestivalMemory

    var body: some View {
        ArchiveRow {
            Text(String(memory.year))
                .marqueeFont(56)
                .foregroundStyle(Theme.ink)
            Text("The full bill arrives with the next app update.")
                .appFont(15)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            YoursLine(text: yourLine)
        }
    }

    private var yourLine: String {
        let count = memory.recap.attendedCount
        return "Your recap · \(count) \(count == 1 ? "set" : "sets")"
    }
}

/// A year in the archive list: its lines, a chevron, and the hairline under it.
private struct ArchiveRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .appFont(12, weight: .semibold)
                .foregroundStyle(Theme.inkFaint)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .contentShape(Rectangle())
    }
}

/// "You were there": the one `sodium` line in the archive, because it's yours.
private struct YoursLine: View {
    let text: String

    var body: some View {
        Label(text.uppercased(), systemImage: "star.fill")
            .appFont(12, weight: .bold)
            .tracking(1.4)
            .foregroundStyle(Theme.sodium)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - One year

/// A year's whole bill, day by day, headliner first, set like a festival poster.
struct PastYearView: View {
    let year: PastLineupYear

    @Environment(ScheduleStore.self) private var store
    @Environment(FestivalMemories.self) private var memories

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(store.data.festival.name) · the bill".uppercased())
                        .appFont(12, weight: .bold)
                        .tracking(2.4)
                        .foregroundStyle(Theme.inkFaint)
                    Text(String(year.year))
                        .marqueeFont(96)
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                }

                if let memory = memories.memory(for: year.year) {
                    yourYear(memory)
                        .padding(.top, 16)
                }

                ForEach(year.days) { day in
                    dayBlock(day)
                }

                footer
                    .padding(.top, 24)

                Horizon()
                    .padding(.top, 48)
                    .padding(.horizontal, -22)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
        }
        .background(Theme.night)
        .navigationTitle(String(year.year))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Your recap for the year, above the bill: the thing you're likelier to have come
    /// looking for than who played third on the Friday.
    private func yourYear(_ memory: FestivalMemory) -> some View {
        let recap = memory.recap
        var detail = "\(recap.attendedCount) \(recap.attendedCount == 1 ? "set" : "sets") seen"
        if let average = recap.average {
            detail += " · \(recap.ratedCount) rated · \(Format.rating(average)) average"
        }
        return NavigationLink(value: PastLineupRoute.yours(memory.year)) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("YOUR \(String(memory.year))")
                        .appFont(13, weight: .bold)
                        .tracking(2.4)
                        .foregroundStyle(Theme.sodium)
                    Text("Your recap and ratings")
                        .appFont(17, weight: .semibold)
                        .foregroundStyle(Theme.ink)
                    Text(detail)
                        .appFont(13)
                        .foregroundStyle(Theme.inkFaint)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .appFont(12, weight: .semibold)
                    .foregroundStyle(Theme.inkFaint)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(Theme.nightRaised)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One night of the bill: the headliner in `title` over the 2pt rule, then everyone
    /// else in `list-name`, the way the poster stacks them.
    private func dayBlock(_ day: PastLineupDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            actRow(PastAct(name: day.headliner), isHeadliner: true)
                .padding(.top, 28)
                .padding(.bottom, 6)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.ink).frame(height: 2)
                }
            ForEach(day.support) { support in
                actRow(support, isHeadliner: false)
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
            }
        }
    }

    /// One name on the bill, with the side stage the archive gives it. Nothing here taps
    /// through: it's a list of names, and most of them have no page anywhere in the app.
    private func actRow(_ act: PastAct, isHeadliner: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // Headliners in Six Caps, like the top of a poster; everyone under them in the
            // list's heavy Barlow, which is the size a name can still be read at.
            Group {
                if isHeadliner {
                    Text(act.name.uppercased())
                        .marqueeFont(56)
                        .foregroundStyle(Theme.ink)
                } else {
                    Text(act.name.uppercased())
                        .listNameFont()
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let stage = act.stage {
                StageBadge(stage: Stage(name: stage), compact: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isHeadliner ? [.isHeader] : [])
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("The festival lists each day by its headliner and doesn't say which day of "
               + "the weekend it was, so neither does this.")
                .appFont(13)
                .foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            if let source = store.pastLineups.source, let url = URL(string: source) {
                Link(destination: url) {
                    Label("Past lineups on hinterlandiowa.com", systemImage: "arrow.up.right")
                }
                .buttonStyle(GlowButtonStyle(.quiet))
            }
        }
    }
}
