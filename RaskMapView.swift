import SwiftUI
import MapKit
import Combine

struct RaskMapView: UIViewRepresentable {

    var countries: [Country]
    var features: [CountryFeature]
    var onCountryTapped: (Country) -> Void
    var highlightedIsoCode: String? = nil
    var onReady: ((_ center: @escaping (String) -> Void) -> Void)? = nil

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        context.coordinator.mapView = mapView
        context.coordinator.subscribeToColorChanges()

        mapView.mapType = .standard
        mapView.showsUserLocation = false
        mapView.isRotateEnabled = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsTraffic = false

        mapView.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 180)
        ), animated: false)
        let maxZoom: CLLocationDistance = 25_000_000   // ~20,000 km (impide ver demasiado “mundo” por rendimiento ya se verá)
          mapView.cameraZoomRange = MKMapView.CameraZoomRange(maxCenterCoordinateDistance: maxZoom)
        
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
            // Ajustar la región para encajar TODO el país (no solo el primer polígono)
            let rect = feature.boundingMapRect
            let padded = rect.insetBy(dx: -rect.size.width * 0.5, dy: -rect.size.height * 0.5)
            let minSize = MKMapSize(width: 13_000_000, height: 13_000_000)
            let finalRect = MKMapRect(
                x: padded.midX - max(padded.size.width,  minSize.width)  / 2,
                y: padded.midY - max(padded.size.height, minSize.height) / 2,
                width:  max(padded.size.width,  minSize.width),
                height: max(padded.size.height, minSize.height))
            mapView.setRegion(MKCoordinateRegion(finalRect), animated: true)
        })

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Siempre actualizar parent para que el coordinator tenga datos frescos
        context.coordinator.parent = self

        // ── 1. Añadir overlays la primera vez que llegan los features ──
        if mapView.overlays.isEmpty, !features.isEmpty {
            context.coordinator.lastKnownStatus =
                Dictionary(uniqueKeysWithValues: countries.map { ($0.isoCode, $0.status) })
            context.coordinator.lastHighlighted = highlightedIsoCode
            let allPolygons = features.flatMap { $0.polygons }
            mapView.addOverlays(allPolygons, level: .aboveRoads)

            let statusSnap = context.coordinator.lastKnownStatus
            let highlightSnap = highlightedIsoCode
            DispatchQueue.global(qos: .utility).async { [weak coordinator = context.coordinator] in
                var built: [(ObjectIdentifier, MKPolygonRenderer)] = []
                for polygon in allPolygons {
                    let pid = ObjectIdentifier(polygon)
                    let renderer = MKPolygonRenderer(polygon: polygon)
                    let status = statusSnap[polygon.isoCode] ?? .none
                    let isHighlighted = polygon.isoCode == highlightSnap
                    RaskMapView.applyStyle(status: status, to: renderer, highlighted: isHighlighted)
                    _ = renderer.path
                    built.append((pid, renderer))
                }
                DispatchQueue.main.async {
                    guard let coordinator else { return }
                    for (pid, r) in built where coordinator.rendererCache[pid] == nil {
                        coordinator.rendererCache[pid] = r
                    }
                }
            }
        }

        // ── 2. Actualizar highlight ──
        let newHighlight = highlightedIsoCode
        let oldHighlight = context.coordinator.lastHighlighted
        if newHighlight != oldHighlight {
            context.coordinator.lastHighlighted = newHighlight
            // Quitar highlight del anterior
            if let old = oldHighlight,
               let feature = features.first(where: { $0.isoCode == old }) {
                let status = context.coordinator.lastKnownStatus[old] ?? .none
                for polygon in feature.polygons {
                    let pid = ObjectIdentifier(polygon)
                    if let renderer = context.coordinator.rendererCache[pid] {
                        Self.applyStyle(status: status, to: renderer, highlighted: false)
                        renderer.setNeedsDisplay()
                    }
                }
            }
            // Aplicar highlight al nuevo
            if let new = newHighlight,
               let feature = features.first(where: { $0.isoCode == new }) {
                let status = context.coordinator.lastKnownStatus[new] ?? .none
                for polygon in feature.polygons {
                    let pid = ObjectIdentifier(polygon)
                    if let renderer = context.coordinator.rendererCache[pid] {
                        Self.applyStyle(status: status, to: renderer, highlighted: true)
                        renderer.setNeedsDisplay()
                    }
                }
            }
        }

        // ── 3. Actualizaciones de status ──
        let newMap = Dictionary(uniqueKeysWithValues: countries.map { ($0.isoCode, $0.status) })
        let oldMap = context.coordinator.lastKnownStatus
        guard newMap != oldMap else { return }
        context.coordinator.lastKnownStatus = newMap

        var changed = Set<String>()
        for (iso, s) in newMap where oldMap[iso] != s { changed.insert(iso) }
        for iso in oldMap.keys where newMap[iso] == nil { changed.insert(iso) }

        for isoCode in changed {
            guard let feature = features.first(where: { $0.isoCode == isoCode }) else { continue }
            let status = newMap[isoCode] ?? .none
            let isHighlighted = isoCode == context.coordinator.lastHighlighted
            for polygon in feature.polygons {
                let pid = ObjectIdentifier(polygon)
                if let renderer = context.coordinator.rendererCache[pid] {
                    Self.applyStyle(status: status, to: renderer, highlighted: isHighlighted)
                    renderer.setNeedsDisplay()
                } else {
                    mapView.removeOverlay(polygon)
                    mapView.addOverlay(polygon, level: .aboveRoads)
                }
            }
        }
    }

    static func applyStyle(status: CountryStatus, to renderer: MKPolygonRenderer, highlighted: Bool = false) {
        if status == .none {
            renderer.fillColor   = UIColor.clear
            renderer.strokeColor = highlighted ? UIColor.black.withAlphaComponent(0.85) : UIColor.clear
            renderer.lineWidth   = highlighted ? 1.0 : 0
        } else {
            renderer.fillColor   = status.overlayColor
            renderer.strokeColor = highlighted ? UIColor.black.withAlphaComponent(0.85) : UIColor.black.withAlphaComponent(0.35)
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
        private var colorCancellables = Set<AnyCancellable>()
        private var scrollWorkItem: DispatchWorkItem?
        weak var mapView: MKMapView?

        init(parent: RaskMapView) { self.parent = parent }

        func subscribeToColorChanges() {
            let theme = ColorThemeManager.shared
            Publishers.MergeMany(
                theme.$visitedColor.dropFirst().map { _ in () },
                theme.$wantToVisitColor.dropFirst().map { _ in () },
                theme.$livedColor.dropFirst().map { _ in () }
            )
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshRendererColors() }
            .store(in: &colorCancellables)
        }

        func refreshRendererColors() {
            guard let mapView else { return }
            for overlay in mapView.overlays {
                guard let polygon = overlay as? CountryPolygon,
                      let renderer = rendererCache[ObjectIdentifier(polygon)] else { continue }
                let status = lastKnownStatus[polygon.isoCode] ?? .none
                guard status != .none else { continue }
                let isHighlighted = polygon.isoCode == lastHighlighted
                renderer.fillColor = status.overlayColor
                if isHighlighted {
                    renderer.strokeColor = UIColor.black.withAlphaComponent(0.85)
                    renderer.lineWidth = 1.5
                } else {
                    renderer.strokeColor = UIColor.black.withAlphaComponent(0.35)
                    renderer.lineWidth = 0.5
                }
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

            let renderer = MKPolygonRenderer(polygon: polygon)
            let status = lastKnownStatus[polygon.isoCode]
                      ?? parent.countries.first { $0.isoCode == polygon.isoCode }?.status
                      ?? .none
            let isHighlighted = polygon.isoCode == lastHighlighted
            RaskMapView.applyStyle(status: status, to: renderer, highlighted: isHighlighted)
            rendererCache[pid] = renderer
            return renderer
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            scrollWorkItem?.cancel()
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            scrollWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                self.updateVisibleOverlays(in: mapView)
            }
            scrollWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
        }

        func updateVisibleOverlays(in mapView: MKMapView) {
            let visibleRect = mapView.visibleMapRect
            // Expandir ligeramente el rect para pre-cargar polígonos cercanos
            let expandedRect = visibleRect.insetBy(dx: -visibleRect.size.width * 0.3,
                                                   dy: -visibleRect.size.height * 0.3)
            let markedIsoCodes = Set(lastKnownStatus.filter { $0.value != .none }.keys)

            var target = Set<ObjectIdentifier>()
            var toAddPolygons: [CountryPolygon] = []
            for feature in parent.features {
                if markedIsoCodes.contains(feature.isoCode) ||
                   feature.boundingMapRect.intersects(expandedRect) {
                    for p in feature.polygons { target.insert(ObjectIdentifier(p)) }
                }
            }

            let current = mapView.overlays.compactMap { $0 as? CountryPolygon }
            let currentIDs = Set(current.map { ObjectIdentifier($0) })

            let toRemove = current.filter { !target.contains(ObjectIdentifier($0)) }
            if !toRemove.isEmpty { mapView.removeOverlays(toRemove) }

            let toAddIDs = target.subtracting(currentIDs)
            guard !toAddIDs.isEmpty else { return }

            for feature in parent.features {
                for p in feature.polygons where toAddIDs.contains(ObjectIdentifier(p)) {
                    toAddPolygons.append(p)
                }
            }

            // Pre-crear renderers y forzar el CGPath en background
            // para que cuando MapKit los pida en el render loop ya estén listos
            let statusSnapshot = lastKnownStatus
            let highlightSnapshot = lastHighlighted
            let cache = rendererCache
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var newRenderers: [(ObjectIdentifier, MKPolygonRenderer)] = []
                for polygon in toAddPolygons {
                    let pid = ObjectIdentifier(polygon)
                    guard cache[pid] == nil else { continue }
                    let renderer = MKPolygonRenderer(polygon: polygon)
                    let status = statusSnapshot[polygon.isoCode] ?? .none
                    let isHighlighted = polygon.isoCode == highlightSnapshot
                    RaskMapView.applyStyle(status: status, to: renderer, highlighted: isHighlighted)
                    _ = renderer.path
                    newRenderers.append((pid, renderer))
                }
                DispatchQueue.main.async { [weak self, weak mapView] in
                    guard let self, let mapView else { return }
                    for (pid, renderer) in newRenderers {
                        self.rendererCache[pid] = renderer
                    }
                    mapView.addOverlays(toAddPolygons, level: .aboveRoads)
                }
            }
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
                    guard let r = mapView.renderer(for: polygon) as? MKPolygonRenderer,
                          r.path?.contains(r.point(for: tapPoint)) == true else { continue }
                    // Buscar en parent.countries (siempre fresco)
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
