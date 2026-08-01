import SwiftUI
import WidgetKit

/// Tabs, named so the widget can ask for one by deep link.
enum RootTab: Hashable {
    case schedule, lineup, maps, food
}

struct RootView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(WeatherStore.self) private var weather
    @Environment(Favorites.self) private var favorites
    @Environment(Ratings.self) private var ratings
    @Environment(CommunityRatings.self) private var community
    @Environment(NotificationManager.self) private var notifications
    @Environment(LiveActivityController.self) private var liveActivity
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: RootTab = .schedule

    var body: some View {
        TabView(selection: $tab) {
            ScheduleView()
                .tabItem { Label("Schedule", systemImage: "calendar") }
                .tag(RootTab.schedule)
            MyLineupView()
                .tabItem { Label("My Lineup", systemImage: "star.fill") }
                .tag(RootTab.lineup)
            MapsView()
                .tabItem { Label("Maps", systemImage: "map") }
                .tag(RootTab.maps)
            NavigationStack { FoodDrinkView() }
                .tabItem { Label("Food & Drink", systemImage: "fork.knife") }
                .tag(RootTab.food)
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .task {
            await notifications.refreshAuthorization()
            // Best-effort catch-up on set-time changes; failure just leaves the bundle in place.
            await store.refresh()
            // Same deal for the forecast, except there is no bundled copy to fall back to
            // — the cache from the last time there was signal is all there is.
            await weather.refresh()
            // Anything rated in the valley yesterday goes up now, and the crowd averages
            // come down. Both are best-effort and neither blocks anything.
            await community.push()
            await community.refresh()
            await syncLiveActivity()
        }
        // Starring a set should arm its reminder immediately, without a settings trip.
        .onChange(of: favorites.ids) { _, _ in
            syncReminders()
            Task { await syncLiveActivity() }
        }
        .onChange(of: store.data) { _, _ in
            syncReminders()
            Task { await syncLiveActivity() }
        }
        // One place decides what goes up, rather than every button that can rate a set.
        .onChange(of: ratings.byPerformanceID) { old, new in
            community.noteLocalChange(from: old, to: new)
            Task { await community.push() }
        }
        .onChange(of: liveActivity.isEnabled) { _, _ in
            Task { await syncLiveActivity() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            syncReminders()
            // Throttled inside the store, so coming back to the app repeatedly doesn't
            // turn into repeated WeatherKit calls.
            Task { await weather.refresh() }
            // Coming back to the app is the likeliest moment for signal to have returned,
            // which makes it the moment to drain the outbox. Also throttled.
            Task {
                await community.push()
                await community.refresh()
            }
            // ActivityKit only lets the app start a card while it's in the foreground, so
            // this is the moment to catch the Live Activity up on the whole day.
            Task { await syncLiveActivity() }
            WidgetCenter.shared.reloadAllTimelines()
        }
        // Tapping the widget or the Live Activity lands on the lineup rather than
        // wherever the app happened to be left.
        .onOpenURL { url in
            if url.host == "lineup" || url.pathComponents.contains("lineup") {
                tab = .lineup
            }
        }
    }

    private func syncReminders() {
        guard notifications.isEnabled else { return }
        notifications.reschedule(for: favorites.performances(in: store.data),
                                 festivalTimeZone: store.data.timeZone)
    }

    private func syncLiveActivity() async {
        await liveActivity.sync(data: store.data, starred: favorites.ids)
    }
}
