import Foundation
import Observation

/// Starred sets, keyed by performance ID and persisted in `UserDefaults`.
///
/// Deliberately not SwiftData or CloudKit: this is a handful of short strings that must
/// survive a relaunch in a field with no signal, and nothing more.
@Observable
final class Favorites {
    private static let storageKey = "starredPerformanceIDs"

    private(set) var ids: Set<String>
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ids = Set(defaults.stringArray(forKey: Self.storageKey) ?? [])
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
    }
}
