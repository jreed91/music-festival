import Foundation

/// The container the app and the widget extension both read.
///
/// A widget runs in its own process with its own sandbox, so anything it needs to draw —
/// which sets are starred, and the most recent schedule — has to live somewhere both can
/// reach. That's the app group.
enum AppGroup {
    /// Must match the `com.apple.security.application-groups` entitlement on both targets
    /// in `project.yml`, and the group has to exist on the App ID in the developer portal.
    static let identifier = "group.com.jreed91.hinterland"

    /// Falls back to `.standard` when the group isn't provisioned, which keeps the app
    /// itself working — starring sets, reminders, everything — on a build whose App ID
    /// has no app group. The widget is what quietly goes empty in that case, because it
    /// reads a `.standard` of its own that nothing writes to.
    static let defaults: UserDefaults = UserDefaults(suiteName: identifier) ?? .standard

    /// Nil for the same reason, and callers fall back to their own container.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Whether the group is actually usable, so the UI can say why the widget is empty
    /// rather than leaving it a mystery.
    static var isAvailable: Bool { containerURL != nil }
}
