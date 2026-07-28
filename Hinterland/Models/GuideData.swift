import Foundation

/// Contents of `info.json` — the festival guide, flattened for offline reading.
struct GuideData: Codable, Equatable {
    let version: Int
    let categories: [GuideCategory]
    /// Written by `scripts/maps.py`; optional so an older bundled or cached file still
    /// decodes.
    var maps: [FestivalMap]?
}

/// A map image bundled in the asset catalog, so parking routes are readable in a field
/// with no signal.
struct FestivalMap: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let asset: String
    var caption: String?
    /// Guide entry this map belongs to, shown inline while reading it.
    var topicID: String?
    var width: Int?
    var height: Int?
    var sourceURL: String?

    /// Only the grounds map is georeferenced, and it's the one worth putting on MapKit.
    var isGrounds: Bool { id == "grounds" }
}

struct GuideCategory: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let topics: [GuideTopic]

    var symbol: String {
        switch id {
        case "ticketing": return "ticket"
        case "general-info": return "info.circle"
        case "activities-merch": return "sparkles"
        case "getting-here-maps": return "car"
        case "health-safety-security": return "cross.case"
        case "accessibility": return "figure.roll"
        case "insider-tips": return "lightbulb"
        case "contacts": return "envelope"
        case "camping": return "tent"
        default: return "doc.text"
        }
    }
}

struct GuideTopic: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let body: String
    var url: String?
    var links: [String]?

    /// First line or so, for the collapsed row.
    var snippet: String {
        body.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension GuideData {
    var allTopics: [GuideTopic] { categories.flatMap(\.topics) }

    var allMaps: [FestivalMap] { maps ?? [] }

    func maps(for topic: GuideTopic) -> [FestivalMap] {
        allMaps.filter { $0.topicID == topic.id }
    }

    func category(for topic: GuideTopic) -> GuideCategory? {
        categories.first { $0.topics.contains(where: { $0.id == topic.id }) }
    }

    func search(_ query: String) -> [GuideTopic] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }
        return allTopics.filter {
            $0.title.lowercased().contains(needle) || $0.body.lowercased().contains(needle)
        }
    }
}
