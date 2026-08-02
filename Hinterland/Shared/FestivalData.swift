import Foundation

/// Top-level payload of `schedule.json`, shipped in the bundle and refreshable from GitHub.
struct FestivalData: Codable, Equatable {
    let version: Int
    let generatedAt: Date
    let festival: Festival
    let artists: [Artist]
    let days: [FestivalDay]
}

struct Festival: Codable, Equatable {
    let name: String
    let year: Int
    let venue: String
    let city: String
    let latitude: Double
    let longitude: Double
    let timeZone: String
    let startDate: String
    let endDate: String
    let website: String
}

struct Artist: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let name: String
    var imageURL: String?
    var imageAsset: String?
    var sourceSlug: String?
    var bio: String?
    var spotifyArtistID: String?
    /// Apple's catalog id, and an override rather than a requirement: `AppleMusicStore`
    /// finds nearly everyone by searching their name, and this is how an artist whose
    /// name collides with another act's gets pinned to the right one from the schedule.
    var appleMusicArtistID: String?
    var instagram: String?
}

struct FestivalDay: Codable, Equatable, Identifiable {
    /// Calendar day the programming belongs to, `yyyy-MM-dd`. Late-night sets after
    /// midnight stay attached to the day they belong to musically, not the clock.
    let date: String
    let weekday: String
    let sets: [Performance]

    var id: String { date }

    /// "Thu" — the compact label used in the day picker.
    var shortWeekday: String { String(weekday.prefix(3)) }
}

struct Performance: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let artistId: String
    let artist: String
    let stage: String
    let start: Date
    let end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }

    func overlaps(_ other: Performance) -> Bool {
        start < other.end && other.start < end
    }

    func isLive(at date: Date) -> Bool { date >= start && date < end }
}

// MARK: - Stages

/// The three Hinterland stages, used for colour-coding and filtering. Unknown stage
/// names coming from a refreshed schedule still render, they just fall back to `other`.
enum Stage: Hashable {
    case main
    case miniland
    case campfire
    case other(String)

    init(name: String) {
        switch name.lowercased() {
        case let s where s.contains("main"): self = .main
        case let s where s.contains("miniland"): self = .miniland
        case let s where s.contains("campfire"): self = .campfire
        default: self = .other(name)
        }
    }

    var displayName: String {
        switch self {
        case .main: return "Main Stage"
        case .miniland: return "Miniland"
        case .campfire: return "Campfire"
        case .other(let name): return name
        }
    }

    var symbol: String {
        switch self {
        case .main: return "music.mic"
        case .miniland: return "guitars"
        case .campfire: return "flame"
        case .other: return "music.note"
        }
    }
}

// MARK: - Convenience lookups

extension FestivalData {
    var allPerformances: [Performance] { days.flatMap(\.sets) }

    func artist(id: String) -> Artist? { artists.first { $0.id == id } }

    func performances(forArtist artistID: String) -> [Performance] {
        allPerformances.filter { $0.artistId == artistID }.sorted { $0.start < $1.start }
    }

    func day(containing performance: Performance) -> FestivalDay? {
        days.first { $0.sets.contains(performance) }
    }

    /// Stage names in the order they first appear in the schedule.
    var stageNames: [String] {
        var seen: [String] = []
        for performance in allPerformances where !seen.contains(performance.stage) {
            seen.append(performance.stage)
        }
        return seen
    }

    /// The festival's own time zone, so set times read correctly from any device.
    var timeZone: TimeZone { TimeZone(identifier: festival.timeZone) ?? .current }
}
