import CoreLocation
import Foundation

/// Contents of `map.json` — the georeferences that pin the festival's illustrated maps
/// onto real coordinates, plus the points of interest traced off them.
///
/// The festival publishes artwork, not a survey, so everything here is an approximation.
/// The grounds map is anchored to three features the illustration shares with the world
/// (I-35, County Road G50, N Cross St) and the concourse map is fitted onto the grounds
/// map through the landmarks both draw. Good enough to answer "which way is Miniland from
/// here"; not good enough to navigate a vehicle with.
struct MapData: Codable, Equatable {
    let version: Int
    let venue: MapVenue
    /// Wide to narrow: the grounds first, then the concourse inside it. Drawn in this
    /// order, so later layers sit on top.
    let layers: [MapLayer]
}

struct MapVenue: Codable, Equatable {
    let name: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct MapLayer: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    /// Asset catalog name of the artwork this layer draws.
    let asset: String
    var note: String?
    let georeference: MapGeoreference
    /// Camera height under which this layer appears at all. The concourse artwork carries
    /// its own legend and its pins would be a pile of overlapping markers from a mile up,
    /// so the whole layer waits until you're zoomed inside the gates. Nil means always
    /// shown.
    var visibleBelowMeters: Double?
    let pois: [MapPOI]

    func isVisible(atCameraDistance distance: Double) -> Bool {
        guard let limit = visibleBelowMeters else { return true }
        return distance <= limit
    }

    func coordinate(for poi: MapPOI) -> CLLocationCoordinate2D {
        georeference.coordinate(x: poi.x, y: poi.y)
    }
}

/// Where a piece of artwork sits on the earth: its centre, how much ground it covers, and
/// how far it is turned off north.
///
/// Centre-size-rotation rather than a corner box because the concourse illustration is
/// drawn at an angle — a north-up bounding box can't express that without shearing the
/// artwork away from the ground it depicts.
struct MapGeoreference: Codable, Equatable {
    let centerLatitude: Double
    let centerLongitude: Double
    let widthMeters: Double
    let heightMeters: Double
    /// Degrees clockwise from north, applied about the centre.
    var rotation: Double = 0

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)
    }

    private var metresPerDegreeLatitude: Double { 111_132 }

    private var metresPerDegreeLongitude: Double {
        111_320 * cos(centerLatitude * .pi / 180)
    }

    /// Image space (0–1 from the top-left of the artwork) to a real coordinate.
    func coordinate(x: Double, y: Double) -> CLLocationCoordinate2D {
        offset(east: (x - 0.5) * widthMeters, south: (y - 0.5) * heightMeters)
    }

    /// Metres along the artwork's own axes to a coordinate, turning them by `rotation`
    /// on the way.
    private func offset(east: Double, south: Double) -> CLLocationCoordinate2D {
        let radians = rotation * .pi / 180
        let rotatedEast = east * cos(radians) - south * sin(radians)
        let rotatedSouth = east * sin(radians) + south * cos(radians)
        return CLLocationCoordinate2D(
            latitude: centerLatitude - rotatedSouth / metresPerDegreeLatitude,
            longitude: centerLongitude + rotatedEast / metresPerDegreeLongitude)
    }

    /// Corners of the artwork, rotation included.
    var corners: [CLLocationCoordinate2D] {
        [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)].map { coordinate(x: $0.0, y: $0.1) }
    }

    /// North-up region that contains the whole (possibly turned) artwork.
    var boundingRegion: MapRegion {
        let latitudes = corners.map(\.latitude)
        let longitudes = corners.map(\.longitude)
        return MapRegion(north: latitudes.max() ?? centerLatitude,
                         south: latitudes.min() ?? centerLatitude,
                         west: longitudes.min() ?? centerLongitude,
                         east: longitudes.max() ?? centerLongitude)
    }
}

struct MapRegion: Equatable {
    let north: Double
    let south: Double
    let west: Double
    let east: Double

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (north + south) / 2, longitude: (west + east) / 2)
    }

    var latitudeSpan: Double { north - south }
    var longitudeSpan: Double { east - west }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude <= north && coordinate.latitude >= south
            && coordinate.longitude >= west && coordinate.longitude <= east
    }
}

struct MapPOI: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: POICategory
    /// Position on the artwork, 0–1 from the top-left corner.
    let x: Double
    let y: Double
    var note: String?
}

/// The kinds of pin the two maps carry. Declaration order is filter order on screen, so
/// it runs roughly from what you look for while walking in to what you only want when
/// something has gone wrong.
enum POICategory: String, Codable, CaseIterable, Identifiable {
    case stage, entrance, gate
    case food, drink, water, restroom, merch
    case info, medical, accessibility, shade, services
    case camping, parking, exit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stage: return "Stages"
        case .entrance: return "Entrances"
        case .gate: return "Gates"
        case .food: return "Food"
        case .drink: return "Bars"
        case .water: return "Water"
        case .restroom: return "Toilets"
        case .merch: return "Merch"
        case .info: return "Info & Tickets"
        case .medical: return "Medical"
        case .accessibility: return "ADA"
        case .shade: return "Shade"
        case .services: return "Services"
        case .camping: return "Camping"
        case .parking: return "Parking"
        case .exit: return "Emergency Exits"
        }
    }

    var symbol: String {
        switch self {
        case .stage: return "music.note"
        case .entrance: return "figure.walk"
        case .gate: return "door.left.hand.open"
        case .food: return "fork.knife"
        case .drink: return "wineglass"
        case .water: return "drop"
        case .restroom: return "toilet"
        case .merch: return "tshirt"
        case .info: return "info.bubble"
        case .medical: return "cross.case"
        case .accessibility: return "figure.roll"
        case .shade: return "umbrella"
        case .services: return "bag"
        case .camping: return "tent"
        case .parking: return "parkingsign"
        case .exit: return "figure.run"
        }
    }
}

/// A pin, resolved: which layer it came from and where on earth it landed.
struct PlacedPOI: Identifiable, Equatable {
    let poi: MapPOI
    let layerID: String
    let coordinate: CLLocationCoordinate2D

    var id: String { "\(layerID)/\(poi.id)" }

    static func == (lhs: PlacedPOI, rhs: PlacedPOI) -> Bool {
        lhs.id == rhs.id
    }
}

extension MapData {
    /// The widest layer, which is what the map opens on. `map.json` is a build input we
    /// control and `ScheduleStore` already refuses to launch on a malformed one, so an
    /// empty layer list is a packaging bug rather than a runtime state to handle.
    var primaryLayer: MapLayer { layers.first! }

    func layer(id: String) -> MapLayer? { layers.first { $0.id == id } }

    func visibleLayers(at cameraDistance: Double) -> [MapLayer] {
        layers.filter { $0.isVisible(atCameraDistance: cameraDistance) }
    }

    /// Pins for the categories asked for, from the layers detailed enough to be legible
    /// at this camera height.
    func placedPOIs(in categories: Set<POICategory>, cameraDistance: Double) -> [PlacedPOI] {
        visibleLayers(at: cameraDistance).flatMap { layer in
            layer.pois
                .filter { categories.contains($0.category) }
                .map { PlacedPOI(poi: $0, layerID: layer.id, coordinate: layer.coordinate(for: $0)) }
        }
    }

    /// Categories worth offering as filters at this camera height, in the order the enum
    /// declares them. Tied to the visible layers so the row tracks what's actually on
    /// screen: camping and parking from a mile up, toilets and water once you're inside
    /// the gates, rather than sixteen chips that half do nothing wherever you're looking.
    func presentCategories(at cameraDistance: Double) -> [POICategory] {
        let present = Set(visibleLayers(at: cameraDistance).flatMap(\.pois).map(\.category))
        return POICategory.allCases.filter(present.contains)
    }
}
