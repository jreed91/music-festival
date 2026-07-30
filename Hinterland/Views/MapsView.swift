import SwiftUI

/// The festival's maps, straight off the tab bar: the georeferenced grounds map with the
/// blue dot on it, and the illustrated maps the festival publishes. Everything here is
/// bundled with the app, which matters because the site has no signal worth relying on.
struct MapsView: View {
    @Environment(ScheduleStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(value: MapRoute.grounds) {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("Grounds map & your location", systemImage: "location.viewfinder")
                                .appFont(15, weight: .semibold)
                                .foregroundStyle(.white)
                            Text("Stages, gates, camping and parking on Apple Maps — zoom in for "
                               + "the concourse.")
                                .appFont(12)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.vertical, 2)
                    }

                    ForEach(store.guide.allMaps) { map in
                        NavigationLink(value: MapRoute.image(map.id)) {
                            HStack(spacing: 12) {
                                MapThumbnail(asset: map.asset)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(map.title)
                                        .appFont(15)
                                        .foregroundStyle(.white)
                                    if let caption = map.caption {
                                        Text(caption)
                                            .appFont(12)
                                            .foregroundStyle(Theme.secondaryText)
                                            .lineLimit(2)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } footer: {
                    Text("Every map is bundled with the app and opens offline.")
                        .appFont(11)
                }
                .listRowBackground(Theme.surface)

                Section {
                    if let venue = venueInMaps {
                        Link(destination: venue) {
                            Label("Open the venue in Apple Maps", systemImage: "map")
                                .appFont(15)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    LabeledContent("Venue") {
                        Text(store.data.festival.venue)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Where") {
                        Text(store.data.festival.city).foregroundStyle(Theme.secondaryText)
                    }
                } header: {
                    Label("Getting here", systemImage: "car")
                        .foregroundStyle(Theme.accent)
                }
                .listRowBackground(Theme.surface)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Maps")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: MapRoute.self) { route in
                switch route {
                case .grounds:
                    GroundsMapView()
                case .image(let id):
                    if let map = store.guide.allMaps.first(where: { $0.id == id }) {
                        MapImageView(map: map)
                    }
                }
            }
        }
    }

    /// Drops a pin on the site itself. The coordinate comes from `map.json`, which is
    /// anchored to the roads around the grounds — `schedule.json`'s scraped pair lands
    /// nearer the town of St. Charles, a couple of miles off.
    private var venueInMaps: URL? {
        let venue = store.map.venue
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(venue.latitude),\(venue.longitude)"),
            URLQueryItem(name: "q", value: venue.name),
        ]
        return components?.url
    }
}
