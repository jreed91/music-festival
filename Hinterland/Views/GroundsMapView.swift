import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// The illustrated grounds map, georeferenced onto MapKit with a pin for every stage,
/// gate, camping area and lot.
///
/// The point of putting it on MapKit rather than leaving it as a picture is the blue dot:
/// the artwork alone tells you where the Campfire Stage is, this tells you where *you*
/// are relative to it. Apple's tiles need a network and won't load in the valley, but the
/// illustration is bundled and Core Location works fine with no signal, so the useful
/// half of the screen survives being offline.
struct GroundsMapView: View {
    @Environment(ScheduleStore.self) private var store

    @State private var categories: Set<POICategory> = Set(POICategory.allCases)
    @State private var showsIllustration = true
    @State private var usesSatellite = false
    @State private var selection: MapPOI?
    @State private var userLocation: CLLocation?
    @State private var recenterCount = 0

    private var map: MapData { store.map }

    var body: some View {
        ZStack(alignment: .bottom) {
            GroundsMapRepresentable(
                map: map,
                visible: map.pois(in: categories),
                showsIllustration: showsIllustration,
                usesSatellite: usesSatellite,
                recenterCount: recenterCount,
                selection: $selection,
                userLocation: $userLocation
            )
            .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 0) {
                filters
                Spacer()
                if let selection {
                    POICard(poi: selection,
                            coordinate: map.coordinate(for: selection),
                            userLocation: userLocation) {
                        self.selection = nil
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    caveat
                }
            }
        }
        .animation(.snappy(duration: 0.22), value: selection)
        .background(Theme.background)
        .navigationTitle("Grounds")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    recenterCount += 1
                } label: {
                    Image(systemName: "location")
                }
                Menu {
                    Toggle("Illustrated map", isOn: $showsIllustration)
                    Toggle("Satellite", isOn: $usesSatellite)
                } label: {
                    Image(systemName: "square.3.layers.3d")
                }
            }
        }
        .tint(Theme.accent)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(map.presentCategories) { category in
                    let isOn = categories.contains(category)
                    Button {
                        if isOn { categories.remove(category) } else { categories.insert(category) }
                        if let selection, !categories.contains(selection.category) {
                            self.selection = nil
                        }
                    } label: {
                        Label(category.label, systemImage: category.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(isOn ? category.tint.opacity(0.9) : Theme.surface.opacity(0.9),
                                        in: Capsule())
                            .foregroundStyle(isOn ? Color.black.opacity(0.85) : Theme.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    private var caveat: some View {
        Text("Pins are traced off the festival's illustrated map, so they're accurate to "
           + "roughly a field's width. Apple's map tiles need signal; the illustration and "
           + "your location don't.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.secondaryText)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
    }
}

// MARK: - Selected pin

private struct POICard: View {
    let poi: MapPOI
    let coordinate: CLLocationCoordinate2D
    let userLocation: CLLocation?
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Label(poi.name, systemImage: poi.category.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }

            if let note = poi.note {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                if let distance {
                    Label(distance, systemImage: "figure.walk")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                Spacer()
                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
                    item.name = poi.name
                    item.openInMaps(launchOptions:
                        [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.circle")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Theme.hairline, lineWidth: 1))
    }

    /// Straight-line distance — there's no route across a field worth computing.
    private var distance: String? {
        guard let userLocation else { return nil }
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let metres = target.distance(from: userLocation)
        guard metres.isFinite, metres < 40_000 else { return nil }
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = metres < 1000 ? 0 : 1
        return formatter.string(from: Measurement(value: metres, unit: UnitLength.meters))
    }
}

// MARK: - MapKit

private struct GroundsMapRepresentable: UIViewRepresentable {
    let map: MapData
    let visible: [MapPOI]
    let showsIllustration: Bool
    let usesSatellite: Bool
    let recenterCount: Int
    @Binding var selection: MapPOI?
    @Binding var userLocation: CLLocation?

    func makeUIView(context: Context) -> MKMapView {
        let view = MKMapView()
        view.delegate = context.coordinator
        view.showsUserLocation = true
        view.showsCompass = true
        view.pointOfInterestFilter = .excludingAll
        view.register(POIAnnotationView.self,
                      forAnnotationViewWithReuseIdentifier: POIAnnotationView.reuseID)

        let region = MKCoordinateRegion(
            center: map.georeference.center,
            span: MKCoordinateSpan(latitudeDelta: map.georeference.latitudeSpan * 1.15,
                                   longitudeDelta: map.georeference.longitudeSpan * 1.15))
        view.setRegion(region, animated: false)

        // Keep the site on screen: there is nothing to look at for miles around, and a
        // stray pinch shouldn't strand anyone over Nebraska.
        if let boundary = MKMapView.CameraBoundary(coordinateRegion: region) {
            view.cameraBoundary = boundary
        }
        if let zoom = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 120,
                                                maxCenterCoordinateDistance: 12_000) {
            view.cameraZoomRange = zoom
        }

        context.coordinator.requestLocationPermission()
        context.coordinator.setIllustration(showsIllustration, on: view, map: map)
        return view
    }

    func updateUIView(_ view: MKMapView, context: Context) {
        context.coordinator.parent = self
        view.preferredConfiguration = usesSatellite
            ? MKHybridMapConfiguration(elevationStyle: .flat)
            : MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)

        context.coordinator.setIllustration(showsIllustration, on: view, map: map)
        context.coordinator.setAnnotations(visible, on: view, map: map)
        context.coordinator.syncSelection(selection, on: view)
        context.coordinator.recenterIfNeeded(recenterCount, on: view, map: map)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, MKMapViewDelegate, CLLocationManagerDelegate {
        var parent: GroundsMapRepresentable
        private let locationManager = CLLocationManager()
        private var overlay: IllustrationOverlay?
        private var shownIDs: Set<String> = []
        private var lastRecenter = 0

        init(parent: GroundsMapRepresentable) {
            self.parent = parent
            super.init()
            locationManager.delegate = self
        }

        func requestLocationPermission() {
            guard locationManager.authorizationStatus == .notDetermined else { return }
            locationManager.requestWhenInUseAuthorization()
        }

        func setIllustration(_ shown: Bool, on view: MKMapView, map: MapData) {
            if shown, overlay == nil, let image = UIImage(named: map.georeference.asset) {
                let new = IllustrationOverlay(georeference: map.georeference, image: image)
                overlay = new
                view.addOverlay(new, level: .aboveRoads)
            } else if !shown, let existing = overlay {
                view.removeOverlay(existing)
                overlay = nil
            }
        }

        func setAnnotations(_ pois: [MapPOI], on view: MKMapView, map: MapData) {
            let wanted = Set(pois.map(\.id))
            guard wanted != shownIDs else { return }
            shownIDs = wanted

            let stale = view.annotations.compactMap { $0 as? POIAnnotation }
                .filter { !wanted.contains($0.poi.id) }
            view.removeAnnotations(stale)

            let existing = Set(view.annotations.compactMap { ($0 as? POIAnnotation)?.poi.id })
            let additions = pois.filter { !existing.contains($0.id) }
                .map { POIAnnotation(poi: $0, coordinate: map.coordinate(for: $0)) }
            view.addAnnotations(additions)
        }

        func syncSelection(_ poi: MapPOI?, on view: MKMapView) {
            guard poi == nil else { return }
            for annotation in view.selectedAnnotations { view.deselectAnnotation(annotation, animated: true) }
        }

        func recenterIfNeeded(_ count: Int, on view: MKMapView, map: MapData) {
            guard count != lastRecenter else { return }
            lastRecenter = count

            // Recentre on the user when we have them and they're actually at the site,
            // otherwise frame the grounds again.
            if let location = view.userLocation.location,
               MKMapPoint(location.coordinate).isInside(map.georeference) {
                view.setRegion(MKCoordinateRegion(center: location.coordinate,
                                                  latitudinalMeters: 400,
                                                  longitudinalMeters: 400), animated: true)
            } else {
                view.setRegion(MKCoordinateRegion(
                    center: map.georeference.center,
                    span: MKCoordinateSpan(latitudeDelta: map.georeference.latitudeSpan * 1.15,
                                           longitudeDelta: map.georeference.longitudeSpan * 1.15)),
                    animated: true)
            }
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let illustration = overlay as? IllustrationOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            return IllustrationOverlayRenderer(overlay: illustration)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let poi = annotation as? POIAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: POIAnnotationView.reuseID, for: poi)
            (view as? POIAnnotationView)?.configure(for: poi.poi)
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let poi = view.annotation as? POIAnnotation else { return }
            parent.selection = poi.poi
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            guard mapView.selectedAnnotations.isEmpty else { return }
            parent.selection = nil
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            parent.userLocation = userLocation.location
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            // Nothing to do — MKMapView starts the blue dot itself once we're allowed.
        }
    }
}

// MARK: - Illustration overlay

/// Draws the bundled grounds artwork inside its georeferenced box. Bundled, so it renders
/// with no network at all.
private final class IllustrationOverlay: NSObject, MKOverlay {
    let image: UIImage
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect

    init(georeference: MapGeoreference, image: UIImage) {
        self.image = image
        self.coordinate = georeference.center

        let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: georeference.north,
                                                        longitude: georeference.west))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: georeference.south,
                                                            longitude: georeference.east))
        self.boundingMapRect = MKMapRect(x: topLeft.x, y: topLeft.y,
                                         width: bottomRight.x - topLeft.x,
                                         height: bottomRight.y - topLeft.y)
        super.init()
    }
}

private final class IllustrationOverlayRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let illustration = overlay as? IllustrationOverlay,
              let cgImage = illustration.image.cgImage else { return }

        let rect = self.rect(for: illustration.boundingMapRect)
        context.saveGState()
        context.setAlpha(0.92)
        // Core Graphics draws images bottom-up; MapKit's rect is top-down.
        context.translateBy(x: 0, y: rect.origin.y * 2 + rect.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: rect)
        context.restoreGState()
    }
}

// MARK: - Pins

private final class POIAnnotation: NSObject, MKAnnotation {
    let poi: MapPOI
    let coordinate: CLLocationCoordinate2D
    var title: String? { poi.name }
    var subtitle: String? { poi.note }

    init(poi: MapPOI, coordinate: CLLocationCoordinate2D) {
        self.poi = poi
        self.coordinate = coordinate
        super.init()
    }
}

private final class POIAnnotationView: MKMarkerAnnotationView {
    static let reuseID = "poi"

    func configure(for poi: MapPOI) {
        markerTintColor = UIColor(poi.category.tint)
        glyphImage = UIImage(systemName: poi.category.symbol)
        glyphTintColor = .black.withAlphaComponent(0.85)
        titleVisibility = poi.category == .stage ? .visible : .adaptive
        displayPriority = poi.category == .stage ? .required : .defaultHigh
        canShowCallout = false
    }
}

private extension MKMapPoint {
    func isInside(_ georeference: MapGeoreference) -> Bool {
        let coordinate = self.coordinate
        return coordinate.latitude <= georeference.north
            && coordinate.latitude >= georeference.south
            && coordinate.longitude >= georeference.west
            && coordinate.longitude <= georeference.east
    }
}
