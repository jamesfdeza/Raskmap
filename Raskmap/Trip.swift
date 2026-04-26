//
//  Trip.swift
//  Raskmap
//
import Foundation
import SwiftData

/// Datos asiento/clase de un único tramo de vuelo.
/// Un vuelo MAD→DXB→NRT ida+vuelta tiene 4 tramos: MAD-DXB, DXB-NRT, NRT-DXB, DXB-MAD.
struct FlightLegInfo: Codable, Equatable {
    var seatNumber: String = ""
    var seatPosition: String = ""  // "" | "pasillo" | "medio" | "ventana"
    var cabinClass: String = ""    // "" | "turista" | "economy+" | "business" | "first"

    var hasAnyData: Bool { !seatNumber.isEmpty || !seatPosition.isEmpty || !cabinClass.isEmpty }
}

struct FlightInfo: Codable, Equatable {
    var bookingRef: String = ""
    // MARK: Legacy scalars (kept para compat con datos antiguos que nunca tuvieron tramos)
    var seatNumber: String = ""
    var seatPosition: String = ""  // "" | "pasillo" | "medio" | "ventana"
    var cabinClass: String = ""    // "" | "turista" | "economy+" | "business" | "first"
    // MARK: Per-leg data
    var outboundLegs: [FlightLegInfo] = []
    var returnLegs: [FlightLegInfo] = []

    var hasAnyData: Bool {
        !bookingRef.isEmpty
            || !seatNumber.isEmpty || !seatPosition.isEmpty || !cabinClass.isEmpty
            || outboundLegs.contains(where: { $0.hasAnyData })
            || returnLegs.contains(where: { $0.hasAnyData })
    }

    /// Todos los tramos (ida + vuelta). Si no hay tramos pero sí datos legacy escalares,
    /// devuelve un tramo sintético con esos datos para no perder información en stats.
    var allLegs: [FlightLegInfo] {
        let combined = outboundLegs + returnLegs
        if !combined.isEmpty { return combined }
        let legacy = FlightLegInfo(seatNumber: seatNumber, seatPosition: seatPosition, cabinClass: cabinClass)
        return legacy.hasAnyData ? [legacy] : []
    }
}

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
        get {
            guard let raw = flightInfoRaw, let data = raw.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(FlightInfo.self, from: data)
        }
        set {
            guard let info = newValue, info.hasAnyData else { flightInfoRaw = nil; return }
            flightInfoRaw = (try? JSONEncoder().encode(info)).flatMap { String(data: $0, encoding: .utf8) }
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

private struct _DayClaim {
    var iso: String
    var priority: Int   // smaller = wins
}

/// Recorre una lista de trips y devuelve el diccionario `iso → nº de días`
/// aplicando la prioridad por especificidad descrita arriba. Se usa desde
/// `daysSpent(iso:trips:)` y desde los stats anuales (YearWrappedSheet).
func daysPerCountry(trips: [Trip]) -> [String: Int] {
    let cal = Calendar.current
    var claims: [Date: _DayClaim] = [:]

    func stake(iso: String, from: Date, to: Date, priority: Int) {
        guard !iso.isEmpty else { return }
        let f = cal.startOfDay(for: from)
        let t = cal.startOfDay(for: to)
        guard t >= f else { return }
        var d = f
        while d <= t {
            if let existing = claims[d] {
                if priority < existing.priority {
                    claims[d] = _DayClaim(iso: iso, priority: priority)
                }
            } else {
                claims[d] = _DayClaim(iso: iso, priority: priority)
            }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d.addingTimeInterval(86400)
        }
    }

    for t in trips {
        let tFrom = cal.startOfDay(for: t.dateFrom)
        let tTo   = cal.startOfDay(for: t.dateTo ?? t.dateFrom)
        let tripLen = max(1, (cal.dateComponents([.day], from: tFrom, to: tTo).day ?? 0) + 1)

        // Prioridad base del trip:
        //   - Hijo de grupo (isSegmentChild) → 200 + len  (fuerte, pero deja
        //     que los segmentos internos del primario también ganen si existen).
        //   - Independiente / primario       → 1000 + len
        //   Nota: "+ len" hace que entre dos trips del mismo tipo gane el más corto.
        let tripPriority = (t.isSegmentChild ? 200 : 1000) + tripLen
        stake(iso: t.isoCode, from: tFrom, to: tTo, priority: tripPriority)

        // Segmentos embebidos del trip primario. Si están presentes con
        // distintos isoCodes y fechas, son la fuente MÁS granular — ganan
        // por encima de cualquier trip "ambiental".
        let segs = t.tripSegments.sorted { $0.dateFrom < $1.dateFrom }
        // Si el trip NO tiene segmentos pero sí tiene escalas marcadas a nivel
        // trip (`visitedLayoverISOsRaw`), reclamamos cada escala como 1 día
        // (día de salida `tFrom`) con prio 50 — gana sobre la estancia ambient.
        // Cubre trips ✈️ legacy editados desde el wizard de `EditTripSheet`.
        guard !segs.isEmpty else {
            for layoverIso in t.visitedLayoverISOs ?? [] where !layoverIso.isEmpty {
                stake(iso: layoverIso, from: tFrom, to: tFrom, priority: 50)
            }
            continue
        }

        var currentIso = t.isoCode
        var currentStart = tFrom
        for seg in segs {
            let segStart = cal.startOfDay(for: seg.dateFrom)
            // Antes del segmento, el usuario estaba en `currentIso`.
            if segStart > currentStart {
                let prevDay = cal.date(byAdding: .day, value: -1, to: segStart) ?? segStart
                stake(iso: currentIso, from: currentStart, to: prevDay, priority: 100)
            } else if segStart == currentStart {
                // Si el segment cae en el mismo día que currentStart, reclamamos ese día
                // explícitamente para currentIso antes de transicionar.
                stake(iso: currentIso, from: currentStart, to: currentStart, priority: 100)
            }
            // Transición: el destino del segment pasa a ser el país actual.
            // IMPORTANTE: las escalas (visitedLayoverISOs) NO son destino — son países
            // de tránsito. Las excluimos de los candidatos a "currentIso" y las
            // reclamamos por separado abajo (1 día cada una).
            let layoverSet = Set(seg.visitedLayoverISOs ?? [])
            let isos = seg.isoCodes.filter { !$0.isEmpty }
            let nonLayoverIsos = isos.filter { !layoverSet.contains($0) }
            let candidates = nonLayoverIsos.filter { $0 != currentIso }
            if let dest = candidates.first ?? nonLayoverIsos.last ?? isos.first { currentIso = dest }
            currentStart = cal.startOfDay(for: seg.dateTo ?? seg.dateFrom)

            // Cada escala visitada cuenta como 1 día — reclamamos el día del
            // segmento (típicamente el día del vuelo). Prioridad MUY alta (50)
            // para que gane sobre cualquier "stay" del mismo día y se asegure
            // que la escala efectivamente cuenta.
            for layoverIso in layoverSet where !layoverIso.isEmpty {
                stake(iso: layoverIso, from: segStart, to: segStart, priority: 50)
            }
        }
        // Desde el último segment hasta el fin del trip, el usuario está en currentIso.
        if tTo >= currentStart {
            stake(iso: currentIso, from: currentStart, to: tTo, priority: 100)
        }
    }

    var out: [String: Int] = [:]
    for claim in claims.values { out[claim.iso, default: 0] += 1 }
    return out
}

/// Días pasados en un país concreto. Delega en `daysPerCountry(trips:)` para
/// garantizar consistencia entre la app, el widget y el wrapped anual.
func daysSpent(iso: String, trips: [Trip]) -> Int {
    daysPerCountry(trips: trips)[iso] ?? 0
}
