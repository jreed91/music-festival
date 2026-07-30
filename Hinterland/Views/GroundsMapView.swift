import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// The festival's illustrated maps, georeferenced onto MapKit: the grounds across the
/// whole site and the concourse artwork laid inside it, with a pin for every stage, gate,
/// camping area, lot and the things inside the gates.
///
/// The point of putting them on MapKit rather than leaving them as pictures is the blue
/// dot: the artwork alone tells you where Miniland is, this tells you where *you* are
/// relative to it. Apple's tiles need a network and won't load in the valley, but the
/// illustrations are bundled and Core Location works fine with no signal, so the useful
/// half of the screen survives being offline.
struct GroundsMapView: View {
    @Environment(ScheduleStore.self) private var store

    @State private var categories: Set<POICategory> = Set(POICategory.allCases)
    @State private var showsIllustration = true
    @State private var usesSatellite = false
    @State private var selection: PlacedPOI?
    @State private var userLocation: CLLocation?
    @State private var cameraDistance: Double = 3_000
    @State private var focus: MapFocus?

    private var map: MapData { store.map }

    private var visible: [PlacedPOI] {
        map.placedPOIs(in: categories, cameraDistance: cameraDistance)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            GroundsMapRepresentable(
                map: map,
                visible: visible,
                showsIllustration: showsIllustration,
                usesSatellite: usesSatellite,
                focus: focus,
                selection: $selection,
                userLocation: $userLocation,
                cameraDistance: $cameraDistance
            )
            // Deliberately *not* ignoring the bottom safe area. The illustrations are
            // bright daylight artwork, and running them under the floating tab bar left
            // "Schedule" and "Food & Drink" sitting on lime green — the bar's material
            // takes its contrast from whatever is behind it, and neither
            // `UITabBarAppearance` nor `.toolbarBackground` reaches it on current iOS.
            // Ending the map at the safe area puts the app's own dark background back
            // behind the bar, which is the one thing that reliably works.

            VStack(spacing: 0) {
                filters
                Spacer()
                if let selection {
                    POICard(placed: selection, userLocation: userLocation) {
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
        .navigationTitle(zoomedIntoConcourse ? "Concourse" : "Grounds")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    focus = MapFocus(target: .user, token: (focus?.token ?? 0) + 1)
                } label: {
                    Image(systemName: "location")
                }
                Menu {
                    Toggle("Illustrated maps", isOn: $showsIllustration)
                    Toggle("Satellite", isOn: $usesSatellite)
                    Divider()
                    // Jumping straight to a layer beats pinching your way in with gloves
                    // on at midnight.
                    ForEach(map.layers) { layer in
                        Button(layer.title) {
                            focus = MapFocus(target: .layer(layer.id),
                                             token: (focus?.token ?? 0) + 1)
                        }
                    }
                } label: {
                    Image(systemName: "square.3.layers.3d")
                }
            }
        }
        .tint(Theme.accent)
    }

    /// Close enough in that a detail layer — the concourse — is what's being read.
    private var zoomedIntoConcourse: Bool {
        map.layers.dropFirst().contains { $0.isVisible(atCameraDistance: cameraDistance) }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(map.presentCategories(at: cameraDistance)) { category in
                    let isOn = categories.contains(category)
                    Button {
                        if isOn { categories.remove(category) } else { categories.insert(category) }
                        if let selection, !categories.contains(selection.poi.category) {
                            self.selection = nil
                        }
                    } label: {
                        Label(category.label, systemImage: category.symbol)
                            .appFont(12, weight: .semibold)
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
        // A system material would brighten to match the artwork underneath and take the
        // chip labels with it. This strip has to stay dark whatever it is sitting on.
        .background(Theme.background.opacity(0.88))
    }

    private var caveat: some View {
        Text(zoomedIntoConcourse
             ? "Concourse pins are fitted to the grounds map, so they're accurate to "
             + "roughly the width of a beer tent. Zoom out for camping and parking."
             : "Pins are traced off the festival's illustrated maps, so they're accurate "
             + "to roughly a field's width. Zoom in for what's inside the gates.")
            .appFont(11)
            .foregroundStyle(Theme.secondaryText)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Theme.background.opacity(0.88))
    }
}

/// What the map should frame next. The token makes repeat taps distinguishable.
struct MapFocus: Equatable {
    enum Target: Equatable {
        case user
        case layer(String)
    }

    let target: Target
    let token: Int
}

// MARK: - Selected pin

private struct POICard: View {
    let placed: PlacedPOI
    let userLocation: CLLocation?
    let dismiss: () -> Void

    private var poi: MapPOI { placed.poi }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Label(poi.name, systemImage: poi.category.symbol)
                    .appFont(16, weight: .semibold)
                    .foregroundStyle(.white)
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .appFont(18)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }

            if let note = poi.note {
                Text(note)
                    .appFont(13)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                if let distance {
                    Label(distance, systemImage: "figure.walk")
                        .appFont(12, weight: .medium)
                        .foregroundStyle(Theme.accent)
                }
                Spacer()
                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: placed.coordinate))
                    item.name = poi.name
                    item.openInMaps(launchOptions:
                        [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.circle")
                        .appFont(12, weight: .semibold)
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
        let target = CLLocation(latitude: placed.coordinate.latitude,
                                longitude: placed.coordinate.longitude)
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
    let visible: [PlacedPOI]
    let showsIllustration: Bool
    let usesSatellite: Bool
    let focus: MapFocus?
    @Binding var selection: PlacedPOI?
    @Binding var userLocation: CLLocation?
    @Binding var cameraDistance: Double

    func makeUIView(context: Context) -> MKMapView {
        let view = MKMapView()
        view.delegate = context.coordinator
        view.showsUserLocation = true
        view.showsCompass = true
        view.pointOfInterestFilter = .excludingAll
        view.register(POIAnnotationView.self,
                      forAnnotationViewWithReuseIdentifier: POIAnnotationView.reuseID)

        view.setRegion(context.coordinator.region(framing: map.primaryLayer), animated: false)

        // Keep the site on screen: there is nothing to look at for miles around, and a
        // stray pinch shouldn't strand anyone over Nebraska.
        let bounds = map.primaryLayer.georeference.boundingRegion
        let boundary = MKCoordinateRegion(
            center: bounds.center,
            span: MKCoordinateSpan(latitudeDelta: bounds.latitudeSpan * 1.6,
                                   longitudeDelta: bounds.longitudeSpan * 1.6))
        if let limit = MKMapView.CameraBoundary(coordinateRegion: boundary) {
            view.cameraBoundary = limit
        }
        if let zoom = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 80,
                                                maxCenterCoordinateDistance: 12_000) {
            view.cameraZoomRange = zoom
        }

        context.coordinator.requestLocationPermission()
        context.coordinator.setIllustrations(showsIllustration, cameraDistance: cameraDistance,
                                             on: view, map: map)
        return view
    }

    func updateUIView(_ view: MKMapView, context: Context) {
        context.coordinator.parent = self
        view.preferredConfiguration = usesSatellite
            ? MKHybridMapConfiguration(elevationStyle: .flat)
            : MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)

        context.coordinator.setIllustrations(showsIllustration, cameraDistance: cameraDistance,
                                             on: view, map: map)
        context.coordinator.setAnnotations(visible, on: view)
        context.coordinator.syncSelection(selection, on: view)
        context.coordinator.applyFocus(focus, on: view, map: map)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, MKMapViewDelegate, CLLocationManagerDelegate {
        var parent: GroundsMapRepresentable
        private let locationManager = CLLocationManager()
        private var overlays: [IllustrationOverlay] = []
        private var shownIDs: Set<String> = []
        private var lastFocusToken = 0

        init(parent: GroundsMapRepresentable) {
            self.parent = parent
            super.init()
            locationManager.delegate = self
        }

        func requestLocationPermission() {
            guard locationManager.authorizationStatus == .notDetermined else { return }
            locationManager.requestWhenInUseAuthorization()
        }

        func region(framing layer: MapLayer) -> MKCoordinateRegion {
            let bounds = layer.georeference.boundingRegion
            return MKCoordinateRegion(
                center: bounds.center,
                span: MKCoordinateSpan(latitudeDelta: bounds.latitudeSpan * 1.15,
                                       longitudeDelta: bounds.longitudeSpan * 1.15))
        }

        /// Layers are added in file order, so the concourse draws over the grounds. The
        /// concourse only joins in once you're zoomed into it — it comes with its own
        /// legend panel, which from a mile up is just a beige box over a field.
        func setIllustrations(_ shown: Bool, cameraDistance: Double,
                              on view: MKMapView, map: MapData) {
            let wanted = shown ? map.visibleLayers(at: cameraDistance) : []
            let wantedIDs = wanted.map(\.id)
            guard wantedIDs != overlays.map(\.layerID) else { return }

            view.removeOverlays(overlays)
            overlays = wanted.compactMap { layer in
                guard let image = UIImage(named: layer.asset) else { return nil }
                return IllustrationOverlay(layerID: layer.id,
                                           georeference: layer.georeference,
                                           image: image)
            }
            view.addOverlays(overlays, level: .aboveRoads)
        }

        func setAnnotations(_ placed: [PlacedPOI], on view: MKMapView) {
            let wanted = Set(placed.map(\.id))
            guard wanted != shownIDs else { return }
            shownIDs = wanted

            let stale = view.annotations.compactMap { $0 as? POIAnnotation }
                .filter { !wanted.contains($0.placed.id) }
            view.removeAnnotations(stale)

            let existing = Set(view.annotations.compactMap { ($0 as? POIAnnotation)?.placed.id })
            view.addAnnotations(placed.filter { !existing.contains($0.id) }.map(POIAnnotation.init))
        }

        func syncSelection(_ placed: PlacedPOI?, on view: MKMapView) {
            guard placed == nil else { return }
            for annotation in view.selectedAnnotations {
                view.deselectAnnotation(annotation, animated: true)
            }
        }

        func applyFocus(_ focus: MapFocus?, on view: MKMapView, map: MapData) {
            guard let focus, focus.token != lastFocusToken else { return }
            lastFocusToken = focus.token

            switch focus.target {
            case .user:
                // Recentre on the user when we have them and they're actually at the
                // site, otherwise frame the grounds again.
                if let location = view.userLocation.location,
                   map.primaryLayer.georeference.boundingRegion.contains(location.coordinate) {
                    view.setRegion(MKCoordinateRegion(center: location.coordinate,
                                                      latitudinalMeters: 400,
                                                      longitudinalMeters: 400), animated: true)
                } else {
                    view.setRegion(region(framing: map.primaryLayer), animated: true)
                }
            case .layer(let id):
                guard let layer = map.layer(id: id) else { return }
                view.setRegion(region(framing: layer), animated: true)
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
            (view as? POIAnnotationView)?.configure(for: poi.placed.poi)
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let poi = view.annotation as? POIAnnotation else { return }
            parent.selection = poi.placed
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            guard mapView.selectedAnnotations.isEmpty else { return }
            parent.selection = nil
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            parent.userLocation = userLocation.location
        }

        /// Camera height decides which layer's pins are worth showing. Bounced through the
        /// next runloop pass because our own `setRegion` can land here mid-update, and
        /// SwiftUI takes a dim view of state changing while it is rendering.
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            let distance = mapView.camera.centerCoordinateDistance
            guard abs(distance - parent.cameraDistance) > 25 else { return }
            DispatchQueue.main.async { [weak self] in
                self?.parent.cameraDistance = distance
            }
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            // Nothing to do — MKMapView starts the blue dot itself once we're allowed.
        }
    }
}

// MARK: - Illustration overlays

/// Draws a bundled illustration over the ground it depicts. The bounding rect is north-up
/// because MapKit insists, but the artwork itself is turned by the georeference's rotation
/// when it's drawn, which is how the concourse map — drawn 13° off north — lands on the
/// right fields.
private final class IllustrationOverlay: NSObject, MKOverlay {
    let layerID: String
    let image: UIImage
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    /// The artwork's own rect before rotation, centred on the same point.
    let unrotatedMapRect: MKMapRect
    let rotation: CGFloat

    init(layerID: String, georeference: MapGeoreference, image: UIImage) {
        self.layerID = layerID
        self.image = image
        self.coordinate = georeference.center
        self.rotation = CGFloat(georeference.rotation * .pi / 180)

        let bounds = georeference.boundingRegion
        let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: bounds.north,
                                                        longitude: bounds.west))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: bounds.south,
                                                            longitude: bounds.east))
        self.boundingMapRect = MKMapRect(x: topLeft.x, y: topLeft.y,
                                         width: bottomRight.x - topLeft.x,
                                         height: bottomRight.y - topLeft.y)

        let pointsPerMetre = MKMapPointsPerMeterAtLatitude(georeference.centerLatitude)
        let width = georeference.widthMeters * pointsPerMetre
        let height = georeference.heightMeters * pointsPerMetre
        let centre = MKMapPoint(georeference.center)
        self.unrotatedMapRect = MKMapRect(x: centre.x - width / 2, y: centre.y - height / 2,
                                          width: width, height: height)
        super.init()
    }
}

private final class IllustrationOverlayRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let illustration = overlay as? IllustrationOverlay,
              let cgImage = illustration.image.cgImage else { return }

        let rect = self.rect(for: illustration.unrotatedMapRect)
        let centre = CGPoint(x: rect.midX, y: rect.midY)

        context.saveGState()
        context.setAlpha(0.92)
        context.interpolationQuality = .high
        // Turn the artwork about its own centre…
        context.translateBy(x: centre.x, y: centre.y)
        context.rotate(by: illustration.rotation)
        context.translateBy(x: -centre.x, y: -centre.y)
        // …then undo Core Graphics' bottom-up image origin.
        context.translateBy(x: 0, y: rect.origin.y * 2 + rect.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: rect)
        context.restoreGState()
    }
}

// MARK: - Pins

private final class POIAnnotation: NSObject, MKAnnotation {
    let placed: PlacedPOI
    var coordinate: CLLocationCoordinate2D { placed.coordinate }
    var title: String? { placed.poi.name }
    var subtitle: String? { placed.poi.note }

    init(placed: PlacedPOI) {
        self.placed = placed
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
        displayPriority = poi.category.displayPriority
        canShowCallout = false
    }
}

private extension POICategory {
    /// Which pin survives when several land on the same patch of screen. The concourse
    /// packs sixty-odd of them into a few hundred metres, so the things you go looking
    /// for outrank the things you only want to see once you're standing next to them.
    var displayPriority: MKFeatureDisplayPriority {
        switch self {
        case .stage:
            return .required
        case .entrance, .gate, .medical, .food, .water, .restroom, .info, .accessibility:
            return .defaultHigh
        case .drink, .merch, .shade, .services, .camping, .parking, .exit:
            return .defaultLow
        }
    }
}
