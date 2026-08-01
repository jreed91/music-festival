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
                EmptyStateView(
                    symbol: "star.leadinghalf.filled",
                    title: "Nothing rated yet",
                    message: "Once a set is under way, open the artist and give it one to five "
                           + "stars. They show up here, ranked, next to what everyone else "
                           + "thought of the same set.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
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
                    .tint(Theme.accent)
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
            LazyVStack(alignment: .leading, spacing: 10) {
                if !ranked.isEmpty {
                    summary
                }

                ForEach(ranked, id: \.performance.id) { entry in
                    VStack(alignment: .leading, spacing: 0) {
                        NavigationLink(value: entry.performance) {
                            PerformanceRow(performance: entry.performance)
                        }
                        .buttonStyle(.plain)

                        // The row itself shows your stars, so what's worth adding here is
                        // the other number: whether the rest of the field agreed with you.
                        if let crowd = community.rating(for: entry.performance) {
                            HStack(spacing: 6) {
                                CrowdBadge(rating: crowd, compact: true)
                                Text("everyone · \(crowd.count) "
                                   + "\(crowd.count == 1 ? "rating" : "ratings")")
                                    .appFont(11)
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 8)
                        }

                        if !entry.rating.note.isEmpty {
                            Text(entry.rating.note)
                                .appFont(12)
                                .foregroundStyle(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 14)
                                .padding(.top, 8)
                        }
                    }
                }

                if !awaiting.isEmpty {
                    Text("NOT RATED YET")
                        .appFont(12, weight: .bold)
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.top, 14)

                    ForEach(awaiting) { performance in
                        NavigationLink(value: performance) {
                            PerformanceRow(performance: performance)
                        }
                        .buttonStyle(.plain)
                    }
                }

                sharing
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .refreshable { await community.refresh(force: true) }
    }

    /// What's shared, what state the sharing is in, and the switch that stops it.
    ///
    /// At the bottom of this screen rather than in the Alerts sheet: this is the screen
    /// where the crowd average is on show, so it's where the question of who else can see
    /// yours actually comes up.
    private var sharing: some View {
        @Bindable var bindable = community

        return VStack(alignment: .leading, spacing: 8) {
            Toggle("Share my ratings", isOn: $bindable.isSharing)
                .appFont(13, weight: .semibold)
                .foregroundStyle(.white)
                .tint(Theme.accent)

            Text("Your stars go into the average everyone sees, anonymously. Notes stay on "
               + "this phone.")
                .appFont(11)
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)

            if community.needsAccount {
                statusLine("Sign in to iCloud to add your ratings to the average.",
                           symbol: "icloud.slash", tint: Theme.warning)
            } else if community.hasPendingUploads {
                // Not an error: the ratings are on the phone, and this is a festival in a
                // valley with no signal. They go up when there's something to go up over.
                statusLine("Saved on your phone — uploading when there's signal.",
                           symbol: "arrow.up.circle", tint: Theme.secondaryText)
            } else if let error = community.lastError {
                statusLine(error, symbol: "exclamationmark.circle", tint: Theme.warning)
            }

            // Rare enough to be worth saying plainly rather than quietly rounding: the
            // sweep hit its cap, so these averages are counted off a sample.
            if community.crowd?.isPartial == true {
                statusLine("More ratings than this app counts in one pass — the averages "
                         + "below are from a sample of them.",
                           symbol: "square.stack.3d.up", tint: Theme.secondaryText)
            }

            if let fetchedAt = community.fetchedAt {
                Text("Everyone's ratings as of "
                   + fetchedAt.formatted(date: .abbreviated, time: .shortened)
                   + ". Pull down to check for more.")
                    .appFont(11)
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 18)
    }

    private func statusLine(_ message: String, symbol: String, tint: Color) -> some View {
        Label(message, systemImage: symbol)
            .appFont(11, weight: .medium)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var summary: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(ranked.count)")
                    .appFont(28, weight: .heavy, design: .rounded)
                    .foregroundStyle(.white)
                Text(ranked.count == 1 ? "set rated" : "sets rated")
                    .appFont(11, weight: .semibold)
                    .foregroundStyle(Theme.tertiaryText)
            }

            if let average = ratings.average(in: store.data) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(Format.rating(average))
                            .appFont(28, weight: .heavy, design: .rounded)
                            .foregroundStyle(Theme.accent)
                        Image(systemName: "star.fill")
                            .appFont(14)
                            .foregroundStyle(Theme.accent)
                    }
                    Text("average")
                        .appFont(11, weight: .semibold)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            LinearGradient(colors: [Theme.accent.opacity(0.22), Theme.surface],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .padding(.top, 12)
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
            Form {
                Section {
                    TextField("Sunset, and they opened with the one everyone came for.",
                              text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($isFocused)
                } header: {
                    Text(performance.artist)
                } footer: {
                    Text("Notes stay on your phone — only the stars are shared, and only "
                       + "as a number in everyone's average.")
                }

                Section {
                    Button("Remove rating", role: .destructive) {
                        ratings.clear(performance)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(Theme.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        ratings.setNote(text, for: performance)
                        dismiss()
                    }
                    .tint(Theme.accent)
                }
            }
            .onAppear { isFocused = true }
        }
    }
}
