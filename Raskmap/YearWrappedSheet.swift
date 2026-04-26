//
//  YearWrappedSheet.swift
//  Raskmap
//
//  Resumen animado del año anterior (estilo Spotify Wrapped).
//  Slides auto-avanzadas con progress bars, gestos de tap/swipe y métricas
//  calculadas sobre los viajes del 1 enero – 31 diciembre del año previo.
//

import SwiftUI
import Combine
import CoreLocation

// MARK: - Stats

struct WrappedStats {
    let year: Int

    // Países reconocidos por la ONU (miembros + observadores) visitados
    let totalCountries: Int
    let newCountries: Int
    let repeatedCountries: Int

    // Territorios no reconocidos por la ONU visitados
    let totalTerritories: Int
    let newTerritories: Int

    let topFlags: [String]           // Top 4 banderas por nº de viajes
    let topCountryNames: [String]    // Nombres correspondientes
    let topCountryTripCount: Int     // nº de viajes del #1 — para saber si "al que más volviste" aplica

    // Destinos nuevos / repetidos con sus flags (para pintarlos en la slide)
    let newDestinations: [(flag: String, name: String)]
    let repeatedDestinations: [(flag: String, name: String)]
    // TODOS los destinos visitados del año (países + territorios) con sus flags.
    // Ordenados por nº de visitas desc → ISO asc. Se usa en la slide "Has visitado X destinos"
    // para mostrar todas las banderas, no solo el top 4.
    let allVisitedDestinations: [(flag: String, name: String)]

    let totalSegments: Int
    let transportBreakdown: [(emoji: String, count: Int)]
    let flights: Int
    let flightKm: Int
    let topAirlines: [(name: String, count: Int)]      // top 3
    let topAirports: [(iata: String, name: String, count: Int)]  // top 3
    let continents: Int
    let topMonths: [(month: Int, count: Int)]  // todos los meses con el máximo
    let longestTripDays: Int
    let longestTripCountry: String?
    let longestTripFlag: String?
    let totalTrips: Int

    static let empty = WrappedStats(
        year: 0, totalCountries: 0, newCountries: 0, repeatedCountries: 0,
        totalTerritories: 0, newTerritories: 0,
        topFlags: [], topCountryNames: [], topCountryTripCount: 0,
        newDestinations: [], repeatedDestinations: [],
        allVisitedDestinations: [],
        totalSegments: 0,
        transportBreakdown: [], flights: 0, flightKm: 0,
        topAirlines: [], topAirports: [], continents: 0,
        topMonths: [], longestTripDays: 0,
        longestTripCountry: nil, longestTripFlag: nil, totalTrips: 0
    )

    static func compute(year: Int, trips: [Trip], allFeatures: [CountryFeature]) -> WrappedStats {
        // Primarios del año (para segmentos/vuelos/mes/etc.)
        let yearTrips = trips.filter { $0.year == year && !$0.isSegmentChild }
        // TODOS los registros del año, incluyendo segment children, para contar destinos reales.
        let yearAllTrips = trips.filter { $0.year == year }

        // ISOs previos al año — tanto primarios como children.
        // Para segments: misma regla que más abajo.
        //  - Vuelo (✈️): endpoints + escalas que el usuario marcó como visitadas
        //    (seg.visitedLayoverISOs, checkbox en AddSegmentSheet).
        //  - Terrestre/marítimo: todos los isoCodes (cruzar frontera = visita).
        // Así una escala aérea previa en UAE no marca este año como "repetido"
        // salvo que el usuario dijera explícitamente "sí, visité UAE".
        var priorISOs: Set<String> = []
        for t in trips where t.year < year {
            if !t.isoCode.isEmpty { priorISOs.insert(t.isoCode) }
            for seg in t.tripSegments {
                let isos = seg.isoCodes.filter { !$0.isEmpty }
                guard !isos.isEmpty else { continue }
                if seg.transport == "✈️" {
                    if let f = isos.first { priorISOs.insert(f) }
                    if isos.count > 1, let l = isos.last { priorISOs.insert(l) }
                    // Escalas marcadas como visitadas por checkbox también cuentan.
                    for iso in seg.visitedLayoverISOs ?? [] where !iso.isEmpty {
                        priorISOs.insert(iso)
                    }
                } else {
                    for iso in isos { priorISOs.insert(iso) }
                }
            }
        }

        // Países / territorios visitados ESTE año. Incluimos segment children (layovers
        // guardados como trip), e ISOs de segments de trips primarios — así
        // capturamos territorios tipo Hong Kong / Macao independientemente de cómo
        // se hayan registrado o el medio de transporte.
        //
        // Dedupe: un round-trip (ida+vuelta) o cualquier viaje multi-transport
        // donde el mismo país aparezca tanto en el primario como en un child
        // debe contar como 1 visita, no 2. La clave de dedupe es
        // (segmentGroupID, isoCode) — un mismo grupo de segmentos solo suma
        // 1 por país. Trips sin groupID cuentan cada uno por separado (son
        // viajes independientes).
        var countryTripCounts: [String: Int] = [:]
        var seenGroupCountry: Set<String> = []
        for t in yearAllTrips where !t.isoCode.isEmpty {
            if let gid = t.segmentGroupID {
                let key = "\(gid)|\(t.isoCode)"
                if seenGroupCountry.insert(key).inserted {
                    countryTripCounts[t.isoCode, default: 0] += 1
                }
            } else {
                countryTripCounts[t.isoCode, default: 0] += 1
            }
        }
        // Recorremos segments de primarios para capturar cualquier ISO adicional
        // que no esté como child trip. Reglas:
        //  - Transporte terrestre/marítimo: TODOS los isoCodes cuentan (cada país
        //    que cruzas en bus/tren/coche/barco/a pie lo visitas físicamente).
        //  - Vuelo (✈️): cuentan los endpoints (origen y destino) + escalas
        //    aéreas que el usuario marcó como visitadas vía el checkbox
        //    (seg.visitedLayoverISOs, mantenido desde AddSegmentSheet).
        //    Escalas intermedias NO marcadas = tránsito de aeropuerto, no visita.
        for t in yearTrips {
            for seg in t.tripSegments {
                let isos = seg.isoCodes.filter { !$0.isEmpty }
                guard !isos.isEmpty else { continue }
                if seg.transport == "✈️" {
                    // Endpoints
                    if let first = isos.first, countryTripCounts[first] == nil {
                        countryTripCounts[first] = 1
                    }
                    if isos.count > 1, let last = isos.last, countryTripCounts[last] == nil {
                        countryTripCounts[last] = 1
                    }
                    // Escalas marcadas como visitadas por el usuario → sí cuentan.
                    for iso in seg.visitedLayoverISOs ?? [] where !iso.isEmpty && countryTripCounts[iso] == nil {
                        countryTripCounts[iso] = 1
                    }
                } else {
                    for iso in isos where countryTripCounts[iso] == nil {
                        countryTripCounts[iso] = 1
                    }
                }
            }
        }
        let isoList = Array(countryTripCounts.keys)

        let recognized = CountingMode.unMembers.union(CountingMode.unObservers)
        let recognizedList = isoList.filter { recognized.contains($0) }
        let territoryList = isoList.filter { !recognized.contains($0) }

        let totalCountries = recognizedList.count
        let totalTerritories = territoryList.count
        let newCountries = recognizedList.filter { !priorISOs.contains($0) }.count
        let newTerritories = territoryList.filter { !priorISOs.contains($0) }.count

        // Top destinos (orden estable: más visitas → ISO alfabético).
        // Si no tienen flagEmoji en features, caemos a 🌐 para que el territorio
        // aparezca igualmente (Hong Kong, Macao, etc.).
        let sortedEntries = countryTripCounts.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key < $1.key
        }
        let topSorted = Array(sortedEntries.prefix(4))
        var flags: [String] = []
        var names: [String] = []
        for (iso, _) in topSorted {
            let feature = allFeatures.first(where: { $0.isoCode == iso })
            flags.append(feature?.flagEmoji ?? "🌐")
            names.append(feature?.localizedName ?? iso)
        }
        let topTripCount = topSorted.first?.1 ?? 0

        // Destinos separados por nuevo / repetido — el usuario pidió ver las banderas
        // en la slide "destinos nuevos + N que repetiste". Nombres como fallback si
        // no hay bandera.
        var newDests: [(flag: String, name: String)] = []
        var repeatedDests: [(flag: String, name: String)] = []
        var allDests: [(flag: String, name: String)] = []
        for (iso, _) in sortedEntries {
            let feature = allFeatures.first(where: { $0.isoCode == iso })
            let pair = (flag: feature?.flagEmoji ?? "🌐",
                        name: feature?.localizedName ?? iso)
            allDests.append(pair)
            if priorISOs.contains(iso) {
                repeatedDests.append(pair)
            } else {
                newDests.append(pair)
            }
        }

        // Transport breakdown (sort estable para evitar parpadeo en empates)
        // Para ✈️ contamos LEGS (tramos), no segmentos. El resto suma 1 por segmento.
        // Debe dar el mismo total que el contador de vuelos de más abajo — misma
        // regla de dedup y sin floor en el fallback legacy.
        var transportCounts: [String: Int] = [:]
        var totalSegs = 0
        for t in yearTrips {
            let segs = t.tripSegments
            if segs.isEmpty {
                if let tr = t.transport, !tr.isEmpty {
                    if tr == "✈️" {
                        let totalTouches = t.tripAirports.reduce(0) { $0 + $1.count }
                        let legs = totalTouches / 2   // sin max(1,…) — no inflamos si falta data
                        if legs > 0 {
                            transportCounts[tr, default: 0] += legs
                            totalSegs += legs
                        }
                    } else {
                        transportCounts[tr, default: 0] += 1
                        totalSegs += 1
                    }
                }
            } else {
                var seenFlightKeys = Set<String>()
                for seg in segs {
                    if seg.transport == "✈️" {
                        let outK = (seg.airports ?? []).map { $0.iata }.joined(separator: "-")
                        let retK = (seg.returnAirports ?? []).map { $0.iata }.joined(separator: "-")
                        let dfK = String(Int(seg.dateFrom.timeIntervalSince1970))
                        guard seenFlightKeys.insert("\(outK)|\(retK)|\(dfK)").inserted else { continue }
                        let outLegs = max(0, (seg.airports?.count ?? 0) - 1)
                        let retLegs = max(0, (seg.returnAirports?.count ?? 0) - 1)
                        let legs = outLegs + retLegs
                        if legs > 0 {
                            transportCounts[seg.transport, default: 0] += legs
                            totalSegs += legs
                        }
                    } else {
                        transportCounts[seg.transport, default: 0] += 1
                        totalSegs += 1
                    }
                }
            }
        }
        let tBreakdown: [(emoji: String, count: Int)] = transportCounts
            .map { (emoji: $0.key, count: $0.value) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.emoji < $1.emoji
            }

        // Flights + airports + airlines + km.
        // Regla clave: 1 vuelo = 1 tramo (leg) de viaje en avión.
        //  - Ida y vuelta directo: [MAD,JFK] + [JFK,MAD] = 2 vuelos
        //  - Ida con escala: [MAD,DXB,NRT] = 2 vuelos (MAD→DXB + DXB→NRT)
        //  - Ida+vuelta con escala ambas direcciones: 4 vuelos
        // Se calcula como max(0, airports.count − 1) + max(0, returnAirports.count − 1).
        var flightCount = 0
        var totalKm = 0.0
        var airlineCounts: [String: Int] = [:]
        var airportCounts: [String: Int] = [:]
        for t in yearTrips {
            let fs = t.tripSegments.filter { $0.transport == "✈️" }
            if !fs.isEmpty {
                // Dedup defensivo por (airports-joined | returnAirports-joined | dateFrom)
                // — si el editor alguna vez hubiera dejado dos segmentos con misma
                // ruta y fecha (p.ej. edit + cancel raro), solo contamos uno.
                var seenSegKeys = Set<String>()
                for seg in fs {
                    let outK = (seg.airports ?? []).map { $0.iata }.joined(separator: "-")
                    let retK = (seg.returnAirports ?? []).map { $0.iata }.joined(separator: "-")
                    let dfK = String(Int(seg.dateFrom.timeIntervalSince1970))
                    guard seenSegKeys.insert("\(outK)|\(retK)|\(dfK)").inserted else { continue }
                    let outLegs = max(0, (seg.airports?.count ?? 0) - 1)
                    let retLegs = max(0, (seg.returnAirports?.count ?? 0) - 1)
                    // NO añadimos floor 1 — si el segmento no tiene aeropuertos válidos
                    // (0 legs), NO cuenta como vuelo (antes inflaba el total).
                    flightCount += outLegs + retLegs
                    for al in seg.airlines ?? [] where !al.name.isEmpty {
                        airlineCounts[al.name, default: 0] += al.count
                    }
                    var apC: [String: Int] = [:]
                    for ap in seg.airports ?? [] { apC[ap.iata, default: 0] += ap.count }
                    for ap in seg.returnAirports ?? [] { apC[ap.iata, default: 0] += ap.count }
                    for (iata, c) in apC { airportCounts[iata, default: 0] += c }
                    totalKm += kmAlong(iatas: (seg.airports ?? []).map { $0.iata })
                    totalKm += kmAlong(iatas: (seg.returnAirports ?? []).map { $0.iata })
                }
            } else if t.transport == "✈️" {
                // Trip primario LEGACY sin segmentos — `tripAirports` es una
                // lista deduplicada donde `count` indica cuántas veces se
                // despegó/aterrizó en ese aeropuerto. Cada tramo toca 2
                // aeropuertos (despegue + aterrizaje), así que:
                //   legs = sum(count) / 2
                //
                // Ejemplos (después de migrar roundTrip→count=2):
                //   - Ida directa MAD→NRT:              [MAD(1), NRT(1)]             → 2/2 = 1
                //   - Round-trip directo MAD↔NRT:       [MAD(2), NRT(2)]             → 4/2 = 2
                //   - Ida con escala MAD→DXB→NRT:       [MAD(1), DXB(2), NRT(1)]    → 4/2 = 2
                //   - Round-trip con escala ambos:      [MAD(2), DXB(4), NRT(2)]    → 8/2 = 4
                //
                // Sin `max(1, ...)`: un trip con transport="✈️" pero sin aeropuertos
                // guardados NO cuenta (antes contaba como 1 ghost flight).
                let totalTouches = t.tripAirports.reduce(0) { $0 + $1.count }
                let legs = totalTouches / 2
                flightCount += legs
                for al in t.tripAirlines where !al.name.isEmpty {
                    airlineCounts[al.name, default: 0] += al.count
                }
                for ap in t.tripAirports { airportCounts[ap.iata, default: 0] += ap.count }
                totalKm += kmAlong(iatas: t.tripAirports.map { $0.iata })
            }
        }

        // Top 3 aerolíneas (estable)
        let topAirlines: [(name: String, count: Int)] = airlineCounts
            .sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                return $0.key < $1.key
            }
            .prefix(3)
            .map { (name: $0.key, count: $0.value) }

        // Top 3 aeropuertos (estable)
        let topAirports: [(iata: String, name: String, count: Int)] = airportCounts
            .sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                return $0.key < $1.key
            }
            .prefix(3)
            .map { kv in
                let n = RoutePickerSheet.allAirports.first { $0.iata == kv.key }?.name ?? kv.key
                return (iata: kv.key, name: n, count: kv.value)
            }

        // Continents
        let continentSets: [Set<String>] = [
            AchievementKind.visitedEuropa.regionIsoCodes,
            AchievementKind.visitedAsia.regionIsoCodes,
            AchievementKind.visitedAfrica.regionIsoCodes,
            AchievementKind.visitedNortamerica.regionIsoCodes
                .union(AchievementKind.visitedCaribe.regionIsoCodes)
                .union(AchievementKind.visitedSudamerica.regionIsoCodes)
                .union(AchievementKind.visitedCentroamerica.regionIsoCodes),
            AchievementKind.visitedOceania.regionIsoCodes,
        ]
        let visitedSet = Set(isoList)
        let contCount = continentSets.filter { !$0.isDisjoint(with: visitedSet) }.count

        // Top month — devolvemos TODOS los meses empatados al máximo (ordenados).
        var monthCounts: [Int: Int] = [:]
        for t in yearTrips {
            let m = Calendar.current.component(.month, from: t.dateFrom)
            monthCounts[m, default: 0] += 1
        }
        let maxMonthCount = monthCounts.values.max() ?? 0
        let topMs: [(month: Int, count: Int)] = maxMonthCount == 0 ? [] :
            monthCounts
                .filter { $0.value == maxMonthCount }
                .sorted { $0.key < $1.key }
                .map { (month: $0.key, count: $0.value) }

        // Longest stay (días en un país concreto) — delegamos en
        // `daysPerCountry(trips:)` (definido en Trip.swift) para usar el
        // mismo algoritmo quirúrgico que el widget y el resto de la app:
        // cada día se atribuye a UN solo país según la fuente más específica
        // (segment interno > child de grupo > trip corto > trip largo).
        //
        // Caso real del usuario: HKG 1–11 con bus→MAC, pie→CHN, tren→HKG
        // entre medias → HKG recibe solo los días fuera de MAC/CHN, no los 11.
        let perCountryDays = daysPerCountry(trips: yearAllTrips)
        var longest = 0
        var longestCountry: String? = nil
        var longestFlag: String? = nil
        // Orden estable: más días desc, luego ISO asc
        let sortedStays = perCountryDays.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key < $1.key
        }
        if let top = sortedStays.first {
            longest = top.value
            let feat = allFeatures.first(where: { $0.isoCode == top.key })
            longestCountry = feat?.localizedName ?? top.key
            longestFlag = feat?.flagEmoji ?? "🌐"
        }

        return WrappedStats(
            year: year,
            totalCountries: totalCountries,
            newCountries: newCountries,
            repeatedCountries: totalCountries - newCountries,
            totalTerritories: totalTerritories,
            newTerritories: newTerritories,
            topFlags: flags,
            topCountryNames: names,
            topCountryTripCount: topTripCount,
            newDestinations: newDests,
            repeatedDestinations: repeatedDests,
            allVisitedDestinations: allDests,
            totalSegments: totalSegs,
            transportBreakdown: tBreakdown,
            flights: flightCount,
            flightKm: Int(totalKm.rounded()),
            topAirlines: topAirlines,
            topAirports: topAirports,
            continents: contCount,
            topMonths: topMs,
            longestTripDays: longest,
            longestTripCountry: longestCountry,
            longestTripFlag: longestFlag,
            totalTrips: yearTrips.count
        )
    }

    private static func kmAlong(iatas: [String]) -> Double {
        guard iatas.count >= 2 else { return 0 }
        var km = 0.0
        for i in 0..<(iatas.count - 1) {
            guard let a = AirportCoordinates.coordinate(for: iatas[i]),
                  let b = AirportCoordinates.coordinate(for: iatas[i + 1]) else { continue }
            km += haversineKm(a, b)
        }
        return km
    }

    private static func haversineKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let R = 6371.0
        let φ1 = a.latitude * .pi / 180
        let φ2 = b.latitude * .pi / 180
        let dφ = (b.latitude - a.latitude) * .pi / 180
        let dλ = (b.longitude - a.longitude) * .pi / 180
        let x = sin(dφ/2) * sin(dφ/2) + cos(φ1) * cos(φ2) * sin(dλ/2) * sin(dλ/2)
        return R * 2 * atan2(sqrt(x), sqrt(1 - x))
    }
}

// MARK: - Slide enum + gradients

private enum WrappedSlide {
    case intro
    case countries
    case newCountries
    case transports
    case flights
    case topAirline
    case topAirport
    case continents
    case topMonth
    case longestTrip
    case outro
}

private enum WrappedGradient {
    static func forSlide(_ s: WrappedSlide) -> LinearGradient {
        switch s {
        case .intro:
            return grad([(0x0B, 0x12, 0x2E), (0x2E, 0x0A, 0x57), (0x7A, 0x1E, 0x9E)])
        case .countries:
            return grad([(0x06, 0x2C, 0x5C), (0x10, 0x70, 0xC4), (0x3A, 0xC4, 0xF0)])
        case .newCountries:
            return grad([(0x0B, 0x45, 0x2A), (0x24, 0x90, 0x5C), (0x6E, 0xD2, 0x8C)])
        case .transports:
            return grad([(0x21, 0x07, 0x3A), (0x6C, 0x1A, 0x93), (0xD4, 0x4B, 0xD4)])
        case .flights:
            return grad([(0x0A, 0x1F, 0x4B), (0x1E, 0x5B, 0xB8), (0x78, 0xB4, 0xFF)])
        case .topAirline:
            return grad([(0x2E, 0x10, 0x0A), (0xB3, 0x3A, 0x1C), (0xEF, 0x8A, 0x3D)])
        case .topAirport:
            return grad([(0x1A, 0x22, 0x4B), (0x3C, 0x4F, 0xA5), (0x89, 0xAA, 0xFF)])
        case .continents:
            return grad([(0x12, 0x3A, 0x2C), (0x24, 0x7A, 0x5C), (0x88, 0xE8, 0xB4)])
        case .topMonth:
            return grad([(0x3A, 0x1F, 0x05), (0xD4, 0x7A, 0x1E), (0xFF, 0xC8, 0x5C)])
        case .longestTrip:
            return grad([(0x14, 0x1A, 0x3E), (0x55, 0x2C, 0xA3), (0xC1, 0x6F, 0xD4)])
        case .outro:
            return grad([(0x07, 0x0C, 0x24), (0x3A, 0x1F, 0x6E), (0xE4, 0x53, 0xC4)])
        }
    }
    private static func grad(_ rgbs: [(Int, Int, Int)]) -> LinearGradient {
        LinearGradient(colors: rgbs.map { Color(red: Double($0.0)/255, green: Double($0.1)/255, blue: Double($0.2)/255) },
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Sheet

struct YearWrappedSheet: View {
    let trips: [Trip]
    let allFeatures: [CountryFeature]

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int = 0
    @State private var progress: CGFloat = 0
    @State private var isPaused: Bool = false
    @State private var animKick: Bool = false
    @State private var cachedStats: WrappedStats? = nil
    private let tickInterval: CGFloat = 0.05
    private let slideDuration: CGFloat = 5.0
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var targetYear: Int {
        Calendar.current.component(.year, from: Date()) - 1
    }

    private var stats: WrappedStats {
        cachedStats ?? WrappedStats.empty
    }

    private var activeSlides: [WrappedSlide] {
        var list: [WrappedSlide] = [.intro]
        if stats.totalCountries > 0 || stats.totalTerritories > 0 { list.append(.countries) }
        if (stats.newCountries + stats.newTerritories) > 0 { list.append(.newCountries) }
        if stats.totalSegments > 0 { list.append(.transports) }
        if stats.flights > 0 { list.append(.flights) }
        if !stats.topAirlines.isEmpty { list.append(.topAirline) }
        if !stats.topAirports.isEmpty { list.append(.topAirport) }
        if stats.continents > 0 { list.append(.continents) }
        if !stats.topMonths.isEmpty { list.append(.topMonth) }
        if stats.longestTripDays > 1 { list.append(.longestTrip) }
        list.append(.outro)
        return list
    }

    var body: some View {
        ZStack {
            if cachedStats == nil {
                WrappedGradient.forSlide(.intro).ignoresSafeArea()
            } else if stats.totalTrips == 0 {
                emptyStateView
            } else {
                storyContent
            }
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .onAppear {
            if cachedStats == nil {
                cachedStats = WrappedStats.compute(year: targetYear, trips: trips, allFeatures: allFeatures)
            }
        }
    }

    // MARK: empty state (slide único si el año no tiene viajes)

    @ViewBuilder
    private var emptyStateView: some View {
        ZStack {
            WrappedGradient.forSlide(.intro).ignoresSafeArea()

            // Header story-like (sin progress bars, con botón cerrar)
            VStack {
                HStack {
                    Text(String(targetYear))
                        .font(.custom("Satoshi-Bold", size: 12))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.18), in: Circle())
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 26)
                Spacer()
            }

            VStack(spacing: 18) {
                Text("🗺️")
                    .font(.system(size: 84))
                    .opacity(animKick ? 1 : 0)
                    .scaleEffect(animKick ? 1 : 0.6)
                    .rotationEffect(.degrees(animKick ? 0 : -15))

                VStack(spacing: 8) {
                    Text("ESTE AÑO")
                        .font(.custom("Satoshi-Bold", size: 13))
                        .tracking(5)
                        .foregroundStyle(.white.opacity(0.75))
                    Text("no viajaste")
                        .font(.custom("Satoshi-Bold", size: 42))
                        .foregroundStyle(.white)
                        .opacity(animKick ? 1 : 0)
                        .offset(y: animKick ? 0 : 16)
                }

                Text("¡El año que viene vuelve a intentarlo!\nEl mundo sigue esperándote ✈️")
                    .font(.custom("Satoshi-Regular", size: 15))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 4)
                    .opacity(animKick ? 1 : 0)

                Button { dismiss() } label: {
                    Text("Cerrar")
                        .font(.custom("Satoshi-Bold", size: 15))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white, in: Capsule())
                }
                .padding(.horizontal, 60)
                .padding(.top, 22)
            }
        }
        .onAppear { kickAnimation() }
    }

    // MARK: story content

    @ViewBuilder
    private var storyContent: some View {
        let slides = activeSlides
        let current = slides[min(index, slides.count - 1)]
        ZStack {
            WrappedGradient.forSlide(current)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.45), value: index)

            slideBody(current)
                .id(index)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                    removal: .opacity
                ))

            VStack(spacing: 0) {
                progressBars(count: slides.count)
                    .padding(.top, 14).padding(.horizontal, 14)
                HStack {
                    Text(String(targetYear))
                        .font(.custom("Satoshi-Bold", size: 12))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.18), in: Circle())
                    }
                }
                .padding(.horizontal, 18).padding(.top, 12)
                Spacer()
            }

            // Invisible touch layer — tap = navegar, mantener pulsado = pausa.
            //
            // En el OUTRO la configuramos distinto: el outro tiene botones
            // explícitos (Compartir / Volver a empezar) en la zona inferior que
            // NO deben ser interceptados por el touch layer (si lo fueran, un
            // tap en "Compartir" se interpretaba como tap→advance→dismiss,
            // cerrando la hoja sin compartir). Solución:
            //  - Limitamos el touch layer a la parte SUPERIOR (padding-bottom
            //    grande), así los botones del final quedan fuera de la capa.
            //  - tap-right y swipe-left ya no avanzan (evita dismiss sorpresa).
            //  - tap-left y swipe-right siguen funcionando → volver a slides
            //    anteriores desde el outro, como el usuario pidió.
            //  - swipe-down cierra la hoja (coherente con el resto de slides).
            if current == .outro {
                StoryTouchLayer(
                    onTapLeft:  { goBack() },
                    onTapRight: { },                       // no-op: no dismiss
                    onPressChange: { pressing in isPaused = pressing },
                    onSwipeLeft:  { },                     // no-op
                    onSwipeRight: { goBack() },
                    onSwipeDown:  { dismiss() }
                )
                .padding(.top, 80)
                .padding(.bottom, 280)                     // deja libre la zona de los botones
            } else {
                StoryTouchLayer(
                    onTapLeft:  { goBack() },
                    onTapRight: { advance() },
                    onPressChange: { pressing in isPaused = pressing },
                    onSwipeLeft:  { advance() },
                    onSwipeRight: { goBack() },
                    onSwipeDown:  { dismiss() }
                )
                .padding(.top, 80)
            }
        }
        .onReceive(timer) { _ in
            guard !isPaused else { return }
            // En el outro no auto-avanzamos — el usuario decide si comparte,
            // reinicia o cierra. Evita el cierre sorpresa mientras lee.
            if current == .outro { return }
            progress = min(progress + tickInterval / slideDuration, 1.0)
            if progress >= 1.0 { advance() }
        }
        .onAppear { kickAnimation() }
        .onChange(of: index) { _, _ in kickAnimation() }
    }

    // MARK: Progress bars

    @ViewBuilder
    private func progressBars(count: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25))
                        Capsule().fill(Color.white)
                            .frame(width: i < index ? geo.size.width :
                                   i == index ? geo.size.width * progress : 0)
                    }
                }
                .frame(height: 3)
            }
        }
    }

    // MARK: navigation

    private func advance() {
        let slides = activeSlides
        if index < slides.count - 1 {
            withAnimation(.easeInOut(duration: 0.3)) {
                index += 1
                progress = 0
            }
        } else {
            dismiss()
        }
    }

    private func goBack() {
        if index > 0 {
            withAnimation(.easeInOut(duration: 0.3)) {
                index -= 1
                progress = 0
            }
        } else {
            progress = 0
        }
    }

    private func kickAnimation() {
        animKick = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) {
                animKick = true
            }
        }
    }

    // MARK: Slide bodies

    @ViewBuilder
    private func slideBody(_ slide: WrappedSlide) -> some View {
        switch slide {
        case .intro:        introSlide
        case .countries:    countriesSlide
        case .newCountries: newCountriesSlide
        case .transports:   transportsSlide
        case .flights:      flightsSlide
        case .topAirline:   topAirlineSlide
        case .topAirport:   topAirportSlide
        case .continents:   continentsSlide
        case .topMonth:     topMonthSlide
        case .longestTrip:  longestTripSlide
        case .outro:        outroSlide
        }
    }

    // ── Intro
    private var introSlide: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("TU AÑO EN")
                .font(.custom("Satoshi-Bold", size: 14))
                .tracking(6)
                .foregroundStyle(.white.opacity(0.75))
                .opacity(animKick ? 1 : 0)
                .offset(y: animKick ? 0 : 12)
            Text("Raskmap")
                .font(.custom("Satoshi-Bold", size: 42))
                .foregroundStyle(.white)
                .opacity(animKick ? 1 : 0)
                .offset(y: animKick ? 0 : 20)
            Text(String(targetYear))
                .font(.custom("Satoshi-Bold", size: 140))
                .foregroundStyle(.white)
                .scaleEffect(animKick ? 1 : 0.6)
                .opacity(animKick ? 1 : 0)
                .padding(.top, 18)
            Spacer()
            Text("Toca para empezar →")
                .font(.custom("Satoshi-Regular", size: 13))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.bottom, 60)
        }
    }

    // ── Countries (+territorios)
    private var countriesSlide: some View {
        let totalAll = stats.totalCountries + stats.totalTerritories
        return VStack(spacing: 18) {
            Spacer()
            Text("HAS VISITADO")
                .font(.custom("Satoshi-Bold", size: 12))
                .tracking(4)
                .foregroundStyle(.white.opacity(0.7))
            BigCountingNumber(value: totalAll, trigger: animKick)
                .foregroundStyle(.white)
            Text(totalAll == 1 ? "destino" : "destinos")
                .font(.custom("Satoshi-Bold", size: 26))
                .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: 22) {
                countriesBadge(number: stats.totalCountries, label: stats.totalCountries == 1 ? "país" : "países")
                if stats.totalTerritories > 0 {
                    countriesBadge(number: stats.totalTerritories, label: stats.totalTerritories == 1 ? "territorio" : "territorios")
                }
            }
            .padding(.top, 4)

            if !stats.allVisitedDestinations.isEmpty {
                allVisitedFlagsGrid(stats.allVisitedDestinations)
                    .padding(.top, 14)
                    .padding(.horizontal, 20)
                // Solo decimos "al que más volviste" si realmente repetiste ese país.
                // Con 1 viaje al #1 no hay base para declarar un "favorito".
                if stats.topCountryTripCount > 1, let first = stats.topCountryNames.first {
                    Text("Al que más volviste: \(first) · \(stats.topCountryTripCount) viajes")
                        .font(.custom("Satoshi-Regular", size: 14))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 6)
                        .opacity(animKick ? 1 : 0)
                }
            }
            Spacer()
        }
    }

    /// Rejilla adaptativa con TODAS las banderas de destinos visitados. Escala
    /// tamaño según cantidad para que quepan sin scrollar. Para destinos sin
    /// flag emoji (🌐) mostramos una cápsula con el nombre en su lugar.
    @ViewBuilder
    private func allVisitedFlagsGrid(_ items: [(flag: String, name: String)]) -> some View {
        let flagSize: CGFloat = Self.flagSize(forCount: items.count, largeMode: true)
        let spacing: CGFloat = items.count > 14 ? 6 : 10
        let cols: [GridItem] = [GridItem(.adaptive(minimum: flagSize + 8), spacing: spacing)]
        LazyVGrid(columns: cols, spacing: spacing) {
            ForEach(Array(items.enumerated()), id: \.offset) { pair in
                flagCell(item: pair.element, index: pair.offset, flagSize: flagSize, delayStep: 0.05)
            }
        }
    }

    /// Celda individual de bandera — extraída para que el type-checker no
    /// tenga que resolver el ViewBuilder entero de la rejilla de golpe.
    @ViewBuilder
    private func flagCell(item: (flag: String, name: String),
                          index: Int,
                          flagSize: CGFloat,
                          delayStep: Double) -> some View {
        let delay: Double = min(0.8, 0.15 + Double(index) * delayStep)
        if item.flag == "🌐" {
            nameChip(name: item.name, flagSize: flagSize, delay: delay)
        } else {
            flagGlyph(flag: item.flag, flagSize: flagSize, delay: delay)
        }
    }

    @ViewBuilder
    private func nameChip(name: String, flagSize: CGFloat, delay: Double) -> some View {
        let fontSize: CGFloat = max(10, flagSize * 0.28)
        Text(name)
            .font(.custom("Satoshi-Bold", size: fontSize))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.18))
            )
            .opacity(animKick ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(delay), value: animKick)
    }

    @ViewBuilder
    private func flagGlyph(flag: String, flagSize: CGFloat, delay: Double) -> some View {
        FlagLabel(emoji: flag, size: flagSize)
            .scaleEffect(animKick ? 1 : 0.3)
            .opacity(animKick ? 1 : 0)
            .animation(.spring(response: 0.55, dampingFraction: 0.65).delay(delay),
                       value: animKick)
    }

    /// Tamaño adaptativo de bandera según cuántos destinos haya.
    private static func flagSize(forCount count: Int, largeMode: Bool) -> CGFloat {
        if largeMode {
            switch count {
            case 0...4:   return 50
            case 5...8:   return 42
            case 9...14:  return 34
            case 15...24: return 28
            default:      return 22
            }
        } else {
            switch count {
            case 0...4:   return 34
            case 5...8:   return 30
            case 9...14:  return 26
            case 15...24: return 22
            default:      return 18
            }
        }
    }

    @ViewBuilder
    private func countriesBadge(number: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(number)")
                .font(.custom("Satoshi-Bold", size: 30))
                .foregroundStyle(.white)
            Text(label)
                .font(.custom("Satoshi-Regular", size: 12))
                .foregroundStyle(.white.opacity(0.7))
                .textCase(.uppercase)
                .tracking(1.5)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // ── Nuevos países (con banderas de los nuevos y de los repetidos)
    private var newCountriesSlide: some View {
        let totalNew = stats.newCountries + stats.newTerritories
        let totalRepeated = stats.repeatedDestinations.count
        return VStack(spacing: 14) {
            Spacer(minLength: 8)
            Text("POR PRIMERA VEZ")
                .font(.custom("Satoshi-Bold", size: 12))
                .tracking(4)
                .foregroundStyle(.white.opacity(0.7))
            BigCountingNumber(value: totalNew, trigger: animKick)
                .foregroundStyle(.white)
            Text(totalNew == 1 ? "destino nuevo" : "destinos nuevos")
                .font(.custom("Satoshi-Bold", size: 24))
                .foregroundStyle(.white.opacity(0.9))

            if !stats.newDestinations.isEmpty {
                destinationFlagRow(stats.newDestinations)
                    .padding(.top, 4)
            }

            if totalRepeated > 0 {
                Divider()
                    .background(Color.white.opacity(0.2))
                    .padding(.horizontal, 60)
                    .padding(.vertical, 4)
                Text("y \(totalRepeated) \(totalRepeated == 1 ? "que repetiste" : "que repetiste")")
                    .font(.custom("Satoshi-Bold", size: 16))
                    .foregroundStyle(.white.opacity(0.8))
                destinationFlagRow(stats.repeatedDestinations)
            }
            Spacer()
        }
    }

    /// Rejilla adaptativa con TODAS las banderas (sin truncar). Si un destino
    /// no tiene flag emoji (🌐), se muestra una cápsula con el nombre.
    @ViewBuilder
    private func destinationFlagRow(_ items: [(flag: String, name: String)]) -> some View {
        let flagSize: CGFloat = Self.flagSize(forCount: items.count, largeMode: false)
        let spacing: CGFloat = items.count > 14 ? 5 : 8
        let cols: [GridItem] = [GridItem(.adaptive(minimum: flagSize + 6), spacing: spacing)]
        LazyVGrid(columns: cols, spacing: spacing) {
            ForEach(Array(items.enumerated()), id: \.offset) { pair in
                flagCell(item: pair.element, index: pair.offset, flagSize: flagSize, delayStep: 0.05)
            }
        }
        .padding(.horizontal, 24)
    }

    // ── Transports
    private var transportsSlide: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("TUS MEDIOS")
                .font(.custom("Satoshi-Bold", size: 12))
                .tracking(4)
                .foregroundStyle(.white.opacity(0.7))
            BigCountingNumber(value: stats.totalSegments, trigger: animKick)
                .foregroundStyle(.white)
            Text(stats.totalSegments == 1 ? "trayecto" : "trayectos")
                .font(.custom("Satoshi-Bold", size: 26))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.bottom, 14)
            VStack(spacing: 10) {
                let maxVal = stats.transportBreakdown.first?.count ?? 1
                let items = Array(stats.transportBreakdown.prefix(5))
                ForEach(items, id: \.emoji) { item in
                    let i = items.firstIndex(where: { $0.emoji == item.emoji }) ?? 0
                    HStack(spacing: 14) {
                        Text(item.emoji).font(.system(size: 28)).frame(width: 40)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.18))
                                Capsule().fill(.white)
                                    .frame(width: animKick ? geo.size.width * CGFloat(item.count) / CGFloat(maxVal) : 0)
                                    .animation(.spring(response: 0.8, dampingFraction: 0.8)
                                        .delay(0.25 + Double(i) * 0.12), value: animKick)
                            }
                        }
                        .frame(height: 10)
                        Text("\(item.count)")
                            .font(.custom("Satoshi-Bold", size: 18))
                            .foregroundStyle(.white)
                            .frame(width: 36, alignment: .trailing)
                    }
                    .opacity(animKick ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.15 + Double(i) * 0.1), value: animKick)
                }
            }
            .padding(.horizontal, 38)
            Spacer()
        }
    }

    // ── Flights
    private var flightsSlide: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("EN EL AIRE")
                .font(.custom("Satoshi-Bold", size: 12))
                .tracking(4)
                .foregroundStyle(.white.opacity(0.7))
            BigCountingNumber(value: stats.flights, trigger: animKick)
                .foregroundStyle(.white)
            Text(stats.flights == 1 ? "vuelo" : "vuelos")
                .font(.custom("Satoshi-Bold", size: 26))
                .foregroundStyle(.white.opacity(0.9))
            if stats.flightKm > 0 {
                Text("≈ \(numberString(stats.flightKm)) km recorridos")
                    .font(.custom("Satoshi-Bold", size: 17))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 20)
                    .opacity(animKick ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(0.4), value: animKick)
                if stats.flightKm >= 40_075 {
                    Text("¡Más de una vuelta al mundo! 🌍")
                        .font(.custom("Satoshi-Regular", size: 14))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.top, 4)
                } else {
                    let pct = Int((Double(stats.flightKm) / 40_075.0) * 100)
                    Text("≈ \(pct)% de la vuelta al mundo")
                        .font(.custom("Satoshi-Regular", size: 14))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.top, 4)
                }
            }
            Spacer()
        }
    }

    // ── Top 3 aerolíneas
    private var topAirlineSlide: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("TUS AEROLÍNEAS")
                .font(.custom("Satoshi-Bold", size: 12))
                .tracking(4)
                .foregroundStyle(.white.opacity(0.7))
            Text("✈️").font(.system(size: 56))
                .scaleEffect(animKick ? 1 : 0.4)
                .rotationEffect(.degrees(animKick ? 0 : -20))
                .padding(.bottom, 6)

            VStack(spacing: 10) {
                ForEach(Array(stats.topAirlines.enumerated()), id: \.element.name) { i, a in
                    rankingRow(rank: i + 1, title: a.name, trailing: "\(a.count) \(a.count == 1 ? "vuelo" : "vuelos")", delay: Double(i) * 0.12)
                }
            }
            .padding(.horizontal, 32)
            Spacer()
        }
    }

    // ── Top 3 aeropuertos
    private var topAirportSlide: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("POR AQUÍ HAS PASADO MÁS")
                .font(.custom("Satoshi-Bold", size: 12))
                .tracking(4)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let ap = stats.topAirports.first {
                Text(ap.iata)
                    .font(.custom("Satoshi-Bold", size: 92))
                    .foregroundStyle(.white)
                    .scaleEffect(animKick ? 1 : 0.5)
                Text(ap.name)
                    .font(.custom("Satoshi-Regular", size: 15))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .opacity(animKick ? 1 : 0)
                Text("\(ap.count) \(ap.count == 1 ? "vez" : "veces")")
                    .font(.custom("Satoshi-Bold", size: 20))
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.top, 4)
                    .opacity(animKick ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.2), value: animKick)
            }

            if stats.topAirports.count > 1 {
                VStack(spacing: 8) {
                    ForEach(Array(stats.topAirports.dropFirst().enumerated()), id: \.element.iata) { i, ap in
                        rankingRow(rank: i + 2, title: ap.iata, trailing: "\(ap.count)", delay: Double(i + 1) * 0.1)
                    }
                }
                .padding(.horizontal, 44)
                .padding(.top, 10)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func rankingRow(rank: Int, title: String, trailing: String, delay: Double) -> some View {
        HStack(spacing: 14) {
            Text("\(rank)")
                .font(.custom("Satoshi-Bold", size: 24))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 24, alignment: .leading)
            Text(title)
                .font(.custom("Satoshi-Bold", size: 18))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            Text(trailing)
                .font(.custom("Satoshi-Regular", size: 14))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(animKick ? 1 : 0)
        .offset(y: animKick ? 0 : 10)
        .animation(.easeOut(duration: 0.4).delay(0.15 + delay), value: animKick)
    }

    // ── Continents
    private var continentsSlide: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("CONTINENTES").font(.custom("Satoshi-Bold", size: 12)).tracking(4)
                .foregroundStyle(.white.opacity(0.7))
            BigCountingNumber(value: stats.continents, trigger: animKick)
                .foregroundStyle(.white)
            Text("de los 5")
                .font(.custom("Satoshi-Bold", size: 26))
                .foregroundStyle(.white.opacity(0.9))
            Text(continentMessage)
                .font(.custom("Satoshi-Regular", size: 15))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 8)
            Spacer()
        }
    }

    private var continentMessage: String {
        switch stats.continents {
        case 5: return "¡Has pisado todos los continentes! 🌍"
        case 4: return "Te faltó uno para darle la vuelta al planeta."
        case 3: return "Tres continentes distintos en un año. 💪"
        case 2: return "Saltando entre dos continentes."
        default: return "Enfocado en un continente."
        }
    }

    // ── Top month (acepta empates y muestra todos a la vez)
    private var topMonthSlide: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(stats.topMonths.count > 1 ? "TUS MESES MÁS VIAJEROS" : "TU MES MÁS VIAJERO")
                .font(.custom("Satoshi-Bold", size: 12)).tracking(4)
                .foregroundStyle(.white.opacity(0.7))

            if stats.topMonths.count <= 1, let m = stats.topMonths.first {
                Text(monthName(m.month).uppercased())
                    .font(.custom("Satoshi-Bold", size: 58))
                    .foregroundStyle(.white)
                    .scaleEffect(animKick ? 1 : 0.6)
                    .opacity(animKick ? 1 : 0)
                Text("\(m.count) \(m.count == 1 ? "viaje" : "viajes")")
                    .font(.custom("Satoshi-Bold", size: 22))
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                // Empate: listamos todos los meses con su nombre
                let count = stats.topMonths.first?.count ?? 0
                VStack(spacing: 6) {
                    ForEach(Array(stats.topMonths.enumerated()), id: \.element.month) { i, m in
                        Text(monthName(m.month).uppercased())
                            .font(.custom("Satoshi-Bold", size: stats.topMonths.count > 3 ? 34 : 44))
                            .foregroundStyle(.white)
                            .scaleEffect(animKick ? 1 : 0.7)
                            .opacity(animKick ? 1 : 0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.75)
                                .delay(0.15 + Double(i) * 0.1), value: animKick)
                    }
                }
                .padding(.vertical, 6)
                Text("\(count) \(count == 1 ? "viaje cada uno" : "viajes cada uno")")
                    .font(.custom("Satoshi-Bold", size: 18))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 4)
                Text("empate múltiple 🤝")
                    .font(.custom("Satoshi-Regular", size: 13))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.top, 2)
            }
            Spacer()
        }
    }

    // ── Longest trip — ahora con país
    private var longestTripSlide: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("TU ESTANCIA MÁS LARGA").font(.custom("Satoshi-Bold", size: 12)).tracking(4)
                .foregroundStyle(.white.opacity(0.7))
            BigCountingNumber(value: stats.longestTripDays, trigger: animKick)
                .foregroundStyle(.white)
            Text(stats.longestTripDays == 1 ? "día" : "días seguidos")
                .font(.custom("Satoshi-Bold", size: 26))
                .foregroundStyle(.white.opacity(0.9))
            if let place = stats.longestTripCountry {
                HStack(spacing: 10) {
                    if let flag = stats.longestTripFlag {
                        FlagLabel(emoji: flag, size: 34)
                    }
                    Text("en \(place)")
                        .font(.custom("Satoshi-Bold", size: 20))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.top, 18)
                .opacity(animKick ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.4), value: animKick)
            }
            Spacer()
        }
    }

    // ── Outro (nuevo diseño, apto para compartir 9:16)
    private var outroSlide: some View {
        OutroSlideView(stats: stats,
                       targetYear: targetYear,
                       animKick: animKick,
                       onShare: { share() },
                       onRestart: {
                           withAnimation(.easeInOut(duration: 0.3)) {
                               index = 0
                               progress = 0
                           }
                       })
    }

    // MARK: helpers

    private func monthName(_ m: Int) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "es_ES")
        return df.monthSymbols[max(0, min(11, m - 1))]
    }

    private func numberString(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "."
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    // MARK: - Share (genera una imagen 9:16 con el resumen)
    @MainActor
    private func share() {
        isPaused = true
        let msg = "Mi año \(targetYear) en Raskmap 🗺️"

        // Intentamos renderizar en un Task para que el layout se resuelva
        // antes de pedir la imagen (ImageRenderer a veces devuelve nil si la
        // vista aún no ha pasado por un ciclo de layout).
        Task { @MainActor in
            let image = Self.renderShareImage(stats: stats, year: targetYear)
            var items: [Any] = []
            if let image { items.append(image) }
            items.append(msg)
            Self.presentShareSheet(items: items) { completed in
                self.isPaused = false
                _ = completed
            }
        }
    }

    /// Renderiza la ficha 9:16 a UIImage. Nil si el render falla.
    @MainActor
    private static func renderShareImage(stats: WrappedStats, year: Int) -> UIImage? {
        let card = ShareableSummaryCard(stats: stats, year: year)
            .frame(width: 1080, height: 1920)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 1920)
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Presenta un UIActivityViewController encontrando el VC superior (tolerante
    /// a escenas con varias ventanas y a presentaciones anidadas vía fullScreenCover).
    @MainActor
    private static func presentShareSheet(items: [Any], onComplete: @escaping (Bool) -> Void) {
        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        av.completionWithItemsHandler = { _, completed, _, _ in onComplete(completed) }

        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
              ?? (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        else {
            onComplete(false); return
        }
        let keyWindow = scene.windows.first(where: { $0.isKeyWindow })
            ?? scene.windows.first(where: { !$0.isHidden })
            ?? scene.windows.first
        guard let root = keyWindow?.rootViewController else {
            onComplete(false); return
        }
        var top: UIViewController = root
        while let p = top.presentedViewController, !p.isBeingDismissed { top = p }

        if let pop = av.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        top.present(av, animated: true)
    }
}

// MARK: - Outro (slide dentro del story)

private struct OutroSlideView: View {
    let stats: WrappedStats
    let targetYear: Int
    let animKick: Bool
    let onShare: () -> Void
    let onRestart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            VStack(spacing: 6) {
                Text("ASÍ FUE TU")
                    .font(.custom("Satoshi-Bold", size: 13))
                    .tracking(5)
                    .foregroundStyle(.white.opacity(0.7))
                Text(String(targetYear))
                    .font(.custom("Satoshi-Bold", size: 96))
                    .foregroundStyle(.white)
                    .scaleEffect(animKick ? 1 : 0.5)
            }
            .padding(.top, 10)

            Spacer(minLength: 12)

            SummaryStatGrid(stats: stats)
                .padding(.horizontal, 24)
                .opacity(animKick ? 1 : 0)
                .offset(y: animKick ? 0 : 16)
                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: animKick)

            if !stats.allVisitedDestinations.isEmpty {
                // TODAS las banderas del año — la rejilla se adapta al número
                // de destinos; el tamaño de cada bandera baja cuanto más haya
                // para que quepa sin scroll dentro del outro.
                let count = stats.allVisitedDestinations.count
                let flagSize: CGFloat = {
                    switch count {
                    case 0...6:   return 30
                    case 7...12:  return 26
                    case 13...20: return 22
                    case 21...30: return 18
                    default:      return 15
                    }
                }()
                let spacing: CGFloat = count > 20 ? 4 : 8
                let cols: [GridItem] = [GridItem(.adaptive(minimum: flagSize + 6), spacing: spacing)]
                LazyVGrid(columns: cols, spacing: spacing) {
                    ForEach(Array(stats.allVisitedDestinations.enumerated()), id: \.offset) { pair in
                        if pair.element.flag == "🌐" {
                            Text(pair.element.name)
                                .font(.custom("Satoshi-Bold", size: max(9, flagSize * 0.32)))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Color.white.opacity(0.18))
                                )
                        } else {
                            FlagLabel(emoji: pair.element.flag, size: flagSize)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .opacity(animKick ? 1 : 0)
            }

            Spacer(minLength: 18)

            VStack(spacing: 10) {
                Button(action: onShare) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.up.fill")
                        Text("Compartir mi año")
                    }
                    .font(.custom("Satoshi-Bold", size: 16))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.white, in: Capsule())
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
                }
                .padding(.horizontal, 40)
                Button("Volver a empezar", action: onRestart)
                    .font(.custom("Satoshi-Regular", size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.bottom, 56)
        }
    }
}

// MARK: - Resumen grid (reutilizado en slide + imagen 9:16)

private struct SummaryStatGrid: View {
    let stats: WrappedStats

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                statCard(big: "\(stats.totalCountries + stats.totalTerritories)",
                         label: "destinos",
                         sub: stats.totalTerritories > 0
                            ? "\(stats.totalCountries) países · \(stats.totalTerritories) terr."
                            : (stats.totalCountries == 1 ? "país" : "países"))
                statCard(big: "\(stats.continents)",
                         label: "continentes",
                         sub: "de 5")
            }
            HStack(spacing: 12) {
                statCard(big: "\(stats.totalSegments)",
                         label: stats.totalSegments == 1 ? "trayecto" : "trayectos",
                         sub: "recorridos")
                if stats.flights > 0 {
                    statCard(big: "\(stats.flights)",
                             label: stats.flights == 1 ? "vuelo" : "vuelos",
                             sub: stats.flightKm > 0 ? "≈ \(numberString(stats.flightKm)) km" : nil)
                } else {
                    statCard(big: "\(stats.newCountries + stats.newTerritories)",
                             label: "nuevos",
                             sub: "por primera vez")
                }
            }
        }
    }

    @ViewBuilder
    private func statCard(big: String, label: String, sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(big)
                .font(.custom("Satoshi-Bold", size: 40))
                .foregroundStyle(.white)
            Text(label.uppercased())
                .font(.custom("Satoshi-Bold", size: 11))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.7))
            if let sub, !sub.isEmpty {
                Text(sub)
                    .font(.custom("Satoshi-Regular", size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.7)
        )
    }

    private func numberString(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = "."
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - Imagen 9:16 exportable

private struct ShareableSummaryCard: View {
    let stats: WrappedStats
    let year: Int

    // Canvas fijo 1080x1920 (9:16, formato historia).
    // Rediseño: la composición reparte el espacio en 4 bloques bien definidos
    // (hero · stats · banderas · footer) ocupando todo el alto, en vez de
    // acumular todo el contenido arriba. Cada bloque respira y mantiene un
    // ritmo vertical predecible.
    var body: some View {
        ZStack {
            // 1) Fondo degradado enriquecido con un glow ambiente —
            // evita el look plano y crea profundidad sin competir con el texto.
            LinearGradient(colors: [
                Color(red: 0x04/255, green: 0x07/255, blue: 0x1F/255),
                Color(red: 0x1C/255, green: 0x10/255, blue: 0x48/255),
                Color(red: 0x52/255, green: 0x20/255, blue: 0x9A/255),
                Color(red: 0xE4/255, green: 0x4B/255, blue: 0xC4/255)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)

            // Glows decorativos — grandes, borrosos, sutiles.
            Circle()
                .fill(Color(red: 0xA1/255, green: 0x6B/255, blue: 0xFF/255).opacity(0.28))
                .frame(width: 900, height: 900)
                .blur(radius: 160)
                .offset(x: -260, y: -420)
            Circle()
                .fill(Color(red: 0xFF/255, green: 0x88/255, blue: 0xCA/255).opacity(0.18))
                .frame(width: 820, height: 820)
                .blur(radius: 180)
                .offset(x: 280, y: 520)

            // Capa de contenido — VStack con Spacer()s proporcionales que
            // distribuyen los bloques en todo el alto del canvas.
            VStack(spacing: 0) {

                // ── HERO (año como protagonista) ──────────────────
                VStack(spacing: 12) {
                    Text("ASÍ FUE MI")
                        .font(.custom("Satoshi-Bold", size: 30))
                        .tracking(14)
                        .foregroundStyle(.white.opacity(0.78))
                    Text(String(year))
                        .font(.custom("Satoshi-Bold", size: 280))
                        .foregroundStyle(.white)
                        .shadow(color: Color.black.opacity(0.35), radius: 18, y: 6)
                    Text("EN RASKMAP")
                        .font(.custom("Satoshi-Bold", size: 28))
                        .tracking(12)
                        .foregroundStyle(.white.opacity(0.78))
                }
                .padding(.top, 170)

                Spacer(minLength: 30)

                // Separador fino con puntos — transición visual al bloque stats.
                HStack(spacing: 14) {
                    Circle().fill(Color.white.opacity(0.7)).frame(width: 6, height: 6)
                    Capsule().fill(Color.white.opacity(0.35)).frame(width: 80, height: 2)
                    Circle().fill(Color.white.opacity(0.55)).frame(width: 10, height: 10)
                    Capsule().fill(Color.white.opacity(0.35)).frame(width: 80, height: 2)
                    Circle().fill(Color.white.opacity(0.7)).frame(width: 6, height: 6)
                }
                .padding(.vertical, 6)

                Spacer(minLength: 30)

                // ── STATS (4 tarjetas) ────────────────────────────
                SummaryStatGrid(stats: stats)
                    .padding(.horizontal, 72)
                    .environment(\.sizeCategory, .medium)

                Spacer(minLength: 50)

                // ── BANDERAS (galería con etiqueta y caja) ────────
                if !stats.allVisitedDestinations.isEmpty {
                    flagGallery
                        .padding(.horizontal, 56)
                }

                Spacer(minLength: 30)

                // ── FOOTER (branding con hairline) ────────────────
                VStack(spacing: 18) {
                    Rectangle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 220, height: 0.8)
                    HStack(spacing: 18) {
                        Text("🗺️").font(.system(size: 52))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Raskmap")
                                .font(.custom("Satoshi-Bold", size: 44))
                                .foregroundStyle(.white)
                            Text("Tu mapa personal del mundo")
                                .font(.custom("Satoshi-Regular", size: 22))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }
                .padding(.bottom, 110)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 1080, height: 1920)
    }

    /// Galería de banderas con etiqueta "MIS BANDERAS" y caja redondeada
    /// translúcida. Tamaño adaptativo por cantidad — escala los iconos para
    /// que TODAS las banderas quepan sin hacer scroll.
    @ViewBuilder
    private var flagGallery: some View {
        let count = stats.allVisitedDestinations.count
        let flagSize: CGFloat = {
            switch count {
            case 0...6:   return 92
            case 7...12:  return 78
            case 13...20: return 64
            case 21...30: return 52
            case 31...45: return 42
            default:      return 34
            }
        }()
        let spacing: CGFloat = count > 20 ? 12 : 18
        let cols: [GridItem] = [GridItem(.adaptive(minimum: flagSize + 14), spacing: spacing)]

        VStack(spacing: 20) {
            HStack(spacing: 10) {
                Rectangle().fill(Color.white.opacity(0.55)).frame(width: 22, height: 2)
                Text("MIS BANDERAS")
                    .font(.custom("Satoshi-Bold", size: 16))
                    .tracking(6)
                    .foregroundStyle(.white.opacity(0.85))
                Rectangle().fill(Color.white.opacity(0.55)).frame(width: 22, height: 2)
            }

            LazyVGrid(columns: cols, spacing: spacing) {
                ForEach(Array(stats.allVisitedDestinations.enumerated()), id: \.offset) { pair in
                    if pair.element.flag == "🌐" {
                        Text(pair.element.name)
                            .font(.custom("Satoshi-Bold", size: max(18, flagSize * 0.32)))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.18))
                            )
                    } else {
                        FlagLabel(emoji: pair.element.flag, size: flagSize)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
            )
        }
    }
}

// MARK: - Touch layer (tap navegar + pulsación pausa)

private struct StoryTouchLayer: View {
    let onTapLeft: () -> Void
    let onTapRight: () -> Void
    let onPressChange: (Bool) -> Void
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void
    let onSwipeDown: () -> Void

    @State private var pressStart: Date? = nil
    @State private var startX: CGFloat = 0
    @State private var didSwipe: Bool = false

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if pressStart == nil {
                                pressStart = Date()
                                startX = value.startLocation.x
                                onPressChange(true)
                            }
                        }
                        .onEnded { value in
                            let dur = pressStart.map { Date().timeIntervalSince($0) } ?? 0
                            pressStart = nil
                            onPressChange(false)

                            // swipes
                            if value.translation.height > 120 { onSwipeDown(); return }
                            if value.translation.width < -80 { onSwipeLeft(); return }
                            if value.translation.width > 80  { onSwipeRight(); return }

                            // tap corto = navegar
                            if dur < 0.35 && abs(value.translation.width) < 12 && abs(value.translation.height) < 12 {
                                if startX < geo.size.width / 2 { onTapLeft() } else { onTapRight() }
                            }
                        }
                )
        }
    }
}

// MARK: - Counting number helper

private struct BigCountingNumber: View {
    let value: Int
    let trigger: Bool
    @State private var display: Int = 0

    var body: some View {
        Text("\(display)")
            .font(.custom("Satoshi-Bold", size: 120))
            .monospacedDigit()
            .contentTransition(.numericText())
            .onAppear { animate() }
            .onChange(of: trigger) { _, _ in animate() }
    }

    private func animate() {
        display = 0
        let target = value
        guard target > 0 else { return }
        let steps = min(target, 40)
        let delay = 0.9 / Double(steps)
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay * Double(i)) {
                withAnimation(.easeOut(duration: delay * 1.5)) {
                    display = Int(Double(target) * Double(i) / Double(steps))
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay * Double(steps) + 0.05) {
            display = target
        }
    }
}
