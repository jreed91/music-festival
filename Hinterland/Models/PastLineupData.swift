import Foundation

/// Contents of `past-lineups.json` — every Hinterland that has already happened, as the
/// festival's own archive page lists them.
///
/// Bundled only, like `map.json` and `vendors.json`. Ten summers that already happened
/// are not going to change over a weekend, so there is nothing a refresh could usefully
/// bring down.
struct PastLineupData: Codable, Equatable {
    let version: Int
    let generatedAt: Date
    /// The page this was scraped from, linked at the bottom of the archive.
    var source: String?
    /// Newest first — the order the festival prints them, and the order they get read in.
    let years: [PastLineupYear]
}

struct PastLineupYear: Codable, Equatable, Identifiable {
    let year: Int
    /// One entry per day of that year's festival, in the order the archive lists them.
    /// The page never says which calendar day a bill was, so neither does this — the
    /// headliner is the heading, the way it is on the poster.
    let days: [PastLineupDay]

    var id: Int { year }

    /// Every act that played that year, headliners included.
    var acts: [PastAct] { days.flatMap(\.acts) }

    var headliners: [String] { days.map(\.headliner) }
}

struct PastLineupDay: Codable, Equatable, Identifiable {
    let id: String
    /// The name printed at the top of the day's bill.
    let headliner: String
    /// Everyone else on that day, in billing order.
    let support: [PastAct]

    /// The whole bill, headliner first.
    var acts: [PastAct] { [PastAct(name: headliner)] + support }
}

struct PastAct: Codable, Equatable, Identifiable, Hashable {
    let name: String
    /// The side stage the archive prints after the name — Campfire, Brunch, Miniland,
    /// Hinterkids. Nil is the main stage, which the archive never spells out.
    var stage: String? = nil

    /// Distinct within a day, which is the only place a bill is listed: 2025 billed both
    /// "Rebecca Black" and "Rebecca Black DJ Set (Campfire Stage)" on the same night.
    var id: String { stage.map { "\(name) (\($0))" } ?? name }
}

// MARK: - Lookups

extension PastLineupData {
    var actCount: Int { years.reduce(0) { $0 + $1.acts.count } }

    func year(_ value: Int) -> PastLineupYear? { years.first { $0.year == value } }

    /// Years inside the archive's range with no festival in them — 2020, and nothing else
    /// so far. Derived rather than written down, so the day the run breaks again the
    /// screen says so without anyone editing it.
    var missingYears: [Int] {
        let held = Set(years.map(\.year))
        guard let first = held.min(), let last = held.max() else { return [] }
        return (first...last).filter { !held.contains($0) }
    }
}
