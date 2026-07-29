import Foundation
import Observation
import WidgetKit

/// Starred sets, keyed by performance ID and persisted in `UserDefaults`.
///
/// Deliberately not SwiftData or CloudKit: this is a handful of short strings that must
/// survive a relaunch in a field with no signal, and nothing more.
///
/// Stored in the app group rather than `.standard` so the widget extension, which is a
/// separate process, can read the same stars the app writes.
@Observable
final class Favorites {
    private static let storageKey = "starredPerformanceIDs"

    private(set) var ids: Set<String>
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        Self.migrateFromStandardDefaults(into: defaults)
        ids = Self.storedIDs(in: defaults)
    }

    /// Reading without building the observable object, for the widget's timeline.
    static func storedIDs(in defaults: UserDefaults = AppGroup.defaults) -> Set<String> {
        Set(defaults.stringArray(forKey: storageKey) ?? [])
    }

    /// Stars were in `.standard` before the widget existed. Copy them across once so
    /// updating the app doesn't silently wipe a lineup someone spent an evening building.
    private static func migrateFromStandardDefaults(into defaults: UserDefaults) {
        let standard = UserDefaults.standard
        guard defaults !== standard,
              defaults.object(forKey: storageKey) == nil,
              let legacy = standard.stringArray(forKey: storageKey) else { return }
        defaults.set(legacy, forKey: storageKey)
    }

    func contains(_ performance: Performance) -> Bool { ids.contains(performance.id) }
    func contains(id: String) -> Bool { ids.contains(id) }

    func toggle(_ performance: Performance) {
        if ids.contains(performance.id) {
            ids.remove(performance.id)
        } else {
            ids.insert(performance.id)
        }
        persist()
    }

    /// Starred sets in chronological order.
    func performances(in data: FestivalData) -> [Performance] {
        data.allPerformances.filter { ids.contains($0.id) }.sorted { $0.start < $1.start }
    }

    /// Starred sets that overlap another starred set — you can't be in two places at once.
    func conflicts(in data: FestivalData) -> [(Performance, Performance)] {
        let starred = performances(in: data)
        var found: [(Performance, Performance)] = []
        for (index, performance) in starred.enumerated() {
            for other in starred.dropFirst(index + 1) {
                // Sorted by start, so once a set begins after this one ends we're done.
                if other.start >= performance.end { break }
                if performance.overlaps(other) { found.append((performance, other)) }
            }
        }
        return found
    }

    func isInConflict(_ performance: Performance, in data: FestivalData) -> Bool {
        conflicts(in: data).contains { $0.0 == performance || $0.1 == performance }
    }

    private func persist() {
        defaults.set(Array(ids), forKey: Self.storageKey)
        // Starring a set should change the widget then and there, not at whatever point
        // WidgetKit next felt like asking.
        WidgetCenter.shared.reloadAllTimelines()
    }
}
