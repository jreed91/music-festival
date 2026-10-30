import SwiftUI

/// Pushed from My Lineup, kept out of `Performance`'s destination so the two don't collide.
enum RatingsRoute: Hashable {
    case recap
}

/// Every set you rated, best first, with what everyone else made of the same set, plus
/// the ones you starred and never got round to rating. The scoreboard for your weekend.
struct RatingsView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(Ratings.self) private var ratings
    @Environment(Favorites.self) private var favorites
    @Environment(CommunityRatings.self) private var community

    /// Read once per visit — nothing on this screen changes mid-second, and "has it
    /// finished yet" only needs to be right when the screen opens.
    @State private var now = Date()

    private var ranked: [(performance: Performance, rating: SetRating)] {
        ratings.ranked(in: store.data)
    }

    /// Starred sets that are over and unrated. Deliberately only the starred ones: every
    /// set that has finished is most of the festival, and you weren't at most of it.
    private var awaiting: [Performance] {
        ratings.unrated(among: favorites.performances(in: store.data), at: now)
    }

    var body: some View {
        Group {
            if ranked.isEmpty && awaiting.isEmpty {
                DeadAirScreen(
                    title: "Nothing rated yet",
                    message: "Once a set is under way, open the artist and rate it from one "
                           + "to five. Your ratings show up here, ranked, next to what the "
                           + "valley thought of the same set.")
            } else {
                list
            }
        }
        .navigationTitle("My Ratings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !ranked.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: recapText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share my ratings")
                }
            }
        }
        .onAppear { now = Date() }
        // Throttled inside the service, so opening this screen repeatedly doesn't turn
        // into repeated sweeps of the database.
        .task { await community.refresh() }
        .onChange(of: community.isSharing) { _, _ in
            community.applySharingChange(localRatings: ratings.byPerformanceID)
            Task { await community.push() }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(store.data.festival.name) \(String(store.data.festival.year))".uppercased())
                        .appFont(12, weight: .bold)
                        .tracking(2.4)
                        .foregroundStyle(Theme.inkFaint)
                    Text("YOUR RATINGS")
                        .marqueeFont(88)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }

                if !ranked.isEmpty {
                    summary
                }

                ForEach(ranked, id: \.performance.id) { entry in
                    VStack(alignment: .leading, spacing: 0) {
                        NavigationLink(value: entry.performance) {
                            PerformanceRow(performance: entry.performance, showsFullTime: true)
                        }
                        .buttonStyle(.plain)

                        // The row itself shows your rating, so what's worth adding here is
                        // the other number: whether the rest of the valley agreed with you.
                        if let crowd = community.rating(for: entry.performance) {
                            HStack(spacing: 8) {
                                CrowdBadge(rating: crowd, compact: true)
                                Text("from \(crowd.count) "
                                   + "\(crowd.count == 1 ? "person" : "people") in the valley")
                                    .appFont(13)
                                    .foregroundStyle(Theme.inkFaint)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, 10)
                            // The badge already says how many people; the text beside it
                            // would only say it again.
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(CrowdBadge.spokenLabel(for: crowd))
                        }

                        if !entry.rating.note.isEmpty {
                            Text(entry.rating.note)
                                .appFont(15)
                                .foregroundStyle(Theme.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 8)
                        }
                    }
                    .padding(.bottom, 12)
                }

                if !awaiting.isEmpty {
                    SectionHeading(title: "Starred, not rated yet",
                                   detail: "\(awaiting.count) \(awaiting.count == 1 ? "set" : "sets")")

                    ForEach(awaiting) { performance in
                        NavigationLink(value: performance) {
                            PerformanceRow(performance: performance, showsFullTime: true)
                        }
                        .buttonStyle(.plain)
                    }
                }

                sharing

                Horizon()
                    .padding(.top, 48)
                    .padding(.horizontal, -22)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
        }
        .background(Theme.night)
        .refreshable { await community.refresh(force: true) }
    }

    /// What's shared, what state the sharing is in, and the switch that stops it.
    ///
    /// At the bottom of this screen rather than in the Alerts sheet: this is the screen
    /// where the crowd average is on show, so it's where the question of who else can see
    /// yours actually comes up.
    private var sharing: some View {
        @Bindable var bindable = community

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "Sharing")

            Toggle("Share my ratings", isOn: $bindable.isSharing)
                .toggleStyle(GlowToggleStyle())
                .padding(.top, 4)

            Text("Your ratings go into the average the valley sees, anonymously. Notes stay "
               + "on this phone.")
                .appFont(15)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            // Whatever the service last had to say comes first, because "nothing is
            // uploading and the app won't say why" is worse than any of the reasons.
            if let error = community.lastError {
                statusLine(error,
                           symbol: community.isBlocked ? "icloud.slash" : "exclamationmark.circle",
                           tint: Theme.signal)
            } else if community.hasPendingUploads {
                // Not an error: the ratings are on the phone, and this is a festival in a
                // valley with no signal. They go up when there's something to go up over.
                statusLine("Saved on your phone. Uploading when there's signal.",
                           symbol: "arrow.up.circle", tint: Theme.inkMuted)
            } else if let uploadedAt = community.lastUploadedAt {
                statusLine("Your ratings uploaded "
                         + uploadedAt.formatted(date: .omitted, time: .shortened) + ".",
                           symbol: "checkmark.icloud", tint: Theme.inkMuted)
            }

            // Rare enough to be worth saying plainly rather than quietly rounding: the
            // sweep hit its cap, so these averages are counted off a sample.
            if community.crowd?.isPartial == true {
                statusLine("More ratings than this app counts in one pass, so the averages "
                         + "above are from a sample of them.",
                           symbol: "square.stack.3d.up", tint: Theme.inkMuted)
            }

            if let fetchedAt = community.fetchedAt {
                Text("The valley's ratings as of "
                   + fetchedAt.formatted(date: .abbreviated, time: .shortened)
                   + ". Pull down to check for more.")
                    .appFont(13)
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
    }

    private func statusLine(_ message: String, symbol: String, tint: Color) -> some View {
        Label(message, systemImage: symbol)
            .appFont(13, weight: .semibold)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// How many and how good, as the recap's big Six Caps numbers. Your average is yours,
    /// so it's the one that glows.
    private var summary: some View {
        HStack(spacing: 10) {
            StatTile(value: "\(ranked.count)",
                     label: ranked.count == 1 ? "set rated" : "sets rated")
            if let average = ratings.average(in: store.data) {
                StatTile(value: Format.rating(average), label: "your average", tint: Theme.sodium)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryLabel)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private var summaryLabel: String {
        var label = "\(ranked.count) \(ranked.count == 1 ? "set" : "sets") rated"
        if let average = ratings.average(in: store.data) {
            label += ", averaging \(Format.rating(average)) stars"
        }
        return label
    }

    /// What the share sheet hands off. Ratings only — the notes are yours, and a share
    /// sheet is the last place they should turn up by default.
    private var recapText: String {
        var lines = ["My \(store.data.festival.name) \(store.data.festival.year)"]
        if let average = ratings.average(in: store.data) {
            lines.append("\(ranked.count) \(ranked.count == 1 ? "set" : "sets") rated · "
                       + "\(Format.rating(average)) average")
        }
        lines += ranked.map { entry in
            let stars = String(repeating: "★", count: entry.rating.stars)
                + String(repeating: "☆", count: SetRating.scale.upperBound - entry.rating.stars)
            return "\(stars)  \(entry.performance.artist)"
        }
        return lines.joined(separator: "\n")
    }
}

/// A line about a set you rated, written after the fact and kept on the phone — unlike
/// the stars, a note is never uploaded.
struct SetNoteView: View {
    let performance: Performance

    @Environment(Ratings.self) private var ratings
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @FocusState private var isFocused: Bool

    /// Seeded by the caller rather than read in `onAppear`, so the field opens with what
    /// you wrote last time already in it.
    init(performance: Performance, note: String) {
        self.performance = performance
        _text = State(initialValue: note)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("YOUR NOTE ON")
                        .appFont(13, weight: .bold)
                        .tracking(2.4)
                        .foregroundStyle(Theme.inkFaint)
                    Text(performance.artist.uppercased())
                        .marqueeFont(56)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 4)

                    TextField("Your note", text: $text,
                              prompt: Text("Sunset, and they opened with the one everyone came for.")
                                .foregroundStyle(Theme.inkFaint),
                              axis: .vertical)
                        .appFont(17)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(3...8)
                        .focused($isFocused)
                        .padding(12)
                        .background(Theme.night)
                        .overlay(Rectangle()
                            .strokeBorder(isFocused ? Theme.ink : Theme.hairline, lineWidth: 1))
                        .padding(.top, 20)

                    Text("Notes stay on your phone. Only your rating is shared, and only as a "
                       + "number in the valley's average.")
                        .appFont(13)
                        .foregroundStyle(Theme.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)

                    Button {
                        ratings.clear(performance)
                        dismiss()
                    } label: {
                        Text("Remove rating")
                    }
                    .buttonStyle(GlowButtonStyle(.quiet))
                    .padding(.top, 32)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
            }
            .background(Theme.nightSheet)
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.nightSheet, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        ratings.setNote(text, for: performance)
                        dismiss()
                    }
                }
            }
            .onAppear { isFocused = true }
        }
        .tint(Theme.ink)
        .presentationBackground(Theme.nightSheet)
    }
}
