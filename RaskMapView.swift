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

        if mapView.overlays.isEmpty {
            let visible = context.coordinator.visibleCountries(for: mapView)
            let polygons = visible.flatMap { $0.polygons }
            mapView.addOverlays(polygons, level: .aboveRoads)
            return
        }

        let dbIsoCodes = Set(countries.map { $0.isoCode })

        let overlaysToRefresh = mapView.overlays
            .compactMap { $0 as? CountryPolygon }
            .filter { dbIsoCodes.contains($0.isoCode) }

        mapView.removeOverlays(overlaysToRefresh)

        let polygonsToAdd = features
            .filter { dbIsoCodes.contains($0.isoCode) }
            .flatMap { $0.polygons }

        mapView.addOverlays(polygonsToAdd, level: .aboveRoads)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: RaskMapView

        init(parent: RaskMapView) {
            self.parent = parent
        }

        // Calcula qué países son visibles en el mapa
        func visibleCountries(for mapView: MKMapView) -> [CountryFeature] {
            let visibleRect = mapView.visibleMapRect
            return parent.features.filter { $0.boundingMapRect.intersects(visibleRect) }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polygon = overlay as? CountryPolygon else {
                return MKOverlayRenderer(overlay: overlay)
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

            return renderer
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            mapView.removeOverlays(mapView.overlays)

            let visible = visibleCountries(for: mapView)
            let polygons = visible.flatMap { $0.polygons }
            mapView.addOverlays(polygons, level: .aboveRoads)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }

            let tapCoord = mapView.convert(gesture.location(in: mapView), toCoordinateFrom: mapView)
            let tapPoint = MKMapPoint(tapCoord)

            for country in visibleCountries(for: mapView) {
                if !country.boundingMapRect.contains(tapPoint) { continue }

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
