import SwiftUI

/// The festival guide, bundled in full so parking routes and gate times are readable
/// when there is no signal — which is exactly when you need them.
struct InfoView: View {
    @Environment(ScheduleStore.self) private var store
    @State private var query = ""

    private var results: [GuideTopic] { store.guide.search(query) }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    Section {
                        if results.isEmpty {
                            Text("Nothing in the guide matches “\(query)”.")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        ForEach(results) { topic in
                            NavigationLink(value: topic.id) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(topic.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text(topic.snippet)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.secondaryText)
                                        .lineLimit(2)
                                }
                            }
                        }
                    } header: {
                        Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                    }
                    .listRowBackground(Theme.surface)
                } else {
                    quickFacts
                    ForEach(store.guide.categories) { category in
                        Section {
                            ForEach(category.topics) { topic in
                                NavigationLink(value: topic.id) {
                                    Text(topic.title)
                                        .font(.system(size: 15))
                                        .foregroundStyle(.white)
                                }
                            }
                        } header: {
                            Label(category.name, systemImage: category.symbol)
                                .foregroundStyle(Theme.accent)
                        }
                        .listRowBackground(Theme.surface)
                    }
                    refreshFooter
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search the guide")
            .navigationDestination(for: String.self) { id in
                if let topic = store.guide.allTopics.first(where: { $0.id == id }) {
                    GuideTopicView(topic: topic)
                }
            }
        }
    }

    private var quickFacts: some View {
        Section {
            LabeledContent("Dates") {
                Text("Jul 30 – Aug 2, 2026").foregroundStyle(Theme.secondaryText)
            }
            LabeledContent("Venue") {
                Text(store.data.festival.venue)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Where") {
                Text(store.data.festival.city).foregroundStyle(Theme.secondaryText)
            }
            if let maps = URL(string:
                "http://maps.apple.com/?q=\(store.data.festival.latitude),"
                + "\(store.data.festival.longitude)") {
                Link(destination: maps) {
                    Label("Open in Maps", systemImage: "map").foregroundStyle(Theme.accent)
                }
            }
        } header: {
            Label("Hinterland \(String(store.data.festival.year))", systemImage: "sparkles")
                .foregroundStyle(Theme.accent)
        }
        .listRowBackground(Theme.surface)
    }

    private var refreshFooter: some View {
        Section {
            Button {
                Task { await store.refresh() }
            } label: {
                HStack {
                    Label("Check for schedule updates", systemImage: "arrow.clockwise")
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    if store.isRefreshing { ProgressView() }
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let error = store.refreshError {
                    Text(error).foregroundStyle(Theme.warning)
                }
                Text("Set times last updated \(store.data.generatedAt.formatted(date: .abbreviated, time: .shortened)). "
                   + "Everything here works offline.")
            }
            .font(.system(size: 11))
        }
        .listRowBackground(Theme.surface)
    }
}

/// A single guide entry. The body is plain text from the site, so it renders as-is with
/// generous line spacing rather than being re-parsed into rich text.
struct GuideTopicView: View {
    let topic: GuideTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(topic.body)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)

                if let links = topic.links, !links.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Links")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.tertiaryText)
                        ForEach(links, id: \.self) { link in
                            if let url = URL(string: link) {
                                Link(destination: url) {
                                    Text(url.host().map { "\($0)\(url.path())" } ?? link)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.accent)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
