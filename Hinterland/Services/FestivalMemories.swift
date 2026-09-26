import Foundation
import Observation

/// One festival as you had it: the sets you rated or starred, what you gave them, and what
/// everyone else made of them, kept after `schedule.json` has moved on to the next year.
///
/// This exists because ratings and stars are keyed by performance ID, and a performance
/// only means anything next to the schedule it came from. Installed apps pull that
/// schedule live from `main`, so the day next year's goes up, last year's sets vanish from
/// `store.data` — the ratings are still in `UserDefaults`, but nothing can say which band
/// `2026-07-31-main-stage-lorde` was, and the recap and My Ratings quietly empty out.
///
/// So the year keeps its own copy of just enough schedule to be recapped: the festival's
/// header and your sets, not the whole bill (that's what `past-lineups.json` is for).
struct FestivalMemory: Codable, Equatable, Identifiable {
    /// That year's schedule, cut down to the sets you rated or starred. Shaped like the
    /// real thing so `Recap` can count it without knowing the difference.
    let schedule: FestivalData
    let ratings: [String: SetRating]
    let starredIDs: Set<String>
    /// How big the whole festival was — the cut-down schedule only knows about your sets,
    /// and the recap's subtitle is about the festival.
    let setCount: Int
    let dayCount: Int
    /// What everyone gave your sets, as last downloaded while this was the current year.
    let crowd: [String: CrowdRating]
    /// The festival's best according to everyone, as it stood when the year was put away.
    let crowdTop: [CrowdTopSet]
    let crowdFetchedAt: Date?

    var id: Int { year }
    var year: Int { schedule.festival.year }

    /// Counted as though the festival is over, which by the time anyone opens one of these
    /// it is: every starred set has finished.
    var recap: Recap {
        Recap(data: schedule, ratings: ratings, starredIDs: starredIDs, now: .distantFuture)
    }

    /// Nothing rated and nothing starred. Never stored — there's no weekend to remember.
    var isEmpty: Bool { schedule.allPerformances.isEmpty }
}

/// Every year's `FestivalMemory`, persisted in the app group alongside the ratings and
/// stars it's built from.
///
/// Kept up to date for the current year whenever the schedule, your ratings, your stars
/// or the crowd averages change, so whichever of those happens last before next year's
/// schedule arrives is already in here. The raw ratings and stars are never pruned either:
/// this is an extra copy, not a move.
@Observable
final class FestivalMemories {
    private static let storageKey = "festivalMemories"

    private(set) var byYear: [Int: FestivalMemory]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        byYear = Self.stored(in: defaults)
    }

    private static func stored(in defaults: UserDefaults) -> [Int: FestivalMemory] {
        guard let payload = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([FestivalMemory].self, from: payload)
        else { return [:] }
        return Dictionary(decoded.map { ($0.year, $0) }) { _, latest in latest }
    }

    func memory(for year: Int) -> FestivalMemory? { byYear[year] }

    // MARK: - Writing

    /// Puts away the year `data` is the schedule for.
    ///
    /// `replacing` is false only for a schedule that isn't the live one — the copy bundled
    /// in the build, checked in case a newer year was already cached before this version
    /// was first opened. That one may fill a gap but never overwrites what was recorded
    /// while the year was current, which is the better copy.
    func record(_ data: FestivalData,
                ratings: [String: SetRating],
                starredIDs: Set<String>,
                community: CommunityRatings,
                replacing: Bool = true) {
        let year = data.festival.year
        if !replacing, byYear[year] != nil { return }

        let mine = Set(ratings.keys).union(starredIDs)
        let days = data.days
            .map { day in
                FestivalDay(date: day.date, weekday: day.weekday,
                            sets: day.sets.filter { mine.contains($0.id) })
            }
            .filter { !$0.sets.isEmpty }
        let sets = days.flatMap(\.sets)
        let setIDs = Set(sets.map(\.id))

        // Clearing every rating and star in the current year means there's nothing to
        // remember; keeping a stale copy would bring back what you just took away.
        guard !sets.isEmpty else {
            if replacing, byYear.removeValue(forKey: year) != nil { persist() }
            return
        }

        let artistIDs = Set(sets.map(\.artistId))
        let schedule = FestivalData(version: data.version,
                                    generatedAt: data.generatedAt,
                                    festival: data.festival,
                                    artists: data.artists.filter { artistIDs.contains($0.id) },
                                    days: days)

        // The crowd table is scoped to one year and gets replaced by the next, and it can
        // be empty simply because there's been no signal yet. An empty read never wipes
        // what an earlier one saved.
        var crowd: [String: CrowdRating] = [:]
        for performance in sets {
            if let rating = community.rating(for: performance) { crowd[performance.id] = rating }
        }
        let top = community.topSets(in: data)
        let previous = byYear[year]

        let memory = FestivalMemory(
            schedule: schedule,
            ratings: ratings.filter { setIDs.contains($0.key) },
            starredIDs: starredIDs.intersection(setIDs),
            setCount: data.allPerformances.count,
            dayCount: data.days.count,
            crowd: crowd.isEmpty ? previous?.crowd ?? [:] : crowd,
            crowdTop: top.isEmpty ? previous?.crowdTop ?? [] : top,
            crowdFetchedAt: top.isEmpty && crowd.isEmpty
                ? previous?.crowdFetchedAt
                : community.fetchedAt)

        guard memory != previous else { return }
        byYear[year] = memory
        persist()
    }

    private func persist() {
        // Same as `Ratings`: if encoding somehow failed, keep the last good copy on disk.
        let memories = byYear.values.sorted { $0.year > $1.year }
        guard let payload = try? JSONEncoder().encode(memories) else { return }
        defaults.set(payload, forKey: Self.storageKey)
    }
}
