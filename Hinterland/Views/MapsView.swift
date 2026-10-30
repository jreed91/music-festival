import SwiftUI
import UIKit

/// The festival's maps, straight off the tab bar: the georeferenced grounds map with the
/// blue dot on it, and the illustrated maps the festival publishes. Everything here is
/// bundled with the app, which matters because the site has no signal worth relying on.
struct MapsView: View {
    @Environment(ScheduleStore.self) private var store

    /// Every map but the grounds, which gets the big live tile of its own.
    private var otherMaps: [FestivalMap] {
        store.guide.allMaps.filter { $0.asset != store.map.primaryLayer.asset }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WORKS OFFLINE")
                            .appFont(12, weight: .bold)
                            .tracking(2.4)
                            .foregroundStyle(Theme.inkFaint)
                        Text("MAPS")
                            .marqueeFont(96)
                            .foregroundStyle(Theme.ink)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .padding(.bottom, 8)

                    NavigationLink(value: MapRoute.grounds) {
                        MapTile(asset: store.map.primaryLayer.asset,
                                eyebrow: "Live · you are here",
                                title: "Grounds",
                                marqueeSize: 64,
                                height: 190,
                                isLive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Grounds map and your location")

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                        GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(otherMaps) { map in
                            NavigationLink(value: MapRoute.image(map.id)) {
                                MapTile(asset: map.asset,
                                        eyebrow: map.caption ?? "",
                                        title: map.title,
                                        height: 150)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(map.title)
                            .accessibilityHint(map.caption ?? "")
                        }
                    }

                    gettingHere
                        .padding(.top, 24)

                    Horizon()
                        .padding(.top, 48)
                        .padding(.horizontal, -22)
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
            }
            .background(Theme.night)
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

    private var gettingHere: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "Getting here")
            Text(store.data.festival.venue.uppercased())
                .marqueeFont(56)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Text(store.data.festival.city)
                .appFont(17)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let venue = venueInMaps {
                Link(destination: venue) {
                    Label("Open in Apple Maps", systemImage: "arrow.up.right")
                }
                .buttonStyle(GlowButtonStyle(.quiet))
                .padding(.top, 4)
            }
            Text("Every map is bundled with the app and opens offline. Apple Maps needs "
               + "signal.")
                .appFont(13)
                .foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
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

/// A map as a tile: the art graded for night behind a gradient to `night`, a callsign
/// and the title over it. Text wraps; nothing is cut off.
private struct MapTile: View {
    let asset: String
    let eyebrow: String
    let title: String
    /// Six Caps at this size for the big tile. The small ones, two to a row, are too
    /// narrow for Six Caps to be read in, so they take the list's heavy Barlow.
    var marqueeSize: CGFloat?
    let height: CGFloat
    var isLive = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if UIImage(named: asset) != nil {
                    Image(asset)
                        .resizable()
                        .scaledToFill()
                        .nightGraded()
                } else {
                    Theme.nightRaised
                }
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .clipped()
            .accessibilityHidden(true)

            LinearGradient(colors: [.clear, Theme.night], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 4) {
                if !eyebrow.isEmpty {
                    Text(eyebrow.uppercased())
                        .appFont(12, weight: .bold)
                        .tracking(1.6)
                        .foregroundStyle(isLive ? Theme.sodium : Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                titleText
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        }
        .frame(minHeight: height)
        .background(Theme.nightRaised)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var titleText: some View {
        if let marqueeSize {
            Text(title.uppercased())
                .marqueeFont(marqueeSize)
        } else {
            Text(title.uppercased())
                .listNameFont()
        }
    }
}
