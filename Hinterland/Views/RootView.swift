import SwiftUI

struct RootView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(WeatherStore.self) private var weather
    @Environment(Favorites.self) private var favorites
    @Environment(NotificationManager.self) private var notifications
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            ScheduleView()
                .tabItem { Label("Schedule", systemImage: "calendar") }
            MyLineupView()
                .tabItem { Label("My Lineup", systemImage: "star.fill") }
            ArtistsView()
                .tabItem { Label("Artists", systemImage: "music.mic") }
            InfoView()
                .tabItem { Label("Info", systemImage: "info.circle") }
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
        }
        // Starring a set should arm its reminder immediately, without a settings trip.
        .onChange(of: favorites.ids) { _, _ in syncReminders() }
        .onChange(of: store.data) { _, _ in syncReminders() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            syncReminders()
            // Throttled inside the store, so coming back to the app repeatedly doesn't
            // turn into repeated WeatherKit calls.
            Task { await weather.refresh() }
        }
    }

    private func syncReminders() {
        guard notifications.isEnabled else { return }
        notifications.reschedule(for: favorites.performances(in: store.data),
                                 festivalTimeZone: store.data.timeZone)
    }
}
