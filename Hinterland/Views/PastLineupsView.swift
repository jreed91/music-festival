import SwiftUI

/// Routes into the archive, pushed from the Schedule tab's own navigation stack.
enum PastLineupRoute: Hashable {
    case index
    /// One year's bill, by `PastLineupYear.year`.
    case year(Int)
}

/// Every Hinterland before this one, newest first. Bundled like the rest of the app, so it
/// reads in the valley — which is where the argument about who played 2017 tends to start.
struct PastLineupsView: View {
    @Environment(ScheduleStore.self) private var store

    private var archive: PastLineupData { store.pastLineups }

    var body: some View {
        List {
            Section {
                ForEach(archive.years) { year in
                    NavigationLink(value: PastLineupRoute.year(year.year)) {
                        YearRow(year: year)
                    }
                }
            } footer: {
                Text(footer).appFont(11)
            }
            .listRowBackground(Theme.surface)

            if let source = archive.source, let url = URL(string: source) {
                Section {
                    Link(destination: url) {
                        Label("Past lineups on hinterlandiowa.com", systemImage: "arrow.up.right")
                            .appFont(13)
                            .foregroundStyle(Theme.accent)
                    }
                }
                .listRowBackground(Theme.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Past Lineups")
        .navigationBarTitleDisplayMode(.inline)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(year.year))
                    .appFont(17, weight: .bold)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Text("\(year.acts.count) acts")
                    .appFont(11)
                    .foregroundStyle(Theme.tertiaryText)
            }
            // The headliners are what anyone is scanning this list for; the rest of the
            // bill is one tap away.
            Text(year.headliners.joined(separator: " · "))
                .appFont(12)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - One year

/// A year's whole bill, day by day, headliner first.
struct PastYearView: View {
    let year: PastLineupYear

    @Environment(ScheduleStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(year.days) { day in
                    dayCard(day)
                }
                footer.padding(.top, 6)
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle(String(year.year))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dayCard(_ day: PastLineupDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            actRow(PastAct(name: day.headliner), isHeadliner: true)
            if !day.support.isEmpty {
                Divider().overlay(Theme.hairline)
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(day.support) { support in
                        actRow(support, isHeadliner: false)
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// One name on the bill, with the side stage the archive gives it. Nothing here taps
    /// through: it's a list of names, and most of them have no page anywhere in the app.
    private func actRow(_ act: PastAct, isHeadliner: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(act.name)
                .appFont(isHeadliner ? 19 : 15, weight: isHeadliner ? .bold : .regular)
                .foregroundStyle(.white.opacity(isHeadliner ? 1 : 0.86))
                .fixedSize(horizontal: false, vertical: true)
            if let stage = act.stage {
                StageBadge(stage: Stage(name: stage), compact: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The festival lists each day by its headliner and doesn't say which day of "
               + "the weekend it was, so neither does this.")
                .appFont(11)
                .foregroundStyle(Theme.tertiaryText)
            if let source = store.pastLineups.source, let url = URL(string: source) {
                Link(destination: url) {
                    Label("Past lineups on hinterlandiowa.com", systemImage: "arrow.up.right")
                        .appFont(12)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
