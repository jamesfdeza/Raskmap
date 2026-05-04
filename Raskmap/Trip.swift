//
//  Trip.swift
//  Raskmap
//
import Foundation
import SwiftData

// FlightInfo + FlightLegInfo viven en `FlightInfo.swift` para que la
// conformancia Codable no herede el aislamiento `@MainActor` del `@Model`
// Trip (error de Swift 6: "Main actor-isolated conformance ... cannot be
// used in nonisolated context").

struct TripAirport: Codable, Hashable, Sendable {
    let iata: String
    var count: Int
}

struct TripAirline: Codable, Hashable, Sendable {
    let name: String
    var count: Int
}

struct TripSegment: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var transport: String
    var isoCodes: [String]
    var dateFrom: Date
    var dateTo: Date?
    var airports: [TripAirport]?         // Outbound route airports (ordered) — ✈️ only
    var returnAirports: [TripAirport]?   // Return route airports (ordered, nil = one-way) — ✈️ only
    var airlines: [TripAirline]?         // Only for ✈️ segments
    var hasLayover: Bool?                // Only for ✈️ segments
    var visitedLayoverISOs: [String]?    // ISO A3 codes of visited layover countries
    var flightInfo: FlightInfo?          // Optional booking/seat/class info — ✈️ only
}

@Model
class Trip {
    var isoCode: String = ""
    var title: String?
    var dateFrom: Date = Date()
    var dateTo: Date?
    var transport: String?
    var hasLayover: Bool = false
    var airport: String?          // Legacy single airport
    var airportsRaw: String?      // JSON-encoded [TripAirport]
    var airlinesRaw: String?      // JSON-encoded [TripAirline]
    var airlineCountsRaw: String? // Legacy - kept for migration
    var createdAt: Date = Date()
    var segmentsRaw: String?      // JSON-encoded [TripSegment]
    var segmentGroupID: String?   // Groups primary + child trips from same multi-transport save
    var isSegmentChild: Bool = false
    var flightInfoRaw: String?    // JSON-encoded FlightInfo — only for non-segment ✈️ trips
    /// JSON-encoded `[String]` (ISO A3) — escalas marcadas como visitadas en
    /// trips ✈️ legacy SIN segmentos. Para trips segment-based, las escalas
    /// viven en `seg.visitedLayoverISOs`. `daysPerCountry` lee de ambas fuentes.
    var visitedLayoverISOsRaw: String?

    init(isoCode: String, title: String? = nil, dateFrom: Date, dateTo: Date? = nil,
         transport: String? = nil,
         tripAirports: [TripAirport] = [], tripAirlines: [TripAirline] = []) {
        self.isoCode = isoCode
        self.title = title
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.transport = transport
        self.airport = nil
        self.airlineCountsRaw = nil
        self.airportsRaw = tripAirports.isEmpty ? nil :
            (try? JSONEncoder().encode(tripAirports)).flatMap { String(data: $0, encoding: .utf8) }
        self.airlinesRaw = tripAirlines.isEmpty ? nil :
            (try? JSONEncoder().encode(tripAirlines)).flatMap { String(data: $0, encoding: .utf8) }
        self.createdAt = Date()
    }

    var tripAirports: [TripAirport] {
        get {
            var result: [TripAirport] = []
            if let raw = airportsRaw, let data = raw.data(using: .utf8) {
                if let arr = try? JSONDecoder().decode([TripAirport].self, from: data) {
                    result = arr
                } else if let arr = try? JSONDecoder().decode([String].self, from: data) {
                    // Legacy [String] format
                    result = arr.map { TripAirport(iata: $0, count: 1) }
                } else if let arr = try? JSONDecoder().decode([[String: String]].self, from: data) {
                    // Legacy TripAirport with roundTrip bool
                    result = arr.compactMap { d in
                        guard let iata = d["iata"] else { return nil }
                        return TripAirport(iata: iata, count: d["roundTrip"] == "true" ? 2 : 1)
                    }
                }
            }
            // Migrate legacy single airport field
            if let legacy = airport, !legacy.isEmpty, !result.contains(where: { $0.iata == legacy }) {
                result.insert(TripAirport(iata: legacy, count: 1), at: 0)
            }
            return result
        }
        set {
            airportsRaw = newValue.isEmpty ? nil :
                (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) }
            if !newValue.isEmpty { airport = nil }
        }
    }

    var tripAirlines: [TripAirline] {
        get {
            guard let raw = airlinesRaw, let data = raw.data(using: .utf8) else { return [] }
            if let arr = try? JSONDecoder().decode([TripAirline].self, from: data) { return arr }
            // Legacy [String] format
            if let arr = try? JSONDecoder().decode([String].self, from: data) {
                // Check airlineCountsRaw for manual counts
                var counts: [String: Int] = [:]
                if let cr = airlineCountsRaw, let cd = cr.data(using: .utf8),
                   let dict = try? JSONDecoder().decode([String: Int].self, from: cd) {
                    counts = dict
                }
                return arr.map { TripAirline(name: $0, count: counts[$0] ?? 1) }
            }
            return []
        }
        set {
            airlinesRaw = newValue.isEmpty ? nil :
                (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    var tripSegments: [TripSegment] {
        get {
            guard let raw = segmentsRaw, let data = raw.data(using: .utf8) else { return [] }
            // Always return segments in chronological order (by `dateFrom`).
            // El orden de inserción NO importa: los vuelos/tramos deben verse
            // siempre por fecha en cualquier sitio (add, edit, detalle, stats).
            let arr = (try? JSONDecoder().decode([TripSegment].self, from: data)) ?? []
            return arr.sorted { $0.dateFrom < $1.dateFrom }
        }
        set {
            // Persist already sorted to that storage matches what the UI shows
            // and any non-sorted reader still gets cronological order.
            let sorted = newValue.sorted { $0.dateFrom < $1.dateFrom }
            segmentsRaw = sorted.isEmpty ? nil :
                (try? JSONEncoder().encode(sorted)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    var flightDetails: FlightInfo? {
        get { decodeFlightInfo(from: flightInfoRaw) }
        set {
            guard let info = newValue, info.hasAnyData else { flightInfoRaw = nil; return }
            flightInfoRaw = encodeFlightInfo(info)
        }
    }

    /// Escalas marcadas como visitadas para trips ✈️ legacy SIN segmentos.
    /// Setear con `[]` o `nil` borra el raw para no contaminar el JSON.
    var visitedLayoverISOs: [String]? {
        get {
            guard let raw = visitedLayoverISOsRaw, let data = raw.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([String].self, from: data)
        }
        set {
            guard let arr = newValue, !arr.isEmpty else { visitedLayoverISOsRaw = nil; return }
            visitedLayoverISOsRaw = (try? JSONEncoder().encode(arr)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    // Convenience
    var airports: [String] { tripAirports.map { $0.iata } }
    var airlines: [String] { tripAirlines.map { $0.name } }

    var airportCountForStats: [String: Int] {
        Dictionary(tripAirports.map { ($0.iata, $0.count) }, uniquingKeysWith: +)
    }

    var year: Int { Calendar.current.component(.year, from: dateTo ?? dateFrom) }
    var effectiveEndDate: Date { dateTo ?? dateFrom }
}

// MARK: - Día a día: asignación quirúrgica por país
//
// Algoritmo basado en intervalos por día. Cada día del calendario se atribuye
// a UN solo país — el usuario no puede estar en dos sitios a la vez.
// Cuando varios viajes cubren el mismo día, gana el claim más específico:
//
//   Prioridad (menor = más específico = gana):
//     1  — Segment interno dentro de un trip primario (distintos isoCodes y
//          fechas concretas). El paso más granular disponible.
//     2  — Trip hijo (`isSegmentChild == true`). Parte explícita de un grupo.
//     3  — Trip independiente pequeño. Rango corto = asunción más concreta.
//     N  — Trip más largo. Cobertura "ambiental" — típicamente el país origen
//          o el que contiene al resto en el tiempo.
//
// Ejemplos que maneja bien:
//   • HKG 1–11 + bus→MAC día 4 + pie→CHN día 6 + tren→HKG día 9
//       → HKG: días 1-3 + 9-11 = 6   | MAC: 4-5 = 2   | CHN: 6-8 = 3
//   • HKG 1–11 como trip independiente, MAC 4–6 aparte, CHN 7–9 aparte
//       → igual distribución por prioridad de rango corto.
//   • Grupo multi-transport (primary HKG + children MAC, CHN con `isSegmentChild`)
//       → los children ganan sus días (prio 2), el resto queda para HKG.

/// Conjunto de ISOs que reclaman un día concreto en una capa de prioridad
/// dada. La capa con la prioridad MÁS BAJA gana; si dos ISOs reclaman el
/// mismo día en la MISMA capa, AMBOS cuentan (regla de "días de tránsito":
/// el día que vuelas/cruzas frontera cuenta para los dos países).
private struct _DaySet {
    var isos: Set<String>
    var priority: Int   // smaller = wins
}

/// Recorre una lista de trips y devuelve el diccionario `iso → nº de días`.
///
/// Modelo: cada día tiene una capa de "claims" con su prioridad. La capa
/// activa para un día es siempre la de prioridad MÁS BAJA vista (más
/// específica). Si dos segmentos solapan rangos a la misma prioridad —
/// p.ej. el día 17 está en el rango "Macao 16–17" y "China 17–21" — ambos
/// países reclaman ese día como tránsito.
///
/// Prioridades:
///   50  — Layover (escala). 1 día por escala.
///   100 — Segmento embebido en trip primario. Reclama todo `[segDateFrom, segDateTo]`
///         para su destino. Múltiples segmentos en mismo día → tránsito (set unión).
///   200 + len — Trip hijo (`isSegmentChild`).
///   1000+ len — Trip primario "ambiental". Solo rellena días no cubiertos por
///         segmentos a más alta prioridad.
func daysPerCountry(trips: [Trip]) -> [String: Int] {
    let cal = Calendar.current
    var claims: [Date: _DaySet] = [:]

    func stake(iso: String, from: Date, to: Date, priority: Int) {
        guard !iso.isEmpty else { return }
        let f = cal.startOfDay(for: from)
        let t = cal.startOfDay(for: to)
        guard t >= f else { return }
        var d = f
        while d <= t {
            if let existing = claims[d] {
                if priority < existing.priority {
                    claims[d] = _DaySet(isos: [iso], priority: priority)
                } else if priority == existing.priority {
                    var s = existing
                    s.isos.insert(iso)
                    claims[d] = s
                }
                // else: capa con prioridad superior, ignoramos
            } else {
                claims[d] = _DaySet(isos: [iso], priority: priority)
            }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d.addingTimeInterval(86400)
        }
    }

    // Indexamos los segmentos del primario por groupID para detectar children
    // huérfanos (sin primary) — solo en ese caso el child contribuye al stake;
    // si el primary existe, el algoritmo usa los segments embebidos del primary
    // y los children quedan ignorados aquí (su rol es aparecer en listas de
    // país, no recontar días).
    let primaryGroupIDs: Set<String> = Set(trips.compactMap { $0.isSegmentChild ? nil : $0.segmentGroupID })

    for t in trips {
        // Skip children cuyo primary también está en el conjunto: el primary
        // ya cubre todos los días vía sus segments embebidos. Stakearíamos
        // dos veces con prioridades distintas y los children, al ser de 1 día,
        // ganan por prioridad y desplazan al primary haciendo perder días al
        // país-base del trip.
        if t.isSegmentChild, let gid = t.segmentGroupID, primaryGroupIDs.contains(gid) {
            continue
        }

        let tFrom = cal.startOfDay(for: t.dateFrom)
        let tTo   = cal.startOfDay(for: t.dateTo ?? t.dateFrom)
        let tripLen = max(1, (cal.dateComponents([.day], from: tFrom, to: tTo).day ?? 0) + 1)
        let tripPriority = (t.isSegmentChild ? 200 : 1000) + tripLen

        // 1) Trip ambiental: cubre todo el rango. Si no hay segmentos, esta es
        //    la única fuente. Si hay segmentos, los segmentos sobrescriben los
        //    días que toquen.
        stake(iso: t.isoCode, from: tFrom, to: tTo, priority: tripPriority)

        let segs = t.tripSegments.sorted { $0.dateFrom < $1.dateFrom }
        // Caso sin segmentos: aplicar layovers a nivel trip si los hay.
        // Las escalas se reclaman como 1 día compartido con el primary
        // (mismo prio que ambient → set unión). El día de la escala cuenta
        // tanto para el país-escala como para el destino del trip.
        guard !segs.isEmpty else {
            for layoverIso in t.visitedLayoverISOs ?? [] where !layoverIso.isEmpty {
                stake(iso: layoverIso, from: tFrom, to: tFrom, priority: tripPriority)
                if tTo != tFrom {
                    stake(iso: layoverIso, from: tTo, to: tTo, priority: tripPriority)
                }
            }
            continue
        }

        // 2) Segmentos no-✈️ (bus, tren, pie, etc.):
        //    - Multi-día (`dateTo > dateFrom`): el usuario está físicamente en
        //      el destino esos días. REEMPLAZA al primary del trip ambient
        //      (prio 100 < 1011). Días en frontera con otro segmento se
        //      comparten (ambos destinos reclamados a prio 100).
        //    - Single-día (`dateTo == dateFrom` o `dateTo == nil`): excursión
        //      de día — el usuario va y vuelve el mismo día. AÑADE al primary
        //      sin reemplazar (mismo prio 1011 que el ambient → set unión),
        //      así el día cuenta tanto para el destino como para el primary.
        //
        //    EXCEPCIÓN ✈️: las fechas de un segmento ✈️ son los días del vuelo,
        //    no la estancia en destino. NO reclamamos el destino — el ambient
        //    del trip ya lo cubre. Solo procesamos sus escalas (un día cada una).
        let nonFlightSegs = segs.filter { $0.transport != "✈️" }
        for (i, seg) in nonFlightSegs.enumerated() {
            let segStart = cal.startOfDay(for: seg.dateFrom)
            let segEndExplicit = seg.dateTo.map { cal.startOfDay(for: $0) }
            let isSingleDay = segEndExplicit == nil || segEndExplicit == segStart
            let layoverSet = Set(seg.visitedLayoverISOs ?? [])
            let isos = seg.isoCodes.filter { !$0.isEmpty }
            let nonLayoverIsos = isos.filter { !layoverSet.contains($0) }
            let destPick = nonLayoverIsos.first(where: { $0 != t.isoCode })
                            ?? nonLayoverIsos.first
                            ?? isos.first
            if let dest = destPick {
                if isSingleDay {
                    // Excursión de día: añade dest al primary (prio = ambient).
                    stake(iso: dest, from: segStart, to: segStart, priority: tripPriority)
                } else if let segEnd = segEndExplicit {
                    // Estancia multi-día explícita: reemplaza al primary.
                    stake(iso: dest, from: segStart, to: segEnd, priority: 100)
                } else {
                    // Multi-día implícito: extiende hasta el siguiente segmento
                    // o fin del trip (puente de tránsito shared).
                    let inferredEnd: Date = {
                        if i + 1 < nonFlightSegs.count {
                            return cal.startOfDay(for: nonFlightSegs[i + 1].dateFrom)
                        }
                        return tTo
                    }()
                    stake(iso: dest, from: segStart, to: inferredEnd, priority: 100)
                }
            }
            // Layovers de cualquier transport: 1 día compartido con primary
            // (prio = ambient para que se sume sin desplazar al primary).
            for layoverIso in layoverSet where !layoverIso.isEmpty {
                stake(iso: layoverIso, from: segStart, to: segStart, priority: tripPriority)
            }
        }
        // 3) Escalas de segmentos ✈️: reclaman tanto el día de la ida (segStart)
        //    como el de la vuelta (segDateTo) si existe. Se añaden al primary
        //    sin desplazarlo (mismo prio que ambient).
        for seg in segs where seg.transport == "✈️" {
            let segStart = cal.startOfDay(for: seg.dateFrom)
            let segEnd = seg.dateTo.map { cal.startOfDay(for: $0) }
            for layoverIso in seg.visitedLayoverISOs ?? [] where !layoverIso.isEmpty {
                stake(iso: layoverIso, from: segStart, to: segStart, priority: tripPriority)
                if let end = segEnd, end != segStart {
                    stake(iso: layoverIso, from: end, to: end, priority: tripPriority)
                }
            }
        }
    }

    var out: [String: Int] = [:]
    for claim in claims.values {
        for iso in claim.isos { out[iso, default: 0] += 1 }
    }
    return out
}

/// Días pasados en un país concreto. Delega en `daysPerCountry(trips:)` para
/// garantizar consistencia entre la app, el widget y el wrapped anual.
func daysSpent(iso: String, trips: [Trip]) -> Int {
    daysPerCountry(trips: trips)[iso] ?? 0
}
