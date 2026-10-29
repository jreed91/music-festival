import SwiftUI
import UIKit

@main
struct HinterlandApp: App {
    @State private var store: ScheduleStore
    @State private var weather: WeatherStore
    @State private var favorites = Favorites()
    @State private var ratings = Ratings()
    @State private var memories = FestivalMemories()
    @State private var community: CommunityRatings
    @State private var notifications = NotificationManager()
    @State private var liveActivity = LiveActivityController()
    @State private var appleMusic = AppleMusicStore()
    @State private var preview = PreviewPlayer()

    init() {
        // The forecast is for the amphitheater rather than wherever the phone is, so it
        // needs the venue coordinate the schedule store has already loaded — hence both
        // being built here rather than as property defaults.
        let store = ScheduleStore()
        _store = State(initialValue: store)
        _weather = State(initialValue: WeatherStore(venue: store.map.venue))
        // Shared ratings are scoped to this year's festival, so the same records aren't
        // still averaging in next summer.
        _community = State(initialValue: CommunityRatings(festivalYear: store.data.festival.year))

        // The tab bar sits over dark content on every screen; make it opaque so rows
        // don't ghost through it. One lit tab in sodium, the rest unlit, labels set like
        // the design system's callsigns.
        let tabLabel = UIFont(name: AppFontFace.text(.bold), size: 10)
            ?? .systemFont(ofSize: 10, weight: .bold)
        let item = UITabBarItemAppearance()
        item.normal.iconColor = UIColor(Theme.unlit)
        item.normal.titleTextAttributes = [.foregroundColor: UIColor(Theme.unlit),
                                           .font: tabLabel, .kern: 1.2]
        item.selected.iconColor = UIColor(Theme.sodium)
        item.selected.titleTextAttributes = [.foregroundColor: UIColor(Theme.sodium),
                                             .font: tabLabel, .kern: 1.2]
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.night)
        appearance.shadowColor = UIColor(Theme.hairline)
        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance

        let navBar = UINavigationBarAppearance()
        navBar.configureWithOpaqueBackground()
        navBar.backgroundColor = UIColor(Theme.night)
        navBar.shadowColor = .clear
        let navTitle = UIFont(name: AppFontFace.text(.bold), size: 15)
            ?? .systemFont(ofSize: 15, weight: .bold)
        navBar.titleTextAttributes = [.foregroundColor: UIColor(Theme.ink),
                                      .font: navTitle, .kern: 2.4]
        UINavigationBar.appearance().standardAppearance = navBar
        UINavigationBar.appearance().scrollEdgeAppearance = navBar
        UINavigationBar.appearance().compactAppearance = navBar
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(weather)
                .environment(favorites)
                .environment(ratings)
                .environment(memories)
                .environment(community)
                .environment(notifications)
                .environment(liveActivity)
                .environment(appleMusic)
                .environment(preview)
        }
    }
}
