import SwiftUI
import UIKit

@main
struct HinterlandApp: App {
    @State private var store = ScheduleStore()
    @State private var favorites = Favorites()
    @State private var notifications = NotificationManager()

    init() {
        // The tab bar sits over dark content on every screen; make it opaque so rows
        // don't ghost through it.
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.surface)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance

        let navBar = UINavigationBarAppearance()
        navBar.configureWithOpaqueBackground()
        navBar.backgroundColor = UIColor(Theme.background)
        navBar.titleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = navBar
        UINavigationBar.appearance().scrollEdgeAppearance = navBar
        UINavigationBar.appearance().compactAppearance = navBar
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(favorites)
                .environment(notifications)
        }
    }
}
