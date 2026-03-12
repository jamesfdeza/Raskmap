import SwiftUI
import MapKit

struct RaskMapView: UIViewRepresentable {

    @Binding var countries: [Country]
    var features: [CountryFeature]

    var onCountryTapped: (Country) -> Void
    var onReady: ((_ center: @escaping (String) -> Void) -> Void)? = nil

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator

        mapView.mapType = .standard
        mapView.showsUserLocation = false
        mapView.isRotateEnabled = false

        // Zoom inicial: vista del mundo
        let worldRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 180)
        )
        mapView.setRegion(worldRegion, animated: false)

        // Gesture recognizer para detectar toques en países
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        mapView.addGestureRecognizer(tapGesture)

        // Añadir solo los polígonos visibles inicialmente
        let visible = context.coordinator.visibleCountries(for: mapView)
        let polygons = visible.flatMap { $0.polygons }
        mapView.addOverlays(polygons, level: .aboveRoads)

        // callback onReady
        onReady?({ isoCode in
            guard let feature = context.coordinator.parent.features.first(where: { $0.isoCode == isoCode }),
                  let polygon = feature.polygons.first else { return }
            let rect = polygon.boundingMapRect
            let paddedRect = rect.insetBy(dx: -rect.size.width * 0.5, dy: -rect.size.height * 0.5)

            let minSize = MKMapSize(width: 13_000_000, height: 13_000_000)
            let finalRect = MKMapRect(
                x: paddedRect.midX - max(paddedRect.size.width, minSize.width) / 2,
                y: paddedRect.midY - max(paddedRect.size.height, minSize.height) / 2,
                width: max(paddedRect.size.width, minSize.width),
                height: max(paddedRect.size.height, minSize.height)
            )
            let region = MKCoordinateRegion(finalRect)
            mapView.setRegion(region, animated: true)
        })

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        // Si no hay overlays aún, añadir los visibles
        if mapView.overlays.isEmpty {
            let visible = context.coordinator.visibleCountries(for: mapView)
            let polygons = visible.flatMap { $0.polygons }
            mapView.addOverlays(polygons, level: .aboveRoads)
            return
        }

        // --- OPTIMIZACIÓN CLAVE: Solo actualizar países que realmente cambiaron ---
        let newStatusMap = Dictionary(uniqueKeysWithValues: countries.map { ($0.isoCode, $0.status) })
        let oldStatusMap = context.coordinator.lastKnownStatus

        // Detectar isoCodes cuyo status cambió
        var changedIsoCodes = Set<String>()
        for (iso, status) in newStatusMap {
            if oldStatusMap[iso] != status { changedIsoCodes.insert(iso) }
        }
        for iso in oldStatusMap.keys where newStatusMap[iso] == nil {
            changedIsoCodes.insert(iso)
        }

        guard !changedIsoCodes.isEmpty else { return }

        // Guardar nuevo snapshot de estado
        context.coordinator.lastKnownStatus = newStatusMap

        // Invalidar caché de renderers para los polígonos de países que cambiaron
        let polygonIDsToInvalidate = features
            .filter { changedIsoCodes.contains($0.isoCode) }
            .flatMap { $0.polygons }
            .map { ObjectIdentifier($0) }
        for pid in polygonIDsToInvalidate {
            context.coordinator.rendererCache.removeValue(forKey: pid)
        }

        // Quitar overlays de países cambiados que estén actualmente en el mapa
        let overlaysToRemove = mapView.overlays
            .compactMap { $0 as? CountryPolygon }
            .filter { changedIsoCodes.contains($0.isoCode) }
        mapView.removeOverlays(overlaysToRemove)

        // Re-añadir solo los polígonos de países cambiados que son visibles
        let visibleRect = mapView.visibleMapRect
        let polygonsToAdd = features
            .filter { changedIsoCodes.contains($0.isoCode) && $0.boundingMapRect.intersects(visibleRect) }
            .flatMap { $0.polygons }

        if !polygonsToAdd.isEmpty {
            mapView.addOverlays(polygonsToAdd, level: .aboveRoads)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: RaskMapView

        /// Caché de renderers: ObjectIdentifier(polygon) → MKPolygonRenderer
        /// Evita recrear renderers en cada llamada. Usa identidad del objeto, no isoCode,
        /// para soportar correctamente países multipolígono (España, EEUU, etc.)
        var rendererCache: [ObjectIdentifier: MKPolygonRenderer] = [:]

        /// Snapshot del estado previo para detectar cambios reales
        var lastKnownStatus: [String: CountryStatus] = [:]

        /// Debounce para regionDidChange — evita recargar en cada frame del scroll
        private var regionChangeWorkItem: DispatchWorkItem?
        /// IDs de polígonos grises ocultados durante el scroll para recuperarlos después
        private var hiddenGrayPolygons: [CountryPolygon] = []

        init(parent: RaskMapView) {
            self.parent = parent
        }

        func visibleCountries(for mapView: MKMapView) -> [CountryFeature] {
            let visibleRect = mapView.visibleMapRect
            return parent.features.filter { $0.boundingMapRect.intersects(visibleRect) }
        }

        // MARK: - Renderer con caché
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polygon = overlay as? CountryPolygon else {
                return MKOverlayRenderer(overlay: overlay)
            }

            // Devolver renderer cacheado si existe
            let polygonID = ObjectIdentifier(polygon)
            if let cached = rendererCache[polygonID] {
                return cached
            }

            let renderer = MKPolygonRenderer(polygon: polygon)

            let status = parent.countries
                .first { $0.isoCode == polygon.isoCode }?
                .status ?? .none

            renderer.fillColor = status.overlayColor
            renderer.strokeColor = status == .none
                ? UIColor.systemGray.withAlphaComponent(0.3)
                : status.strokeColor
            renderer.lineWidth = status == .none ? 0.4 : 1.2

            // Cachear solo países con estado marcado (los grises se recrean rápido y hay muchos)
            if status != .none {
                rendererCache[polygonID] = renderer
            }

            return renderer
        }

        // MARK: - Ocultar grises al empezar scroll para máxima fluidez
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            regionChangeWorkItem?.cancel()

            // Durante el scroll, quitar temporalmente los polígonos grises del mapa
            // Los coloreados se quedan siempre visibles
            let markedIsoCodes = Set(parent.countries
                .filter { $0.status != .none }
                .map { $0.isoCode })

            let grays = mapView.overlays
                .compactMap { $0 as? CountryPolygon }
                .filter { !markedIsoCodes.contains($0.isoCode) }

            if !grays.isEmpty {
                hiddenGrayPolygons = grays
                mapView.removeOverlays(grays)
            }
        }

        // MARK: - Restaurar grises cuando el scroll termina
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            regionChangeWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                self.hiddenGrayPolygons = []
                self.reloadVisibleOverlays(in: mapView)
            }
            regionChangeWorkItem = workItem
            // Pequeño delay para que el mapa termine de asentarse antes de repintar
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
        }

        private func reloadVisibleOverlays(in mapView: MKMapView) {
            let visibleRect = mapView.visibleMapRect

            // IsoCodes de países marcados — estos NUNCA se quitan del mapa
            let markedIsoCodes = Set(parent.countries
                .filter { $0.status != .none }
                .map { $0.isoCode })

            // Polígonos que DEBEN estar en el mapa:
            // - todos los de países visibles (grises)
            // - SIEMPRE todos los de países marcados (coloreados), aunque no sean visibles
            let visibleFeaturePolygons = parent.features
                .filter { $0.boundingMapRect.intersects(visibleRect) }
                .flatMap { $0.polygons }
            let markedFeaturePolygons = parent.features
                .filter { markedIsoCodes.contains($0.isoCode) }
                .flatMap { $0.polygons }

            // Unión sin duplicados usando ObjectIdentifier
            var targetMap: [ObjectIdentifier: CountryPolygon] = [:]
            for p in visibleFeaturePolygons { targetMap[ObjectIdentifier(p)] = p }
            for p in markedFeaturePolygons  { targetMap[ObjectIdentifier(p)] = p }

            let currentPolygons = mapView.overlays.compactMap { $0 as? CountryPolygon }
            let currentSet = Set(currentPolygons.map { ObjectIdentifier($0) })

            // Quitar solo los grises que ya no son visibles (nunca quitar marcados)
            let toRemove = currentPolygons.filter {
                !targetMap.keys.contains(ObjectIdentifier($0))
            }
            if !toRemove.isEmpty {
                mapView.removeOverlays(toRemove)
            }

            // Añadir los que faltan
            let toAdd = targetMap.values.filter { !currentSet.contains(ObjectIdentifier($0)) }
            if !toAdd.isEmpty {
                mapView.addOverlays(Array(toAdd), level: .aboveRoads)
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }

            let tapCoord = mapView.convert(gesture.location(in: mapView), toCoordinateFrom: mapView)
            let tapPoint = MKMapPoint(tapCoord)

            // Ordenar por área ascendente: los territorios pequeños (enclaves,
            // territorios en conflicto) tienen prioridad sobre el país grande que los contiene
            let candidates = visibleCountries(for: mapView)
                .filter { $0.boundingMapRect.contains(tapPoint) }
                .sorted {
                    let a0 = $0.boundingMapRect.size.width * $0.boundingMapRect.size.height
                    let a1 = $1.boundingMapRect.size.width * $1.boundingMapRect.size.height
                    return a0 < a1
                }

            for country in candidates {
                for polygon in country.polygons {
                    guard let renderer = mapView.renderer(for: polygon) as? MKPolygonRenderer else { continue }
                    let rendererPoint = renderer.point(for: tapPoint)

                    if renderer.path?.contains(rendererPoint) == true {
                        if let countryData = parent.countries.first(where: { $0.isoCode == polygon.isoCode }) {
                            parent.onCountryTapped(countryData)
                        } else {
                            let newCountry = Country(name: polygon.countryName, isoCode: polygon.isoCode)
                            parent.onCountryTapped(newCountry)
                        }
                        return
                    }
                }
            }
        }
    }
}
