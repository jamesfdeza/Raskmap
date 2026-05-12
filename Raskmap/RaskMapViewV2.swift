//
//  RaskMapViewV2.swift
//  Raskmap
//
//  SwiftUI Map nativo (iOS 18+) con MapPolygon — alternativa al
//  `RaskMapView.swift` (UIViewRepresentable + MKMapView UIKit).
//
//  Por qué existe esta vista paralela:
//  · El render de MKPolygonRenderer (UIKit) re-rasteriza polígonos
//    por tile en cada pan, causando el flicker que el usuario reporta.
//  · El nuevo `MapPolygon` de iOS 18 usa Metal y elimina el flicker.
//
//  Estado: scaffold funcional con feature flag. El usuario decide
//  cuándo activarlo via `@AppStorage("useMapV2")` en Ajustes. Cuando
//  esté validado, se puede sustituir el viejo `RaskMapView` por este.
//
//  Limitaciones actuales:
//  · Requiere iOS 18.0+ (proyecto está en 17.0 → este archivo está
//    gated con `@available(iOS 18.0, *)`).
//  · No implementa flight mode aún (las rutas geodésicas se añaden
//    con `MapPolyline`).
//  · El highlight, location indicator y user-here vienen como TODOs
//    bien marcados.
//
//  Para activarlo:
//  1. Subir IPHONEOS_DEPLOYMENT_TARGET a 18.0 (corta cuota de usuarios).
//  2. Habilitar el toggle "Mapa nativo" en Ajustes (próximo paso).
//  3. Sustituir `RaskMapView(...)` por `RaskMapViewV2(...)` en
//     `ContentView.mapCore()`.
//

import SwiftUI
import MapKit
import CoreLocation

@available(iOS 18.0, *)
struct RaskMapViewV2: View {

    var countries: [Country]
    var features: [CountryFeature]
    var onCountryTapped: (Country) -> Void
    var highlightedIsoCode: String? = nil
    var showBucketList: Bool = true
    var locationIsoCode: String? = nil

    @EnvironmentObject private var colorTheme: ColorThemeManager

    /// Cámara — controlable desde el padre via callback `onReady`
    /// (compat con `RaskMapView` clásico). En esta versión usamos
    /// `@State` simple para simplificar el scaffold.
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 180)
        )
    )

    /// Mapa de status pre-indexado por ISO (recalculado al cambiar `countries`).
    private var statusByIso: [String: CountryStatus] {
        Dictionary(uniqueKeysWithValues: countries.map { ($0.isoCode, $0.status) })
    }

    /// Solo los polígonos coloreados — misma optimización que `RaskMapView`
    /// clásico, pero más simple porque MapKit nativo gestiona el cache.
    private var coloredFeatures: [CountryFeature] {
        features.filter { feature in
            let status = statusByIso[feature.isoCode] ?? .none
            switch status {
            case .none:        return false
            case .visited:     return true
            case .lived:       return true
            case .wantToVisit: return true
            case .bucketList:  return showBucketList
            }
        }
    }

    private func fillColor(for isoCode: String) -> Color {
        let status = statusByIso[isoCode] ?? .none
        return colorTheme.color(for: status)
    }

    var body: some View {
        Map(position: $cameraPosition) {
            // Polígonos de países coloreados. MapPolygon usa Metal y
            // se rasteriza una sola vez con `LOD` (level of detail)
            // gestionado por MapKit. Adiós flicker.
            ForEach(coloredFeatures, id: \.isoCode) { feature in
                ForEach(feature.polygons, id: \.self) { polygon in
                    MapPolygon(coordinates: polygonCoords(polygon))
                        .foregroundStyle(fillColor(for: feature.isoCode).opacity(0.78))
                        .stroke(
                            feature.isoCode == highlightedIsoCode
                                ? Color.black.opacity(0.85)
                                : Color.clear,
                            lineWidth: feature.isoCode == highlightedIsoCode ? 1.0 : 0
                        )
                }
            }

            // User location (azul nativo Apple).
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            // El usuario puede hacer pinch/pan estándar; sin controles
            // adicionales para mantener UX similar al MKMapView clásico.
        }
        .onTapGesture { _ in
            // TODO: hit-test contra polígonos visibles.
            // En iOS 18, `MapReader` + `proxy.convert(_:from:)` permite
            // convertir el punto de pantalla a coordenada y luego hacer
            // point-in-polygon manual. Pendiente para producción.
            //
            // Por ahora el scaffold solo dibuja — el tap-detection del
            // mapa antiguo sigue activo si el feature flag está off.
        }
    }

    /// Convierte un `CountryPolygon` (MKPolygon subclass) a array de
    /// CLLocationCoordinate2D para alimentar `MapPolygon`. MapKit ya
    /// tiene este dato internamente pero no expone una API directa
    /// SwiftUI; tenemos que extraer puntos.
    private func polygonCoords(_ polygon: CountryPolygon) -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(),
            count: polygon.pointCount
        )
        polygon.getCoordinates(&coords, range: NSRange(location: 0, length: polygon.pointCount))
        return coords
    }
}

// MARK: - Feature flag global

/// `useMapV2 == true` → renderizar `RaskMapViewV2` (requiere iOS 18+).
/// Default `false`. El usuario lo activa desde Ajustes cuando esté listo.
///
/// Para usar en código:
///
///     @AppStorage("useMapV2") private var useMapV2: Bool = false
///     ...
///     if useMapV2, #available(iOS 18.0, *) {
///         RaskMapViewV2(...)
///     } else {
///         RaskMapView(...)
///     }
///
/// (Wire-up no incluido en este scaffold — el dev decide cuándo migrar.)
