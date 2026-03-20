//
//  GeoJSONLoader.swift
//  Raskmap
//
//  Carga el archivo countries.geojson del bundle y lo convierte
//  en polígonos de MapKit listos para pintar sobre el mapa.
//
//  En Java sería algo como un RepositoryLoader o un JSONParser utilitario.
//

import Foundation
import MapKit


// MARK: - Estructura que representa un país con sus polígonos geográficos
// (equivalente a un DTO / Value Object en Java)
struct CountryFeature {
    let name: String
    let adminName: String
    let isoCode: String
    let isoA2: String
    let polygons: [CountryPolygon]

    // NUEVO: bounding box del país completo
    let boundingMapRect: MKMapRect
    // Traducir el nombre al español usando el sistema
    var localizedName: String {
        if isoA2 != "-99",
           let localized = Locale(identifier: "es").localizedString(forRegionCode: isoA2) {
            return localized
        }
        // Fallback manual para territorios sin código ISO
        let manualTranslations: [String: String] = [
            "Somaliland": "Somalilandia",
            "Northern Cyprus": "Chipre del Norte",
            "Kosovo": "Kosovo",
            "Transnistria": "Transnistria",
            "Abkhazia": "Abjasia",
            "South Ossetia": "Osetia del Sur",
        ]
        return manualTranslations[adminName] ?? adminName
    }/// Devuelve el emoji de bandera o nil si no hay código válido
    var flagEmoji: String? {
        guard isoA2.count == 2, isoA2 != "-99" else { return nil }
        return isoA2.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(0x1F1E6 + $0.value - 65)
        }.map { String($0) }.joined()
    }
}

// MARK: - Subclase de MKPolygon con metadatos del país
// Necesitamos subclasificar para poder asociar el nombre/código al overlay del mapa.
// En Java sería una clase que extiende otra añadiendo campos extra.
class CountryPolygon: MKPolygon {
    nonisolated(unsafe) var countryName: String = ""
    nonisolated(unsafe) var isoCode: String = ""
}

// MARK: - Cargador de GeoJSON
// Clase utilitaria estática (como una clase con métodos static en Java)
class GeoJSONLoader {

    /// Carga todos los países desde countries.geojson en el bundle de la app.
    /// - Returns: Array de CountryFeature, o vacío si hay algún error.
    nonisolated static func loadCountries() -> [CountryFeature] {
        // Buscar el archivo en el bundle (como getResourceAsStream en Java)
        guard let url = Bundle.main.url(forResource: "countries", withExtension: "geojson") else {
            print("❌ ERROR: No se encontró countries.geojson en el bundle.")
            print("   → Asegúrate de añadir el archivo al proyecto en Xcode.")
            return []
        }

        guard let data = try? Data(contentsOf: url) else {
            print("❌ ERROR: No se pudo leer countries.geojson")
            return []
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            print("❌ ERROR: JSON malformado en countries.geojson")
            return []
        }

        // Mapeamos cada feature GeoJSON a nuestro CountryFeature (como un .stream().map() en Java)
        return features.compactMap { parseFeature($0) }
    }
    // MARK: - Carga en background (evita bloquear la UI)
    static func loadCountriesAsync(completion: @escaping ([CountryFeature]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let countries = loadCountries()

            DispatchQueue.main.async {
                completion(countries)
            }
        }
    }
    // MARK: - Private helpers

     private nonisolated static func parseFeature(_ feature: [String: Any]) -> CountryFeature? {
        guard let props = feature["properties"] as? [String: Any],
              let geometry = feature["geometry"] as? [String: Any],
              let geometryType = geometry["type"] as? String else { return nil }
         
        // Probamos varias claves por compatibilidad con distintas fuentes de datos
         let name = props["ADMIN"] as? String
                 ?? props["name"] as? String
                 ?? props["NAME"] as? String
                 ?? "Unknown"
         let adminName = props["ADMIN"] as? String
                      ?? props["name"] as? String
                      ?? name
         let rawIso = props["ISO_A3"] as? String
                   ?? props["iso_a3"] as? String
                   ?? "-99"

         // Natural Earth usa "-99" para territorios sin código ISO oficial.
         // En ese caso usamos ADM0_A3 (código interno) o el nombre como fallback,
         // así cada territorio tiene un identificador único y no se confunden entre sí.
         let isoCode: String
         
         
         if rawIso == "-99" {
             isoCode = props["ADM0_A3"] as? String ?? name
         } else {
             isoCode = rawIso
         }

         // Fallback manual para territorios que Natural Earth deja en -99
         let knownA2: [String: String] = [
             "NOR": "NO",  // Norway
             "FRA": "FR",  // France
             "KOS": "XK",  // Kosovo
             "TWN": "TW",  // Taiwan
             "REU": "RE",  // Réunion
             "GLP": "GP",  // Guadeloupe
             "MTQ": "MQ",  // Martinique
             "GUF": "GF",  // French Guiana
             "MYT": "YT",  // Mayotte
         ]
         var isoA2 = "-99"
         if let v = props["ISO3166-1-Alpha-2"] {
             let s = "\(v)"  // Convierte cualquier tipo a String
             if s != "-99" && s.count == 2 {
                 isoA2 = s
             }
         } else if let v = props["ISO_A2"] {
             let s = "\(v)"
             if s != "-99" && s.count == 2 {
                 isoA2 = s
             }
         }
         if isoA2 == "-99" {
             isoA2 = knownA2[isoCode] ?? "-99"
         }
         
        var polygons: [CountryPolygon] = []

        switch geometryType {
        case "Polygon":
            // Un solo polígono (ej: España continental)
            if let coords = geometry["coordinates"] as? [[[Double]]],
               let polygon = makePolygon(rings: coords, name: name, iso: isoCode) {
                polygons.append(polygon)
            }

        case "MultiPolygon":
            // Múltiples polígonos (ej: España + Canarias + Baleares + Ceuta + Melilla)
            if let multiCoords = geometry["coordinates"] as? [[[[Double]]]] {
                polygons = multiCoords.compactMap {
                    makePolygon(rings: $0, name: name, iso: isoCode)
                }
            }

        default:
            return nil
        }

         guard !polygons.isEmpty else { return nil }

         // calcular bounding box del país
         let boundingRect = polygons
             .map { $0.boundingMapRect }
             .reduce(MKMapRect.null) { $0.union($1) }
         
         return CountryFeature(
             name: name,
             adminName: adminName,
             isoCode: isoCode,
             isoA2: isoA2,
             polygons: polygons,
             boundingMapRect: boundingRect
         )
     }

    /// Convierte arrays de coordenadas GeoJSON en un MKPolygon con huecos (ej: lagos dentro de países)
    private nonisolated static func makePolygon(rings: [[[Double]]], name: String, iso: String) -> CountryPolygon? {
        guard let outerRing = rings.first else { return nil }

        // GeoJSON usa [longitud, latitud] — MapKit usa CLLocationCoordinate2D(lat, lon) → hay que invertir
        let outerCoords: [CLLocationCoordinate2D] = outerRing.compactMap { point in
            guard point.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
        }
        guard outerCoords.count >= 3 else { return nil }

        // Tolerancia adaptativa según el tamaño del bounding box del polígono (en grados²):
        //  > 500°²  → muy grandes (Rusia, Canadá, EEUU…)     → 0.05°  (~5 km)
        //  > 50°²   → medianos (España, Francia, Alemania…)   → 0.02°  (~2 km)
        //  > 5°²    → pequeños (Bélgica, Suiza, Portugal…)    → 0.01°  (~1 km)
        //  ≤ 5°²    → microestados e islas (Malta, Maldivas…) → 0.005° (~500 m)
        let lats = outerCoords.map { $0.latitude }
        let lons = outerCoords.map { $0.longitude }
        let latSpan = (lats.max() ?? 0) - (lats.min() ?? 0)
        let lonSpan = (lons.max() ?? 0) - (lons.min() ?? 0)
        let area = latSpan * lonSpan
        let tolerance: Double
        switch area {
        case 500...:    tolerance = 0.05
        case 50...:     tolerance = 0.02
        case 5...:      tolerance = 0.01
        case 0.01...:   tolerance = 0.005
        default:        tolerance = 0.0  // microestados (Vaticano, San Marino…): no simplificar
        }

        let simplifiedOuter = tolerance > 0
            ? simplifyCoords(outerCoords, tolerance: tolerance)
            : outerCoords
        guard simplifiedOuter.count >= 3 else { return nil }

        // Solo ZAF (Sudáfrica) tiene un hueco real (Lesoto) — el resto son artefactos
        let holes: [MKPolygon] = iso == "ZAF" ? rings.dropFirst().compactMap { ring in
            let holeCoords: [CLLocationCoordinate2D] = ring.compactMap { point in
                guard point.count >= 2 else { return nil }
                return CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
            }
            guard holeCoords.count >= 3 else { return nil }
            let simplified = tolerance > 0
                ? simplifyCoords(holeCoords, tolerance: tolerance)
                : holeCoords
            guard simplified.count >= 3 else { return nil }
            return MKPolygon(coordinates: simplified, count: simplified.count)
        } : []

        let polygon = CountryPolygon(
            coordinates: simplifiedOuter,
            count: simplifiedOuter.count,
            interiorPolygons: holes.isEmpty ? nil : holes
        )
        polygon.countryName = name
        polygon.isoCode = iso
        return polygon
    }

    /// Simplificación de Ramer–Douglas–Peucker: elimina puntos redundantes manteniendo la forma
    private nonisolated static func simplifyCoords(
        _ coords: [CLLocationCoordinate2D],
        tolerance: Double
    ) -> [CLLocationCoordinate2D] {
        guard coords.count > 2 else { return coords }

        var maxDist = 0.0
        var maxIdx  = 0
        let last = coords.count - 1

        for i in 1..<last {
            let d = perpendicularDistance(coords[i], lineStart: coords[0], lineEnd: coords[last])
            if d > maxDist { maxDist = d; maxIdx = i }
        }

        if maxDist > tolerance {
            let left  = simplifyCoords(Array(coords[0...maxIdx]), tolerance: tolerance)
            let right = simplifyCoords(Array(coords[maxIdx...last]), tolerance: tolerance)
            return left.dropLast() + right
        } else {
            return [coords[0], coords[last]]
        }
    }

    private nonisolated static func perpendicularDistance(
        _ point: CLLocationCoordinate2D,
        lineStart: CLLocationCoordinate2D,
        lineEnd: CLLocationCoordinate2D
    ) -> Double {
        let dx = lineEnd.longitude - lineStart.longitude
        let dy = lineEnd.latitude  - lineStart.latitude
        let len2 = dx * dx + dy * dy
        if len2 == 0 {
            let ex = point.longitude - lineStart.longitude
            let ey = point.latitude  - lineStart.latitude
            return sqrt(ex * ex + ey * ey)
        }
        let t = ((point.longitude - lineStart.longitude) * dx +
                 (point.latitude  - lineStart.latitude)  * dy) / len2
        let projX = lineStart.longitude + t * dx
        let projY = lineStart.latitude  + t * dy
        let ex = point.longitude - projX
        let ey = point.latitude  - projY
        return sqrt(ex * ex + ey * ey)
    }
}
