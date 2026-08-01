import SwiftUI

/// Pushed from My Lineup, kept out of `Performance`'s destination so the two don't collide.
enum RatingsRoute: Hashable {
    case recap
}

/// Every set you rated, best first, plus the ones you starred and never got round to
/// rating. The festival's own scoreboard for your weekend.
struct RatingsView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(Ratings.self) private var ratings
    @Environment(Favorites.self) private var favorites

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
                           + "stars. They show up here, ranked, with anything you wrote down.")
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
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
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

/// A line about a set you rated, written after the fact and kept on the phone.
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
                    Text("Kept on your phone with the rating. Nothing is uploaded.")
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
