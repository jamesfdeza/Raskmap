//
//  FlightInfo.swift
//  Raskmap
//
//  Datos de vuelo embebidos en `Trip.flightInfoRaw` y `TripSegment.flightInfo`.
//  Vivían en `Trip.swift` pero se separan para que la conformancia Codable
//  de Swift 6 no herede el aislamiento `@MainActor` del `@Model` Trip.
//

import Foundation

/// Datos asiento/clase de un único tramo de vuelo.
/// Un vuelo MAD→DXB→NRT ida+vuelta tiene 4 tramos: MAD-DXB, DXB-NRT, NRT-DXB, DXB-MAD.
struct FlightLegInfo: Equatable, Sendable {
    var seatNumber: String = ""
    var seatPosition: String = ""  // "" | "pasillo" | "medio" | "ventana"
    var cabinClass: String = ""    // "" | "turista" | "economy+" | "business" | "first"

    var hasAnyData: Bool { !seatNumber.isEmpty || !seatPosition.isEmpty || !cabinClass.isEmpty }
}

/// Codable manual (no sintetizado) — Swift 6 sintetiza Codable con
/// aislamiento heredado del contexto, lo que provoca el error
/// "Main actor-isolated conformance ... cannot be used in nonisolated context"
/// cuando se llama desde computed properties de `@Model class Trip`.
/// La implementación manual queda explícitamente nonisolated.
extension FlightLegInfo: Codable {
    enum CodingKeys: String, CodingKey {
        case seatNumber, seatPosition, cabinClass
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.seatNumber   = try c.decodeIfPresent(String.self, forKey: .seatNumber) ?? ""
        self.seatPosition = try c.decodeIfPresent(String.self, forKey: .seatPosition) ?? ""
        self.cabinClass   = try c.decodeIfPresent(String.self, forKey: .cabinClass) ?? ""
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(seatNumber,   forKey: .seatNumber)
        try c.encode(seatPosition, forKey: .seatPosition)
        try c.encode(cabinClass,   forKey: .cabinClass)
    }
}

struct FlightInfo: Equatable, Sendable {
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

extension FlightInfo: Codable {
    enum CodingKeys: String, CodingKey {
        case bookingRef, seatNumber, seatPosition, cabinClass, outboundLegs, returnLegs
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.bookingRef   = try c.decodeIfPresent(String.self,           forKey: .bookingRef) ?? ""
        self.seatNumber   = try c.decodeIfPresent(String.self,           forKey: .seatNumber) ?? ""
        self.seatPosition = try c.decodeIfPresent(String.self,           forKey: .seatPosition) ?? ""
        self.cabinClass   = try c.decodeIfPresent(String.self,           forKey: .cabinClass) ?? ""
        self.outboundLegs = try c.decodeIfPresent([FlightLegInfo].self,  forKey: .outboundLegs) ?? []
        self.returnLegs   = try c.decodeIfPresent([FlightLegInfo].self,  forKey: .returnLegs) ?? []
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bookingRef,   forKey: .bookingRef)
        try c.encode(seatNumber,   forKey: .seatNumber)
        try c.encode(seatPosition, forKey: .seatPosition)
        try c.encode(cabinClass,   forKey: .cabinClass)
        try c.encode(outboundLegs, forKey: .outboundLegs)
        try c.encode(returnLegs,   forKey: .returnLegs)
    }
}

/// Helpers para encode/decode desde callsites cuyo contexto de aislamiento
/// (p.ej. computed properties dentro de `@Model class Trip`) puede confundir
/// al inferidor de Swift 6 sobre la conformancia de `FlightInfo` a Codable.
/// Marcados `nonisolated` para forzar contexto plano.
nonisolated func decodeFlightInfo(from raw: String?) -> FlightInfo? {
    guard let raw, let data = raw.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(FlightInfo.self, from: data)
}

nonisolated func encodeFlightInfo(_ info: FlightInfo) -> String? {
    (try? JSONEncoder().encode(info)).flatMap { String(data: $0, encoding: .utf8) }
}
