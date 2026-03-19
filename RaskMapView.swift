import SwiftUI
import MapKit
import Combine
import CoreLocation

struct RaskMapView: UIViewRepresentable {

    var countries: [Country]
    var features: [CountryFeature]
    var onCountryTapped: (Country) -> Void
    var highlightedIsoCode: String? = nil
    var showLived: Bool = true
    var showBucketList: Bool = true
    var locationIsoCode: String? = nil  // country where user currently is
    var onReady: ((_ center: @escaping (String) -> Void) -> Void)? = nil

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        context.coordinator.mapView = mapView
        context.coordinator.subscribeToColorChanges()

        mapView.mapType = .standard
        mapView.showsUserLocation = true
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsTraffic = false

        mapView.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 180)
        ), animated: false)
        mapView.cameraZoomRange = MKMapView.CameraZoomRange(maxCenterCoordinateDistance: 30_000_000)

        let tap = InstantTapGestureRecognizer(target: context.coordinator,
                                              action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan  = false
        tap.delaysTouchesEnded  = false
        mapView.addGestureRecognizer(tap)

        let coordinator = context.coordinator
        onReady?({ [weak mapView, weak coordinator] isoCode in
            guard let mapView, let coordinator,
                  let feature = coordinator.parent.features.first(where: { $0.isoCode == isoCode }) else { return }

            // For very large countries, cap zoom and use custom center if available
            let rect = feature.boundingMapRect
            let maxSpanDegrees = 40.0
            let region = MKCoordinateRegion(rect)
            let cappedSpan = MKCoordinateSpan(
                latitudeDelta:  min(region.span.latitudeDelta  * 1.5, maxSpanDegrees),
                longitudeDelta: min(region.span.longitudeDelta * 1.5, maxSpanDegrees)
            )
            // Use custom center for oversized countries
            let customCenters: [String: CLLocationCoordinate2D] = [
                "RUS": CLLocationCoordinate2D(latitude: 55.75, longitude: 37.62), // Moscow
                "CAN": CLLocationCoordinate2D(latitude: 56.13, longitude: -106.35),
                "USA": CLLocationCoordinate2D(latitude: 38.90, longitude: -97.00),
                "BRA": CLLocationCoordinate2D(latitude: -14.24, longitude: -51.93),
                "AUS": CLLocationCoordinate2D(latitude: -25.27, longitude: 133.78),
                "CHN": CLLocationCoordinate2D(latitude: 35.86, longitude: 104.19),
                "GRL": CLLocationCoordinate2D(latitude: 71.71, longitude: -42.60),
            ]
            let center = customCenters[isoCode] ?? region.center
            mapView.setRegion(MKCoordinateRegion(center: center, span: cappedSpan), animated: true)
        })

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coord = context.coordinator
        coord.parent = self

        guard !features.isEmpty else { return }

        // ── 1. Primera carga ──
        if !coord.initialLoadDone {
            coord.initialLoadDone = true
            let statusMap = Dictionary(uniqueKeysWithValues: countries.map { ($0.isoCode, $0.status) })
            coord.lastKnownStatus = statusMap
            coord.lastHighlighted = highlightedIsoCode

            let allPolygons = features.flatMap { $0.polygons }
            let statusSnap = statusMap
            let highlightSnap = highlightedIsoCode
            let showLivedSnap = showLived
            let showBucketSnap = showBucketList

            // Precalentar CGPaths en background — solo para países con color (los .none no necesitan path)
            let coloredIsoCodes = Self.coloredIsoCodes(from: statusMap,
                                                        showLived: showLivedSnap,
                                                        showBucketList: showBucketSnap)
            let coloredPolygons = allPolygons.filter { coloredIsoCodes.contains($0.isoCode) }

            DispatchQueue.global(qos: .userInitiated).async { [weak coordinator = coord] in
                var built: [(ObjectIdentifier, MKPolygonRenderer)] = []
                for polygon in coloredPolygons {
                    let pid = ObjectIdentifier(polygon)
                    let renderer = MKPolygonRenderer(polygon: polygon)
                    let status = statusSnap[polygon.isoCode] ?? .none
                    RaskMapView.applyStyle(status: status, to: renderer,
                                          highlighted: polygon.isoCode == highlightSnap,
                                          showLived: showLivedSnap, showBucketList: showBucketSnap)
                    _ = renderer.path
                    built.append((pid, renderer))
                }
                DispatchQueue.main.async { [weak coordinator] in
                    guard let coordinator else { return }
                    for (pid, r) in built where coordinator.rendererCache[pid] == nil {
                        coordinator.rendererCache[pid] = r
                    }
                }
            }

            // Añadir TODOS los overlays — necesario para tap y highlight en países .none
            mapView.addOverlays(allPolygons, level: .aboveRoads)
            return
        }

        // ── 1b. Actualizar location iso ──
        let newLocationIso = locationIsoCode
        let oldLocationIso = coord.lastLocationIso
        if newLocationIso != oldLocationIso {
            coord.lastLocationIso = newLocationIso
            // Refresh old location country
            if let old = oldLocationIso, let feature = features.first(where: { $0.isoCode == old }) {
                let status = coord.lastKnownStatus[old] ?? .none
                let isHL = old == coord.lastHighlighted
                for polygon in feature.polygons {
                    if let renderer = coord.rendererCache[ObjectIdentifier(polygon)] {
                        Self.applyStyle(status: status, to: renderer, highlighted: isHL,
                                        showLived: showLived, showBucketList: showBucketList,
                                        isUserHere: false)
                        renderer.setNeedsDisplay()
                    }
                }
            }
            // Refresh new location country
            if let new = newLocationIso, let feature = features.first(where: { $0.isoCode == new }) {
                let status = coord.lastKnownStatus[new] ?? .none
                let isHL = new == coord.lastHighlighted
                for polygon in feature.polygons {
                    let pid = ObjectIdentifier(polygon)
                    if coord.rendererCache[pid] == nil {
                        let renderer = MKPolygonRenderer(polygon: polygon)
                        Self.applyStyle(status: status, to: renderer, highlighted: isHL,
                                        showLived: showLived, showBucketList: showBucketList,
                                        isUserHere: true)
                        coord.rendererCache[pid] = renderer
                        mapView.removeOverlay(polygon)
                        mapView.addOverlay(polygon, level: .aboveRoads)
                    } else if let renderer = coord.rendererCache[pid] {
                        Self.applyStyle(status: status, to: renderer, highlighted: isHL,
                                        showLived: showLived, showBucketList: showBucketList,
                                        isUserHere: true)
                        renderer.setNeedsDisplay()
                    }
                }
            }
        }

        // ── 2. Actualizar highlight ──
        let newHighlight = highlightedIsoCode
        let oldHighlight = coord.lastHighlighted
        if newHighlight != oldHighlight {
            coord.lastHighlighted = newHighlight
            if let old = oldHighlight,
               let feature = features.first(where: { $0.isoCode == old }) {
                let status = coord.lastKnownStatus[old] ?? .none
                for polygon in feature.polygons {
                    if let renderer = coord.rendererCache[ObjectIdentifier(polygon)] {
                        Self.applyStyle(status: status, to: renderer, highlighted: false,
                                        showLived: showLived, showBucketList: showBucketList)
                        renderer.setNeedsDisplay()
                    }
                }
                // País .none — el overlay sigue en el mapa, solo actualizar renderer
                if status == .none {
                    for polygon in feature.polygons {
                        coord.rendererCache.removeValue(forKey: ObjectIdentifier(polygon))
                    }
                }
            }
            if let new = newHighlight,
               let feature = features.first(where: { $0.isoCode == new }) {
                let status = coord.lastKnownStatus[new] ?? .none
                for polygon in feature.polygons {
                    let pid = ObjectIdentifier(polygon)
                    // Si es .none, añadir temporalmente para mostrar el borde
                    if coord.rendererCache[pid] == nil {
                        let renderer = MKPolygonRenderer(polygon: polygon)
                        Self.applyStyle(status: status, to: renderer, highlighted: true,
                                        showLived: showLived, showBucketList: showBucketList)
                        _ = renderer.path
                        coord.rendererCache[pid] = renderer
                        // Overlay ya existe — solo invalidar para que MapKit pida el renderer
                        mapView.removeOverlay(polygon)
                        mapView.addOverlay(polygon, level: .aboveRoads)
                    } else if let renderer = coord.rendererCache[pid] {
                        Self.applyStyle(status: status, to: renderer, highlighted: true,
                                        showLived: showLived, showBucketList: showBucketList)
                        renderer.setNeedsDisplay()
                    }
                }
            }
            else if newHighlight == nil, let locIso = coord.lastLocationIso,
                      let feature = features.first(where: { $0.isoCode == locIso }) {
                let status = coord.lastKnownStatus[locIso] ?? .none
                for polygon in feature.polygons {
                    let pid = ObjectIdentifier(polygon)
                    if let renderer = coord.rendererCache[pid] {
                        Self.applyStyle(status: status, to: renderer, highlighted: false,
                                        showLived: showLived, showBucketList: showBucketList,
                                        isUserHere: true)
                        renderer.setNeedsDisplay()
                    } else {
                        let renderer = MKPolygonRenderer(polygon: polygon)
                        Self.applyStyle(status: status, to: renderer, highlighted: false,
                                        showLived: showLived, showBucketList: showBucketList,
                                        isUserHere: true)
                        coord.rendererCache[pid] = renderer
                        mapView.removeOverlay(polygon)
                        mapView.addOverlay(polygon, level: .aboveRoads)
                    }
                }
            }
        }

        // ── 3. Actualizaciones de status — solo diff ──
        let newMap = Dictionary(uniqueKeysWithValues: countries.map { ($0.isoCode, $0.status) })
        let oldMap = coord.lastKnownStatus
        guard newMap != oldMap else { return }
        coord.lastKnownStatus = newMap

        var changed = Set<String>()
        for (iso, s) in newMap where oldMap[iso] != s { changed.insert(iso) }
        for iso in oldMap.keys where newMap[iso] == nil { changed.insert(iso) }

        let showLivedSnap = showLived
        let showBucketSnap = showBucketList

        for isoCode in changed {
            guard let feature = features.first(where: { $0.isoCode == isoCode }) else { continue }
            let newStatus = newMap[isoCode] ?? .none
            let oldStatus = oldMap[isoCode] ?? .none
            let isHighlighted = isoCode == coord.lastHighlighted
            let isNowColored = Self.isColored(newStatus, showLived: showLivedSnap, showBucketList: showBucketSnap)
            let wasColored   = Self.isColored(oldStatus, showLived: showLivedSnap, showBucketList: showBucketSnap)

            for polygon in feature.polygons {
                let pid = ObjectIdentifier(polygon)
                if isNowColored {
                    if let renderer = coord.rendererCache[pid] {
                        // Ya existe — solo actualizar color
                        Self.applyStyle(status: newStatus, to: renderer, highlighted: isHighlighted,
                                        showLived: showLivedSnap, showBucketList: showBucketSnap)
                        renderer.setNeedsDisplay()
                    } else {
                        // Añadir nuevo overlay para este país
                        let renderer = MKPolygonRenderer(polygon: polygon)
                        Self.applyStyle(status: newStatus, to: renderer, highlighted: isHighlighted,
                                        showLived: showLivedSnap, showBucketList: showBucketSnap)
                        coord.rendererCache[pid] = renderer
                        DispatchQueue.global(qos: .userInitiated).async {
                            _ = renderer.path
                            DispatchQueue.main.async { mapView.addOverlay(polygon, level: .aboveRoads) }
                        }
                    }
                } else if wasColored && !isHighlighted {
                    // Pasó a .none — quitar del cache para que MapKit pida renderer limpio
                    coord.rendererCache.removeValue(forKey: pid)
                    mapView.removeOverlay(polygon)
                    mapView.addOverlay(polygon, level: .aboveRoads)
                } else if let renderer = coord.rendererCache[pid] {
                    Self.applyStyle(status: newStatus, to: renderer, highlighted: isHighlighted,
                                    showLived: showLivedSnap, showBucketList: showBucketSnap)
                    renderer.setNeedsDisplay()
                }
            }
        }
    }

    // ── Helpers ──

    private static func isColored(_ status: CountryStatus, showLived: Bool, showBucketList: Bool) -> Bool {
        switch status {
        case .none:        return false
        case .visited:     return true
        case .wantToVisit: return true
        case .lived:       return showLived
        case .bucketList:  return showBucketList
        }
    }

    private static func coloredIsoCodes(from statusMap: [String: CountryStatus],
                                         showLived: Bool, showBucketList: Bool) -> Set<String> {
        Set(statusMap.filter { isColored($0.value, showLived: showLived, showBucketList: showBucketList) }.keys)
    }

    static func applyStyle(status: CountryStatus, to renderer: MKPolygonRenderer,
                            highlighted: Bool = false,
                            showLived: Bool = true, showBucketList: Bool = true,
                            isUserHere: Bool = false) {
        let effective: CountryStatus = {
            if status == .lived      && !showLived      { return .none }
            if status == .bucketList && !showBucketList { return .none }
            return status
        }()
        if effective == .none && !isUserHere {
            renderer.fillColor   = UIColor.clear
            renderer.strokeColor = highlighted ? UIColor.black.withAlphaComponent(0.85) : UIColor.clear
            renderer.lineWidth   = highlighted ? 1.0 : 0
        } else if isUserHere {
            // User is physically in this country — translucent fill, colored border
            let base = effective != .none ? effective.overlayColor : CountryStatus.visited.overlayColor
            renderer.fillColor   = base.withAlphaComponent(0.45)
            renderer.strokeColor = base
            renderer.lineWidth   = 2.5
        } else {
            renderer.fillColor   = effective.overlayColor
            renderer.strokeColor = highlighted
                ? UIColor.black.withAlphaComponent(0.85)
                : UIColor.black.withAlphaComponent(0.35)
            renderer.lineWidth   = highlighted ? 1.5 : 0.5
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    // MARK: - Coordinator
    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: RaskMapView
        var rendererCache: [ObjectIdentifier: MKPolygonRenderer] = [:]
        var lastKnownStatus: [String: CountryStatus] = [:]
        var lastHighlighted: String? = nil
        var lastLocationIso: String? = nil
        var initialLoadDone = false
        private var colorCancellables = Set<AnyCancellable>()
        weak var mapView: MKMapView?

        init(parent: RaskMapView) { self.parent = parent }

        func subscribeToColorChanges() {
            let theme = ColorThemeManager.shared
            Publishers.MergeMany(
                theme.$visitedColor.dropFirst().map { _ in () },
                theme.$wantToVisitColor.dropFirst().map { _ in () },
                theme.$livedColor.dropFirst().map { _ in () },
                theme.$bucketListColor.dropFirst().map { _ in () }
            )
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshRendererColors() }
            .store(in: &colorCancellables)
        }

        func refreshRendererColors() {
            for (_, renderer) in rendererCache {
                guard let polygon = renderer.polygon as? CountryPolygon else { continue }
                let status = lastKnownStatus[polygon.isoCode] ?? .none
                guard status != .none else { continue }
                let isHighlighted = polygon.isoCode == lastHighlighted
                let isUserHere = polygon.isoCode == parent.locationIsoCode
                RaskMapView.applyStyle(status: status, to: renderer,
                                       highlighted: isHighlighted,
                                       showLived: parent.showLived,
                                       showBucketList: parent.showBucketList,
                                       isUserHere: isUserHere)
                renderer.setNeedsDisplay()
            }
        }

        func visibleCountries(for mapView: MKMapView) -> [CountryFeature] {
            let r = mapView.visibleMapRect
            return parent.features.filter { $0.boundingMapRect.intersects(r) }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polygon = overlay as? CountryPolygon else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let pid = ObjectIdentifier(polygon)
            if let cached = rendererCache[pid] { return cached }
            // Fallback — debería estar en cache desde el precalentado
            let renderer = MKPolygonRenderer(polygon: polygon)
            let status = lastKnownStatus[polygon.isoCode]
                      ?? parent.countries.first { $0.isoCode == polygon.isoCode }?.status
                      ?? .none
            RaskMapView.applyStyle(status: status, to: renderer,
                                   highlighted: polygon.isoCode == lastHighlighted,
                                   showLived: parent.showLived,
                                   showBucketList: parent.showBucketList,
                                   isUserHere: polygon.isoCode == parent.locationIsoCode)
            rendererCache[pid] = renderer
            return renderer
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {}
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {}

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let userLoc = annotation as? MKUserLocation else { return nil }
            userLoc.title = ""
            userLoc.subtitle = ""
            let id = "userLocationView"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKUserLocationView
                ?? MKUserLocationView(annotation: userLoc, reuseIdentifier: id)
            view.canShowCallout = false
            return view
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            userLocation.title = ""
            userLocation.subtitle = ""
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldReceive t: UITouch) -> Bool { true }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let tapPoint = MKMapPoint(mapView.convert(gesture.location(in: mapView),
                                                      toCoordinateFrom: mapView))
            let candidates = visibleCountries(for: mapView)
                .filter { $0.boundingMapRect.contains(tapPoint) }
                .sorted {
                    $0.boundingMapRect.size.width * $0.boundingMapRect.size.height <
                    $1.boundingMapRect.size.width * $1.boundingMapRect.size.height
                }

            for country in candidates {
                for polygon in country.polygons {
                    // Use cached renderer if available, otherwise create a temporary one for hit-test
                    let pid = ObjectIdentifier(polygon)
                    let renderer: MKPolygonRenderer
                    if let cached = rendererCache[pid] {
                        renderer = cached
                    } else {
                        renderer = MKPolygonRenderer(polygon: polygon)
                        // Force path computation synchronously for hit-test
                        renderer.invalidatePath()
                    }
                    guard renderer.path?.contains(renderer.point(for: tapPoint)) == true else { continue }
                    let result = parent.countries.first { $0.isoCode == polygon.isoCode }
                              ?? Country(name: polygon.countryName, isoCode: polygon.isoCode)
                    parent.onCountryTapped(result)
                    return
                }
            }
        }
    }
}

private class InstantTapGestureRecognizer: UITapGestureRecognizer {
    private var start: CGPoint = .zero
    override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent) {
        super.touchesBegan(t, with: e); start = t.first?.location(in: view) ?? .zero
    }
    override func touchesMoved(_ t: Set<UITouch>, with e: UIEvent) {
        super.touchesMoved(t, with: e)
        guard let c = t.first?.location(in: view) else { return }
        if hypot(c.x - start.x, c.y - start.y) > 10 { state = .failed }
    }
}

