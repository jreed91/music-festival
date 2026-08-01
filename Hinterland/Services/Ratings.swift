import Foundation
import Observation

/// What you thought of a set you watched: one to five stars and, optionally, a line about
/// it. Keyed by performance rather than by artist — an artist can play twice over the
/// weekend, and the DJ set at 1am on the Campfire stage isn't the main-stage set.
struct SetRating: Codable, Equatable, Identifiable {
    let performanceID: String
    var stars: Int
    var note: String
    var ratedAt: Date

    var id: String { performanceID }

    static let scale = 1...5
}

/// Your ratings, persisted in `UserDefaults` alongside the stars.
///
/// Same reasoning as `Favorites`: a few dozen small values that have to survive a relaunch
/// in a field with no signal, which is neither a database nor a sync problem. This stays
/// the source of truth even though the scores are shared — `CommunityRatings` uploads from
/// here and reads the crowd average back, and it can be offline, switched off or missing
/// its container without any of it costing you a rating.
///
/// The note never goes anywhere near that. Only the score is shared.
///
/// Unlike `Favorites` this isn't in `Shared`, because the widget answers "what am I
/// watching next" and has no use for what you made of last night.
@Observable
final class Ratings {
    private static let storageKey = "setRatings"

    private(set) var byPerformanceID: [String: SetRating]
    private let defaults: UserDefaults

    /// Written to the app group for no other reason than that it's where the stars already
    /// live, so a lineup and the ratings built on top of it stay in one container.
    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        byPerformanceID = Self.stored(in: defaults)
    }

    private static func stored(in defaults: UserDefaults) -> [String: SetRating] {
        guard let payload = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: SetRating].self, from: payload)
        else { return [:] }
        return decoded
    }

    // MARK: - Reading

    func rating(for performance: Performance) -> SetRating? { byPerformanceID[performance.id] }

    /// Zero when unrated, so the star row has something to draw either way.
    func stars(for performance: Performance) -> Int { byPerformanceID[performance.id]?.stars ?? 0 }

    /// Rating a set that hasn't started yet is rating a set you haven't seen, so the
    /// control doesn't appear until the band is on.
    func canRate(_ performance: Performance, at now: Date = Date()) -> Bool {
        now >= performance.start
    }

    var count: Int { byPerformanceID.count }

    /// Rated sets, best first, then earliest — the order the recap reads in.
    func ranked(in data: FestivalData) -> [(performance: Performance, rating: SetRating)] {
        data.allPerformances
            .compactMap { performance -> (performance: Performance, rating: SetRating)? in
                guard let rating = byPerformanceID[performance.id] else { return nil }
                return (performance: performance, rating: rating)
            }
            .sorted {
                $0.rating.stars == $1.rating.stars
                    ? $0.performance.start < $1.performance.start
                    : $0.rating.stars > $1.rating.stars
            }
    }

    /// Nil rather than zero when nothing is rated, so the recap can say so instead of
    /// claiming an average of none.
    func average(in data: FestivalData) -> Double? {
        let scores = ranked(in: data).map { Double($0.rating.stars) }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    /// Sets that have finished without being rated — what the recap nudges you about.
    func unrated(among performances: [Performance], at now: Date = Date()) -> [Performance] {
        performances
            .filter { $0.end <= now && byPerformanceID[$0.id] == nil }
            .sorted { $0.start < $1.start }
    }

    // MARK: - Writing

    /// Tapping the star you already gave clears the rating — otherwise there is no way
    /// back to unrated once a star has been tapped by accident. A rating carrying a note
    /// is left alone instead: dropping something you wrote because of a stray tap on the
    /// stars isn't undoable, and "Remove rating" in the note sheet says what it does.
    func rate(_ performance: Performance, stars: Int, at now: Date = Date()) {
        let clamped = min(max(stars, SetRating.scale.lowerBound), SetRating.scale.upperBound)
        if let existing = byPerformanceID[performance.id], existing.stars == clamped {
            if existing.note.isEmpty { clear(performance) }
            return
        }

        if var existing = byPerformanceID[performance.id] {
            existing.stars = clamped
            existing.ratedAt = now
            byPerformanceID[performance.id] = existing
        } else {
            byPerformanceID[performance.id] = SetRating(performanceID: performance.id,
                                                        stars: clamped, note: "", ratedAt: now)
        }
        persist()
    }

    /// Notes hang off a rating rather than standing alone, so there's one thing to clear
    /// and one thing to show in the recap.
    func setNote(_ note: String, for performance: Performance) {
        guard var existing = byPerformanceID[performance.id] else { return }
        existing.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        byPerformanceID[performance.id] = existing
        persist()
    }

    func clear(_ performance: Performance) {
        guard byPerformanceID.removeValue(forKey: performance.id) != nil else { return }
        persist()
    }

    private func persist() {
        // Encoding a handful of small structs can't realistically fail; if it somehow did,
        // leave the last good copy on disk rather than replacing it with nothing.
        guard let payload = try? JSONEncoder().encode(byPerformanceID) else { return }
        defaults.set(payload, forKey: Self.storageKey)
    }
}
