import SwiftUI
import MapKit
import Combine
import CoreLocation

struct RaskMapView: UIViewRepresentable {

    var countries: [Country]
    var features: [CountryFeature]
    var onCountryTapped: (Country) -> Void
    var highlightedIsoCode: String? = nil
    var showBucketList: Bool = true
    var locationIsoCode: String? = nil  // country where user currently is
    var onReady: ((_ center: @escaping (String) -> Void) -> Void)? = nil
    var flightMode: Bool = false
    var flightRouteFilter: FlightRouteFilter = .past
    var trips: [Trip] = []
    /// Filtro visual aplicado al mapa. Cuando es `.all`, render normal. Para
    /// el resto, los países cuyo status no matchea se pintan transparentes
    /// (status efectivo `.none`). La transformación se hace al construir el
    /// statusMap; el resto del pipeline de diff/render funciona igual.
    var mapFilter: MapFilter = .all

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
        // Sin cameraZoomRange: el usuario quiere poder hacer zoom-out sin tope.

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
                "RUS": CLLocationCoordinate2D(latitude: 55.75, longitude: 37.62),
                "CAN": CLLocationCoordinate2D(latitude: 56.13, longitude: -106.35),
                "USA": CLLocationCoordinate2D(latitude: 38.90, longitude: -97.00),
                "BRA": CLLocationCoordinate2D(latitude: -14.24, longitude: -51.93),
                "AUS": CLLocationCoordinate2D(latitude: -25.27, longitude: 133.78),
                "CHN": CLLocationCoordinate2D(latitude: 35.86, longitude: 104.19),
                "GRL": CLLocationCoordinate2D(latitude: 71.71, longitude: -42.60),
                "NOR": CLLocationCoordinate2D(latitude: 59.91, longitude: 10.75),   // Oslo
                "NZL": CLLocationCoordinate2D(latitude: -36.86, longitude: 174.76), // Auckland
                "REU": CLLocationCoordinate2D(latitude: -21.13, longitude: 55.54),  // Saint-Denis
                "GLP": CLLocationCoordinate2D(latitude: 16.25, longitude: -61.55),  // Basse-Terre
                "MTQ": CLLocationCoordinate2D(latitude: 14.64, longitude: -61.02),  // Fort-de-France
                "GUF": CLLocationCoordinate2D(latitude: 4.93, longitude: -52.33),   // Cayenne
                "MYT": CLLocationCoordinate2D(latitude: -12.78, longitude: 45.23),  // Mamoudzou
                "CHL": CLLocationCoordinate2D(latitude: -33.45, longitude: -70.67), // Santiago
                "FRA": CLLocationCoordinate2D(latitude: 48.85, longitude: 2.35),    // Paris
                "NLD": CLLocationCoordinate2D(latitude: 52.38, longitude: 4.90),    // Amsterdam
                "FJI": CLLocationCoordinate2D(latitude: -18.14, longitude: 178.44), // Suva
                "KIR": CLLocationCoordinate2D(latitude:  1.33, longitude: 172.98),  // South Tarawa
                "MHL": CLLocationCoordinate2D(latitude:  7.09, longitude: 171.38),  // Majuro
                "MUS": CLLocationCoordinate2D(latitude: -20.15, longitude: 57.49),  // Port Louis
                "COK": CLLocationCoordinate2D(latitude: -21.21, longitude: -159.78), // Avarua
                "ATA": CLLocationCoordinate2D(latitude: -70.75, longitude:  44.33), // Mizuho Plateau
            ]
            let customSpans: [String: MKCoordinateSpan] = [
                "KIR": MKCoordinateSpan(latitudeDelta: 2.5, longitudeDelta: 2.5),
                "MHL": MKCoordinateSpan(latitudeDelta: 2.5, longitudeDelta: 2.5),
                "MUS": MKCoordinateSpan(latitudeDelta: 3.0, longitudeDelta: 3.0),
            ]
            let center = customCenters[isoCode] ?? region.center
            let span = customSpans[isoCode] ?? cappedSpan
            mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: true)
        })

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coord = context.coordinator
        coord.parent = self


        guard !features.isEmpty else { return }

        // ── Flight mode toggle ──
        if flightMode != coord.lastFlightMode {
            coord.lastFlightMode = flightMode
            coord.lastFlightRouteFilter = flightRouteFilter
            if flightMode {
                coord.enterFlightMode(mapView: mapView, trips: trips, filter: flightRouteFilter)
            } else {
                coord.exitFlightMode(mapView: mapView)
            }
            return
        }
        // Si estamos en modo vuelos y cambian filtro o trips, recalcular
        if flightMode {
            if flightRouteFilter != coord.lastFlightRouteFilter {
                coord.lastFlightRouteFilter = flightRouteFilter
                coord.rebuildFlightOverlays(mapView: mapView, trips: trips, filter: flightRouteFilter)
            } else {
                coord.refreshFlightOverlaysIfNeeded(mapView: mapView, trips: trips, filter: flightRouteFilter)
            }
            return
        }

        // ── 1. Primera carga ──
        if !coord.initialLoadDone {
            coord.initialLoadDone = true
            // Aplica `mapFilter` para que los países que no matcheen el
            // filtro queden como `.none` (transparentes). El filtro activo
            // se cachea en `coord.lastMapFilter` para detectar cambios en
            // updateUIView siguientes. Para filtros .transport pasamos
            // los trips agrupados por isoCode (necesitamos saber qué
            // transports usa cada país).
            coord.lastMapFilter = mapFilter
            let tripsByIso = Dictionary(grouping: trips, by: { $0.isoCode })
            let statusMap = Dictionary(uniqueKeysWithValues: countries.map { c in
                (c.isoCode, mapFilter.effectiveStatus(c.status, tripsForCountry: tripsByIso[c.isoCode] ?? []))
            })
            coord.lastKnownStatus = statusMap
            coord.lastHighlighted = highlightedIsoCode

            let allPolygons = features.flatMap { $0.polygons }
            let statusSnap = statusMap
            let highlightSnap = highlightedIsoCode
            let showBucketSnap = showBucketList

            // CAMBIO CLAVE para reducir flicker en pan: solo registramos como
            // overlays los polígonos COLOREADOS (visited/lived/wantToVisit/
            // bucketList si toggle on) + el highlight actual si es .none.
            // Antes añadíamos los ~1000+ polígonos como overlays y MapKit
            // los re-rasterizaba por tile en cada pan; ahora solo procesa
            // ~5-30 polígonos (los del usuario), reduciendo drásticamente
            // el coste de renderizado por tile.
            // Tap-detection sigue funcionando — usa `features` directamente,
            // no la lista de overlays (ver handleTap).
            let coloredIsos = Self.coloredIsoCodes(from: statusMap, showBucketList: showBucketSnap)
            var activeIsos = coloredIsos
            if let hl = highlightSnap, !activeIsos.contains(hl) {
                activeIsos.insert(hl)  // .none country highlighted: añadir temporalmente
            }
            let activePolygons = allPolygons.filter { activeIsos.contains($0.isoCode) }
            coord.activeOverlayIsos = activeIsos

            // Pre-warm en background SOLO para polígonos activos. Path
            // computado offline para que el primer draw del tile sea rápido.
            DispatchQueue.global(qos: .utility).async { [weak coordinator = coord] in
                var built: [(ObjectIdentifier, MKPolygonRenderer)] = []
                built.reserveCapacity(activePolygons.count)
                for polygon in activePolygons {
                    let pid = ObjectIdentifier(polygon)
                    let renderer = MKPolygonRenderer(polygon: polygon)
                    let status = statusSnap[polygon.isoCode] ?? .none
                    RaskMapView.applyStyle(status: status, to: renderer,
                                          highlighted: polygon.isoCode == highlightSnap,
                                          showBucketList: showBucketSnap)
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

            mapView.addOverlays(activePolygons, level: .aboveRoads)
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
                                        showBucketList: showBucketList,
                                        isUserHere: false)
                        renderer.setNeedsDisplay()
                    }
                }
            }
            // Refresh new location country. Como ahora el pre-warm cubre TODOS
            // los polígonos, el branch "cache nil" es solo un fallback para
            // la race window entre `mapView.addOverlays` y la finalización del
            // pre-warm; ya no hacemos remove+add (causa flicker de tiles).
            if let new = newLocationIso, let feature = features.first(where: { $0.isoCode == new }) {
                let status = coord.lastKnownStatus[new] ?? .none
                let isHL = new == coord.lastHighlighted
                for polygon in feature.polygons {
                    let pid = ObjectIdentifier(polygon)
                    let renderer: MKPolygonRenderer
                    if let cached = coord.rendererCache[pid] {
                        renderer = cached
                    } else {
                        renderer = MKPolygonRenderer(polygon: polygon)
                        coord.rendererCache[pid] = renderer
                    }
                    Self.applyStyle(status: status, to: renderer, highlighted: isHL,
                                    showBucketList: showBucketList,
                                    isUserHere: true)
                    renderer.setNeedsDisplay()
                }
            }
        }

        // ── 2. Actualizar highlight ──
        // Si el destacado es un país .none, hay que añadirlo TEMPORALMENTE al
        // mapa como overlay (con stroke pero sin fill). Al perder el destacado
        // se elimina del mapa para volver al estado óptimo (solo coloreados).
        let newHighlight = highlightedIsoCode
        let oldHighlight = coord.lastHighlighted
        if newHighlight != oldHighlight {
            coord.lastHighlighted = newHighlight
            // OLD highlight: si era .none y no es coloreado, quitar del mapa.
            if let old = oldHighlight,
               let feature = features.first(where: { $0.isoCode == old }) {
                let status = coord.lastKnownStatus[old] ?? .none
                let stillActive = Self.isColored(status, showBucketList: showBucketList)
                for polygon in feature.polygons {
                    if let renderer = coord.rendererCache[ObjectIdentifier(polygon)] {
                        Self.applyStyle(status: status, to: renderer, highlighted: false,
                                        showBucketList: showBucketList)
                        renderer.setNeedsDisplay()
                    }
                }
                if !stillActive {
                    coord.activeOverlayIsos.remove(old)
                    mapView.removeOverlays(feature.polygons)
                    for polygon in feature.polygons {
                        coord.rendererCache.removeValue(forKey: ObjectIdentifier(polygon))
                    }
                }
            }
            // NEW highlight: si no estaba en el mapa, añadir overlay.
            if let new = newHighlight,
               let feature = features.first(where: { $0.isoCode == new }) {
                let status = coord.lastKnownStatus[new] ?? .none
                let needsAdd = !coord.activeOverlayIsos.contains(new)
                if needsAdd {
                    coord.activeOverlayIsos.insert(new)
                    // Crear renderers en cache antes de addOverlays para que
                    // mapView(_:rendererFor:) tenga el cache hit al primer draw.
                    for polygon in feature.polygons {
                        let pid = ObjectIdentifier(polygon)
                        let renderer = MKPolygonRenderer(polygon: polygon)
                        Self.applyStyle(status: status, to: renderer, highlighted: true,
                                        showBucketList: showBucketList)
                        _ = renderer.path
                        coord.rendererCache[pid] = renderer
                    }
                    mapView.addOverlays(feature.polygons, level: .aboveRoads)
                } else {
                    for polygon in feature.polygons {
                        let pid = ObjectIdentifier(polygon)
                        if let renderer = coord.rendererCache[pid] {
                            Self.applyStyle(status: status, to: renderer, highlighted: true,
                                            showBucketList: showBucketList)
                            renderer.setNeedsDisplay()
                        }
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
                                        showBucketList: showBucketList,
                                        isUserHere: true)
                        renderer.setNeedsDisplay()
                    }
                }
            }
        }

        // ── 3. Actualizaciones de status — solo diff ──
        // Aplica `mapFilter`: si el filtro cambió, esta línea ya genera un
        // newMap diferente al lastKnownStatus → el diff de abajo detecta los
        // países que han ganado/perdido color y re-renderiza solo esos.
        // Para .transport agrupamos trips por isoCode para que el filtro
        // pueda chequear qué transports usa cada país.
        coord.lastMapFilter = mapFilter
        let tripsByIso = Dictionary(grouping: trips, by: { $0.isoCode })
        let newMap = Dictionary(uniqueKeysWithValues: countries.map { c in
            (c.isoCode, mapFilter.effectiveStatus(c.status, tripsForCountry: tripsByIso[c.isoCode] ?? []))
        })
        let oldMap = coord.lastKnownStatus
        guard newMap != oldMap else { return }
        coord.lastKnownStatus = newMap

        var changed = Set<String>()
        for (iso, s) in newMap where oldMap[iso] != s { changed.insert(iso) }
        for iso in oldMap.keys where newMap[iso] == nil { changed.insert(iso) }

        
        let showBucketSnap = showBucketList

        for isoCode in changed {
            guard let feature = features.first(where: { $0.isoCode == isoCode }) else { continue }
            let newStatus = newMap[isoCode] ?? .none
            let isHighlighted = isoCode == coord.lastHighlighted
            let isNowActive = Self.isColored(newStatus, showBucketList: showBucketSnap) || isHighlighted
            let wasActive = coord.activeOverlayIsos.contains(isoCode)

            if isNowActive && !wasActive {
                // ⇢ Añadir el país al mapa (estaba .none, ahora coloreado).
                coord.activeOverlayIsos.insert(isoCode)
                for polygon in feature.polygons {
                    let pid = ObjectIdentifier(polygon)
                    let renderer = MKPolygonRenderer(polygon: polygon)
                    Self.applyStyle(status: newStatus, to: renderer, highlighted: isHighlighted,
                                    showBucketList: showBucketSnap)
                    coord.rendererCache[pid] = renderer
                    DispatchQueue.global(qos: .userInitiated).async {
                        _ = renderer.path
                        DispatchQueue.main.async { mapView.addOverlay(polygon, level: .aboveRoads) }
                    }
                }
            } else if !isNowActive && wasActive {
                // ⇠ Quitar el país del mapa (pasó a .none y sin highlight).
                coord.activeOverlayIsos.remove(isoCode)
                mapView.removeOverlays(feature.polygons)
                for polygon in feature.polygons {
                    coord.rendererCache.removeValue(forKey: ObjectIdentifier(polygon))
                }
            } else if wasActive {
                // Cambio de color entre estados coloreados (visited ↔ wantToVisit, etc.).
                for polygon in feature.polygons {
                    let pid = ObjectIdentifier(polygon)
                    if let renderer = coord.rendererCache[pid] {
                        Self.applyStyle(status: newStatus, to: renderer, highlighted: isHighlighted,
                                        showBucketList: showBucketSnap)
                        renderer.setNeedsDisplay()
                    }
                }
            }
        }
    }

    // ── Helpers ──

    private static func isColored(_ status: CountryStatus, showBucketList: Bool) -> Bool {
        switch status {
        case .none:        return false
        case .visited:     return true
        case .lived:       return true
        case .wantToVisit: return true
        case .bucketList:  return showBucketList
        }
    }

    private static func coloredIsoCodes(from statusMap: [String: CountryStatus],
                                          showBucketList: Bool) -> Set<String> {
        Set(statusMap.filter { isColored($0.value, showBucketList: showBucketList) }.keys)
    }

    static func applyStyle(status: CountryStatus, to renderer: MKPolygonRenderer,
                            highlighted: Bool = false,
                            showBucketList: Bool = true,
                            isUserHere: Bool = false) {
        let isAntarctica = (renderer.polygon as? CountryPolygon)?.isoCode == "ATA"
        let effective: CountryStatus = {
            if status == .lived                        { return .visited }
            if status == .bucketList && !showBucketList { return .none }
            return status
        }()
        if effective == .none && !isUserHere {
            renderer.fillColor   = UIColor.clear
            renderer.strokeColor = (highlighted && !isAntarctica) ? UIColor.black.withAlphaComponent(0.85) : UIColor.clear
            renderer.lineWidth   = (highlighted && !isAntarctica) ? 1.0 : 0
        } else if isUserHere {
            let base = effective != .none ? effective.overlayColor : CountryStatus.visited.overlayColor
            renderer.fillColor   = base.withAlphaComponent(0.45)
            renderer.strokeColor = base
            renderer.lineWidth   = 2.5
        } else {
            renderer.fillColor   = effective.overlayColor
            if isAntarctica {
                renderer.strokeColor = UIColor.clear
                renderer.lineWidth   = 0
            } else if highlighted {
                renderer.strokeColor = UIColor.black.withAlphaComponent(0.85)
                renderer.lineWidth   = 1.0
            } else {
                renderer.strokeColor = UIColor.clear
                renderer.lineWidth   = 0
            }
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
        /// Filtro de mapa activo en el último render. Usado para detectar
        /// cuándo el user cambia de filtro (p.ej. "Todos" → "Solo visitados")
        /// y disparar un re-render del statusMap completo.
        var lastMapFilter: MapFilter = .all
        /// ISOs cuyos polígonos están ACTUALMENTE registrados como overlays
        /// en el MKMapView. Subset de `features` — solo coloreados +
        /// (opcionalmente) el highlight actual si es .none. Mantener este set
        /// sincronizado evita el flicker en pan: MapKit solo re-rasteriza
        /// estos overlays por tile.
        var activeOverlayIsos: Set<String> = []
        private var colorCancellables = Set<AnyCancellable>()
        weak var mapView: MKMapView?

        /// Fallback reutilizable para taps en la Antártida cuando aún no está en `parent.countries`.
        static let antarcticaFallback = Country(name: "Antarctica", isoCode: "ATA")

        // Flight mode
        var lastFlightMode: Bool = false
        var lastFlightRouteFilter: FlightRouteFilter = .past
        var flightRouteOverlays: [MKGeodesicPolyline] = []
        var airportAnnotations: [AirportDotAnnotation] = []
        var lastFlightRoutes: Set<FlightRoutePair> = []
        var lastFlightAirports: Set<String> = []

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
            guard let mv = mapView else { return }
            let visibleRect = mv.visibleMapRect
            let visibleISOs = Set(parent.features
                .filter { $0.boundingMapRect.intersects(visibleRect) }
                .map { $0.isoCode })

            // Wrap en CATransaction con actions disabled para que CoreAnimation
            // NO genere implicit animations en cada `setNeedsDisplay`. Antes
            // cambiar 4 colores a la vez (p.ej. "Restablecer colores") hacía
            // que MapKit re-rasterizara las tiles del mapa con un flash
            // visible, como si todo Apple Maps recargara. Con esta wrap la
            // actualización es instantánea sin transición ni flicker.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }

            for (_, renderer) in rendererCache {
                guard let polygon = renderer.polygon as? CountryPolygon else { continue }
                let status = lastKnownStatus[polygon.isoCode] ?? .none
                guard status != .none else { continue }
                let isHighlighted = polygon.isoCode == lastHighlighted
                let isUserHere = polygon.isoCode == parent.locationIsoCode
                RaskMapView.applyStyle(status: status, to: renderer,
                                       highlighted: isHighlighted,
                                       showBucketList: parent.showBucketList,
                                       isUserHere: isUserHere)
                // Only force immediate redraw for currently visible polygons.
                // Non-visible ones have their fillColor updated and will render
                // with the new color when the user pans to them.
                if visibleISOs.contains(polygon.isoCode) {
                    renderer.setNeedsDisplay()
                }
            }
        }

        func visibleCountries(for mapView: MKMapView) -> [CountryFeature] {
            let r = mapView.visibleMapRect
            return parent.features.filter { $0.boundingMapRect.intersects(r) }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let route = overlay as? MKGeodesicPolyline,
               flightRouteOverlays.contains(where: { $0 === route }) {
                let renderer = MKPolylineRenderer(polyline: route)
                let accent = BrandColor.accentUI
                renderer.strokeColor = accent.withAlphaComponent(0.85)
                renderer.lineWidth = 1.6
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            guard let polygon = overlay as? CountryPolygon else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let pid = ObjectIdentifier(polygon)
            if let cached = rendererCache[pid] {
                if parent.flightMode {
                    cached.fillColor = .clear
                    cached.strokeColor = .clear
                }
                return cached
            }
            // Fallback — debería estar en cache desde el precalentado.
            // Solo cacheamos si el polígono está en `activeOverlayIsos` (es decir,
            // realmente lo queremos en el mapa). En otro caso devolvemos el
            // renderer sin cachear: previene leaks ante requests de MapKit por
            // overlays que ya quitamos. Cap natural del cache = |activeOverlayIsos|.
            let renderer = MKPolygonRenderer(polygon: polygon)
            if parent.flightMode {
                renderer.fillColor = .clear
                renderer.strokeColor = .clear
            } else {
                let status = lastKnownStatus[polygon.isoCode] ?? .none
                RaskMapView.applyStyle(status: status, to: renderer,
                                       highlighted: polygon.isoCode == lastHighlighted,
                                       showBucketList: parent.showBucketList,
                                       isUserHere: polygon.isoCode == parent.locationIsoCode)
            }
            if activeOverlayIsos.contains(polygon.isoCode) {
                rendererCache[pid] = renderer
            }
            return renderer
        }

        /// Defensa adicional contra crecimiento patológico del cache. Si supera
        /// el cap (improbable con la arquitectura actual de overlays acotados),
        /// limpia las entries que ya no corresponden a polígonos activos.
        /// Pensado para llamarse desde puntos de sync ocasionales.
        private static let rendererCacheSoftCap = 2000
        func compactRendererCacheIfNeeded() {
            guard rendererCache.count > Self.rendererCacheSoftCap else { return }
            let stale = rendererCache.filter { (_, renderer) -> Bool in
                guard let polygon = renderer.polygon as? CountryPolygon else { return true }
                return !activeOverlayIsos.contains(polygon.isoCode)
            }
            for (pid, _) in stale {
                rendererCache.removeValue(forKey: pid)
            }
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {}
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {}

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if annotation is MKUserLocation {
                mapView.deselectAnnotation(annotation, animated: false)
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let airport = annotation as? AirportDotAnnotation {
                let id = "airportDot"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: airport, reuseIdentifier: id)
                view.annotation = airport
                view.canShowCallout = false
                view.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
                view.centerOffset = .zero
                view.backgroundColor = .clear
                view.isUserInteractionEnabled = false
                // Reutilizar el dot si ya existe (evita churn de subviews al reusar celdas).
                if view.subviews.isEmpty {
                    let accent = BrandColor.accentUI
                    let dot = UIView(frame: view.bounds)
                    dot.tag = 1001
                    dot.backgroundColor = .white
                    dot.layer.cornerRadius = 5
                    dot.layer.borderColor = accent.cgColor
                    dot.layer.borderWidth = 2
                    dot.layer.shadowColor = UIColor.black.cgColor
                    dot.layer.shadowOpacity = 0.18
                    dot.layer.shadowRadius = 2.5
                    dot.layer.shadowOffset = CGSize(width: 0, height: 1)
                    dot.isUserInteractionEnabled = false
                    view.addSubview(dot)
                }
                return view
            }
            guard let userLoc = annotation as? MKUserLocation else { return nil }
            userLoc.title = ""
            userLoc.subtitle = ""
            let id = "userLocationView"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKUserLocationView
                ?? MKUserLocationView(annotation: userLoc, reuseIdentifier: id)
            view.canShowCallout = false
            view.isUserInteractionEnabled = false
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

        // MARK: - Flight mode

        func enterFlightMode(mapView: MKMapView, trips: [Trip], filter: FlightRouteFilter) {
            // Ocultar punto de ubicación del usuario
            mapView.showsUserLocation = false
            // Ocultar polígonos sin quitar overlays (más rápido)
            for (_, renderer) in rendererCache {
                renderer.fillColor   = .clear
                renderer.strokeColor = .clear
                renderer.setNeedsDisplay()
            }
            applyFlightOverlays(mapView: mapView, trips: trips, filter: filter)
        }

        func exitFlightMode(mapView: MKMapView) {
            mapView.removeOverlays(flightRouteOverlays)
            mapView.removeAnnotations(airportAnnotations)
            flightRouteOverlays.removeAll()
            airportAnnotations.removeAll()
            lastFlightRoutes.removeAll()
            lastFlightAirports.removeAll()
            // Restaurar punto de ubicación
            mapView.showsUserLocation = true
            // Restaurar estilos
            let showBucket = parent.showBucketList
            for (_, renderer) in rendererCache {
                guard let polygon = renderer.polygon as? CountryPolygon else { continue }
                let status = lastKnownStatus[polygon.isoCode] ?? .none
                let isHL = polygon.isoCode == lastHighlighted
                let isHere = polygon.isoCode == parent.locationIsoCode
                RaskMapView.applyStyle(status: status, to: renderer,
                                       highlighted: isHL,
                                       showBucketList: showBucket,
                                       isUserHere: isHere)
                renderer.setNeedsDisplay()
            }
            // Encajar la vista a los países visitados (paralelo al fit de aeropuertos
            // que se hace al entrar en modo vuelos).
            fitToVisitedCountries(mapView: mapView)
        }

        /// Ajusta la región del mapa para que se vean todos los países visitados
        /// (o vividos). Si no hay ninguno o la región sería demasiado grande,
        /// no hace nada y conserva la vista actual.
        private func fitToVisitedCountries(mapView: MKMapView) {
            let visitedSet = Set(
                parent.countries
                    .filter { $0.status == .visited || $0.status == .lived }
                    .map { $0.isoCode }
            )
            guard !visitedSet.isEmpty else { return }
            var rect = MKMapRect.null
            for feature in parent.features where visitedSet.contains(feature.isoCode) {
                rect = rect.union(feature.boundingMapRect)
            }
            guard !rect.isNull, rect.size.width > 0, rect.size.height > 0 else { return }
            let padding = UIEdgeInsets(top: 80, left: 50, bottom: 80, right: 50)
            mapView.setVisibleMapRect(rect, edgePadding: padding, animated: true)
        }

        func refreshFlightOverlaysIfNeeded(mapView: MKMapView, trips: [Trip], filter: FlightRouteFilter) {
            let (routes, airports) = FlightRoutesBuilder.build(from: trips, filter: filter)
            guard routes != lastFlightRoutes || airports != lastFlightAirports else { return }
            mapView.removeOverlays(flightRouteOverlays)
            mapView.removeAnnotations(airportAnnotations)
            flightRouteOverlays.removeAll()
            airportAnnotations.removeAll()
            applyFlightOverlays(mapView: mapView, trips: trips, filter: filter)
        }

        /// Cambia el subfiltro (past/upcoming) — limpia y reconstruye siempre.
        func rebuildFlightOverlays(mapView: MKMapView, trips: [Trip], filter: FlightRouteFilter) {
            mapView.removeOverlays(flightRouteOverlays)
            mapView.removeAnnotations(airportAnnotations)
            flightRouteOverlays.removeAll()
            airportAnnotations.removeAll()
            lastFlightRoutes.removeAll()
            lastFlightAirports.removeAll()
            applyFlightOverlays(mapView: mapView, trips: trips, filter: filter)
        }

        private func applyFlightOverlays(mapView: MKMapView, trips: [Trip], filter: FlightRouteFilter) {
            let (routes, airports) = FlightRoutesBuilder.build(from: trips, filter: filter)
            lastFlightRoutes = routes
            lastFlightAirports = airports

            for pair in routes {
                guard let a = AirportCoordinates.coordinate(for: pair.a),
                      let b = AirportCoordinates.coordinate(for: pair.b) else { continue }
                var pts = [a, b]
                let line = MKGeodesicPolyline(coordinates: &pts, count: 2)
                flightRouteOverlays.append(line)
            }
            mapView.addOverlays(flightRouteOverlays, level: .aboveRoads)

            for iata in airports {
                guard let c = AirportCoordinates.coordinate(for: iata) else { continue }
                airportAnnotations.append(AirportDotAnnotation(iata: iata, coordinate: c))
            }
            mapView.addAnnotations(airportAnnotations)

            // Encaja la región al conjunto UNIÓN (pasados + próximos) para que
            // el viewport sea el MISMO al cambiar de filtro — así el usuario no
            // pierde la referencia. Si el filtro actual tiene un subconjunto,
            // los puntos/líneas cambian pero el encuadre es estable.
            fitFlightRegion(mapView: mapView, trips: trips)
        }

        /// Encaja la vista del mapa a TODOS los aeropuertos implicados en
        /// vuelos (pasados + próximos). Maneja el caso degenerado de 1 solo
        /// aeropuerto con un span razonable — si no, `setVisibleMapRect` con
        /// un MKMapRect 1×1 + padding zooma hasta nivel calle.
        private func fitFlightRegion(mapView: MKMapView, trips: [Trip]) {
            var iataSet = Set<String>()
            for f in [FlightRouteFilter.past, FlightRouteFilter.upcoming] {
                let (_, airports) = FlightRoutesBuilder.build(from: trips, filter: f)
                iataSet.formUnion(airports)
            }
            guard !iataSet.isEmpty else { return }

            let coords: [CLLocationCoordinate2D] = iataSet.compactMap {
                AirportCoordinates.coordinate(for: $0)
            }
            guard !coords.isEmpty else { return }

            // Caso 1 solo aeropuerto: usamos un span regional para no zoomar
            // a nivel calle (≈ un país mediano de ancho).
            if coords.count == 1 {
                let region = MKCoordinateRegion(
                    center: coords[0],
                    span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 30)
                )
                mapView.setRegion(region, animated: true)
                return
            }

            var rect = MKMapRect.null
            for c in coords {
                let p = MKMapPoint(c)
                rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 1, height: 1))
            }
            guard !rect.isNull else { return }
            let padding = UIEdgeInsets(top: 80, left: 50, bottom: 80, right: 50)
            mapView.setVisibleMapRect(rect, edgePadding: padding, animated: true)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            if parent.flightMode { return }
            guard let mapView = gesture.view as? MKMapView else { return }
            let tapLocation = gesture.location(in: mapView)
            let tapCoord = mapView.convert(tapLocation, toCoordinateFrom: mapView)
            let tapPoint = MKMapPoint(tapCoord)

            // Antarctica: Mercator can't represent the south pole correctly.
            // Any tap below -60° latitude maps reliably to Antarctica —
            // no other tappable territory exists below that latitude.
            if tapCoord.latitude < -60 {
                let result = parent.countries.first { $0.isoCode == "ATA" }
                          ?? Coordinator.antarcticaFallback
                parent.onCountryTapped(result)
                return
            }

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

