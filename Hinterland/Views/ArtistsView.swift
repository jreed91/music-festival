import SwiftUI

/// Every artist on the bill, searchable — for when you know the name but not the day.
struct ArtistsView: View {
    @Environment(ScheduleStore.self) private var store
    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    private var artists: [Artist] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = store.data.artists.sorted { $0.name.lowercased() < $1.name.lowercased() }
        return needle.isEmpty ? all : all.filter { $0.name.lowercased().contains(needle) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(artists) { artist in
                        NavigationLink(value: artist.id) {
                            ArtistCard(artist: artist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Artists")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search artists")
            .navigationDestination(for: String.self) { id in
                ArtistDetailView(artistID: id)
            }
            .overlay {
                if artists.isEmpty {
                    EmptyStateView(symbol: "magnifyingglass",
                                   title: "No artists found",
                                   message: "Nothing on the bill matches “\(query)”.")
                }
            }
        }
    }
}

private struct ArtistCard: View {
    let artist: Artist

    @Environment(ScheduleStore.self) private var store

    private var firstSet: Performance? {
        store.data.performances(forArtist: artist.id).first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArtistImage(artist: artist)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipped()

            VStack(alignment: .leading, spacing: 5) {
                Text(artist.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let firstSet, let day = store.data.day(containing: firstSet) {
                    Text("\(day.shortWeekday) · \(Format.time(firstSet.start))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                    StageBadge(stage: Stage(name: firstSet.stage), compact: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
