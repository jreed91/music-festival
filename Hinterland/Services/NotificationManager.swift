import Foundation
import Observation
import UserNotifications

/// Local notifications ahead of starred sets. No server, no push certificate — these are
/// scheduled on device and fire with the phone in airplane mode.
@Observable
final class NotificationManager {
    /// iOS keeps at most 64 pending local notifications per app; staying under that
    /// matters because a fully starred weekend is ~48 sets.
    private static let pendingLimit = 60
    private static let identifierPrefix = "set-reminder-"

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "remindersEnabled") }
    }

    /// Minutes of warning before a set starts — enough time to walk between stages.
    var leadMinutes: Int {
        didSet { UserDefaults.standard.set(leadMinutes, forKey: "reminderLeadMinutes") }
    }

    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: "remindersEnabled")
        let stored = defaults.integer(forKey: "reminderLeadMinutes")
        leadMinutes = stored == 0 ? 15 : stored
    }

    @MainActor
    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus
    }

    /// Returns whether we ended up authorised, so callers can flip their toggle back.
    @MainActor
    @discardableResult
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        await refreshAuthorization()
        return granted
    }

    /// Rebuilds every pending reminder from scratch — simpler and less error-prone than
    /// diffing, and cheap at this scale.
    func reschedule(for performances: [Performance], festivalTimeZone: TimeZone) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ours = requests.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)

            guard self.isEnabled else { return }

            let lead = TimeInterval(self.leadMinutes * 60)
            let now = Date()
            let formatter = DateFormatter()
            formatter.timeZone = festivalTimeZone
            formatter.dateFormat = "h:mm a"

            let upcoming = performances
                .filter { $0.start.addingTimeInterval(-lead) > now }
                .sorted { $0.start < $1.start }
                .prefix(Self.pendingLimit)

            for performance in upcoming {
                let fireDate = performance.start.addingTimeInterval(-lead)

                let content = UNMutableNotificationContent()
                content.title = performance.artist
                content.body = "Starts at \(formatter.string(from: performance.start)) "
                    + "on the \(Stage(name: performance.stage).displayName)."
                content.sound = .default

                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: fireDate)
                let request = UNNotificationRequest(
                    identifier: Self.identifierPrefix + performance.id,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
                center.add(request)
            }
        }
    }

    func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ours = requests.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }
    }
}
