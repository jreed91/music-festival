import SwiftUI

struct RootView: View {
    @Environment(ScheduleStore.self) private var store
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
        }
        // Starring a set should arm its reminder immediately, without a settings trip.
        .onChange(of: favorites.ids) { _, _ in syncReminders() }
        .onChange(of: store.data) { _, _ in syncReminders() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { syncReminders() }
        }
    }

    private func syncReminders() {
        guard notifications.isEnabled else { return }
        notifications.reschedule(for: favorites.performances(in: store.data),
                                 festivalTimeZone: store.data.timeZone)
    }
}
