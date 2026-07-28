import CoreLocation
import Foundation

/// Contents of `map.json` — the georeference that pins the illustrated grounds map onto
/// real coordinates, plus the points of interest traced off it.
///
/// The festival publishes artwork, not a survey, so everything here is an approximation
/// anchored to three features the illustration shares with the world: I-35 down the east
/// edge, County Road G50 across the bottom and N Cross St on the west. Good enough to
/// answer "which way is the Campfire Stage from my tent"; not good enough to navigate a
/// vehicle with.
struct MapData: Codable, Equatable {
    let version: Int
    let venue: MapVenue
    let georeference: MapGeoreference
    let pois: [MapPOI]
}

struct MapVenue: Codable, Equatable {
    let name: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// The bounding box of the illustration, north-up. Corners are enough: the artwork is
/// drawn without rotation, so a linear map from image space to coordinates is as much
/// precision as the source supports.
struct MapGeoreference: Codable, Equatable {
    let asset: String
    var note: String?
    let north: Double
    let south: Double
    let west: Double
    let east: Double

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (north + south) / 2, longitude: (west + east) / 2)
    }

    var latitudeSpan: Double { north - south }
    var longitudeSpan: Double { east - west }

    /// Image-space (0–1 from the top-left of the artwork) to a real coordinate.
    func coordinate(x: Double, y: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: north - y * latitudeSpan,
                               longitude: west + x * longitudeSpan)
    }
}

struct MapPOI: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: POICategory
    /// Position on the grounds artwork, 0–1 from the top-left corner.
    let x: Double
    let y: Double
    var note: String?
}

enum POICategory: String, Codable, CaseIterable, Identifiable {
    case stage, entrance, gate, camping, parking, services, medical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stage: return "Stages"
        case .entrance: return "Entrances"
        case .gate: return "Gates"
        case .camping: return "Camping"
        case .parking: return "Parking"
        case .services: return "Services"
        case .medical: return "Medical"
        }
    }

    var symbol: String {
        switch self {
        case .stage: return "music.note"
        case .entrance: return "figure.walk"
        case .gate: return "door.left.hand.open"
        case .camping: return "tent"
        case .parking: return "parkingsign"
        case .services: return "bag"
        case .medical: return "cross.case"
        }
    }
}

extension MapData {
    func coordinate(for poi: MapPOI) -> CLLocationCoordinate2D {
        georeference.coordinate(x: poi.x, y: poi.y)
    }

    func pois(in categories: Set<POICategory>) -> [MapPOI] {
        pois.filter { categories.contains($0.category) }
    }

    /// Categories that actually have pins, in the order the enum declares them.
    var presentCategories: [POICategory] {
        POICategory.allCases.filter { category in pois.contains { $0.category == category } }
    }
}
