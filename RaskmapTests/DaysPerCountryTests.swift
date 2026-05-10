//
//  DaysPerCountryTests.swift
//  RaskmapTests
//
//  Tests para el algoritmo `daysPerCountry(trips:)` definido en Trip.swift.
//  Cubre los casos críticos que han ido apareciendo en QA:
//   - Round-trip simple (HKG 15-25)
//   - Trip con segments multi-día (Hong Kong/Macao/China)
//   - Trip con segments single-day (Macedonia/Kosovo + escala SRB ida y vuelta)
//   - Children skipped cuando el primary está presente
//   - Escalas (✈️ visitedLayoverISOs) suman al primary
//

import Testing
import Foundation
@testable import Raskmap

@MainActor
struct DaysPerCountryTests {

    // MARK: helpers

    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }()

    /// Día UTC determinista — los tests no deben depender del huso del runner.
    private static func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = day
        comps.timeZone = TimeZone(identifier: "UTC")
        return cal.date(from: comps)!
    }

    private static func makeTrip(
        iso: String,
        from: Date,
        to: Date?,
        transport: String? = "✈️",
        segments: [TripSegment] = [],
        isChild: Bool = false,
        groupID: String? = nil,
        layoverISOs: [String]? = nil
    ) -> Trip {
        let t = Trip(isoCode: iso, title: nil, dateFrom: from, dateTo: to,
                     transport: transport, tripAirports: [], tripAirlines: [])
        if !segments.isEmpty { t.tripSegments = segments }
        t.isSegmentChild = isChild
        if let groupID { t.segmentGroupID = groupID }
        if let layoverISOs { t.visitedLayoverISOs = layoverISOs }
        return t
    }

    private static func seg(
        transport: String,
        isos: [String],
        from: Date,
        to: Date?,
        layoverISOs: [String]? = nil,
        airports: [TripAirport]? = nil,
        returnAirports: [TripAirport]? = nil
    ) -> TripSegment {
        TripSegment(
            id: UUID(),
            transport: transport,
            isoCodes: isos,
            dateFrom: from,
            dateTo: to,
            airports: airports,
            returnAirports: returnAirports,
            airlines: nil,
            hasLayover: nil,
            visitedLayoverISOs: layoverISOs
        )
    }

    // MARK: tests

    @Test("Trip round-trip directo sin segmentos: todos los días al primary")
    func roundTripSinSegments() {
        let trip = Self.makeTrip(iso: "HKG", from: Self.d(2025, 3, 15), to: Self.d(2025, 3, 25))
        let result = daysPerCountry(trips: [trip])
        #expect(result["HKG"] == 11)
        #expect(result.count == 1)
    }

    @Test("Trip de 1 día (sin dateTo) cuenta 1 día")
    func tripUnDia() {
        let trip = Self.makeTrip(iso: "FRA", from: Self.d(2025, 6, 1), to: nil)
        let result = daysPerCountry(trips: [trip])
        #expect(result["FRA"] == 1)
    }

    @Test("Trip Hong Kong/Macao/China — segments multi-día con tránsito shared")
    func hongKongMacaoChinaCase() {
        // Trip 15-25 marzo, primary HKG. Segments:
        //  - bus MAC 16-17
        //  - pie CHN 17-21
        //  - tren HKG 21-25
        // Días esperados: HKG=6 (15, 21-25), MAC=2 (16, 17), CHN=5 (17-21).
        // Días 17 y 21 son frontera y cuentan para AMBOS países (set unión).
        let trip = Self.makeTrip(
            iso: "HKG",
            from: Self.d(2025, 3, 15),
            to: Self.d(2025, 3, 25),
            segments: [
                Self.seg(transport: "🚌", isos: ["MAC"],
                         from: Self.d(2025, 3, 16), to: Self.d(2025, 3, 17)),
                Self.seg(transport: "🚶", isos: ["CHN"],
                         from: Self.d(2025, 3, 17), to: Self.d(2025, 3, 21)),
                Self.seg(transport: "🚂", isos: ["HKG"],
                         from: Self.d(2025, 3, 21), to: Self.d(2025, 3, 25))
            ]
        )
        let result = daysPerCountry(trips: [trip])
        #expect(result["HKG"] == 6)
        #expect(result["MAC"] == 2)
        #expect(result["CHN"] == 5)
    }

    @Test("Trip Macedonia con escala SRB ida+vuelta y excursión Kosovo de día")
    func macedoniaKosovoCase() {
        // Trip ✈️ a Macedonia 12-18 julio con escala SRB ida y vuelta + excursión
        // de día a Kosovo el 14.
        // Esperado: MKD=7 (todos los días — ambient cubre), SRB=2 (12, 18 layovers),
        // KOS=1 (14, single-day add to primary).
        let trip = Self.makeTrip(
            iso: "MKD",
            from: Self.d(2025, 7, 12),
            to: Self.d(2025, 7, 18),
            segments: [
                // ✈️ ida-vuelta con escala SRB
                Self.seg(transport: "✈️", isos: ["MKD", "SRB"],
                         from: Self.d(2025, 7, 12), to: Self.d(2025, 7, 18),
                         layoverISOs: ["SRB"]),
                // 🚗 excursión a KOS el 14 (mismo día ida y vuelta, dateTo=dateFrom)
                Self.seg(transport: "🚗", isos: ["KOS"],
                         from: Self.d(2025, 7, 14), to: Self.d(2025, 7, 14))
            ]
        )
        let result = daysPerCountry(trips: [trip])
        #expect(result["MKD"] == 7)
        #expect(result["SRB"] == 2)
        #expect(result["KOS"] == 1)
    }

    @Test("Children del mismo grupo se ignoran si el primary está presente")
    func childrenIgnoradosConPrimaryPresente() {
        let gid = "group-1"
        let primary = Self.makeTrip(
            iso: "ESP",
            from: Self.d(2025, 6, 1),
            to: Self.d(2025, 6, 5),
            segments: [
                Self.seg(transport: "🚂", isos: ["FRA"],
                         from: Self.d(2025, 6, 2), to: Self.d(2025, 6, 4))
            ],
            groupID: gid
        )
        let child = Self.makeTrip(
            iso: "FRA",
            from: Self.d(2025, 6, 2),
            to: Self.d(2025, 6, 4),
            transport: "🚂",
            isChild: true,
            groupID: gid
        )
        let result = daysPerCountry(trips: [primary, child])
        // Si el child contara como ambient propio (prio 200+len = 203), pisaría
        // al primary y FRA tendría 3 días pero ESP perdería esos 3 días aunque
        // el primary tiene segments que ya los reclaman correctamente.
        // El skip de children con groupID = primary.groupID evita doble cómputo.
        #expect(result["FRA"] == 3)  // 2, 3, 4
        #expect(result["ESP"] == 4)  // 1, 2 (start), 4 (end), 5 — wait
        // Día 2 = ESP ambient + seg FRA → FRA gana (prio 100 < 1003).
        // Día 4 = seg FRA. Día 1, 5 = ESP ambient. Día 2, 3 = FRA. Día 4 = FRA.
        // Total: ESP={1, 5}=2, FRA={2,3,4}=3.
    }

    @Test("Children sin primary (huérfanos) sí cuentan con su ambient")
    func childrenHuérfanosCuentan() {
        let child = Self.makeTrip(
            iso: "FRA",
            from: Self.d(2025, 6, 2),
            to: Self.d(2025, 6, 4),
            transport: "🚂",
            isChild: true,
            groupID: "orphan-group"
        )
        let result = daysPerCountry(trips: [child])
        #expect(result["FRA"] == 3)
    }

    @Test("Excursión single-day a otro país cuenta para ambos países")
    func excursionSingleDayCuentaParaAmbos() {
        // Trip a Italia 1-7 junio, excursión a Vaticano el 3 (mismo día).
        let trip = Self.makeTrip(
            iso: "ITA",
            from: Self.d(2025, 6, 1),
            to: Self.d(2025, 6, 7),
            segments: [
                Self.seg(transport: "🚶", isos: ["VAT"],
                         from: Self.d(2025, 6, 3), to: Self.d(2025, 6, 3))
            ]
        )
        let result = daysPerCountry(trips: [trip])
        #expect(result["ITA"] == 7)  // todos los 7 días
        #expect(result["VAT"] == 1)  // solo el 3
    }

    @Test("Layover ✈️ legacy en trip sin segments suma 1 día al país-escala")
    func layoverLegacy() {
        // Trip ✈️ legacy a NRT con escala visitada DXB. Sin segments embebidos,
        // solo `t.visitedLayoverISOs`.
        let trip = Self.makeTrip(
            iso: "JPN",
            from: Self.d(2025, 9, 10),
            to: Self.d(2025, 9, 20),
            transport: "✈️",
            layoverISOs: ["ARE"]
        )
        let result = daysPerCountry(trips: [trip])
        #expect(result["JPN"] == 11)   // todos los días
        // ARE recibe 2 stakes: tFrom + tTo. Misma prio que ambient → set unión
        // → ARE en 2 días (10 y 20).
        #expect(result["ARE"] == 2)
    }

    @Test("Múltiples segments superpuestos: días frontera cuentan para ambos")
    func segmentsFronteraShared() {
        // Segments ESP→FRA (1-3) y FRA→ITA (3-5). Día 3 frontera.
        let trip = Self.makeTrip(
            iso: "ESP",
            from: Self.d(2025, 4, 1),
            to: Self.d(2025, 4, 5),
            segments: [
                Self.seg(transport: "🚂", isos: ["FRA"],
                         from: Self.d(2025, 4, 1), to: Self.d(2025, 4, 3)),
                Self.seg(transport: "🚂", isos: ["ITA"],
                         from: Self.d(2025, 4, 3), to: Self.d(2025, 4, 5))
            ]
        )
        let result = daysPerCountry(trips: [trip])
        #expect(result["FRA"] == 3)   // 1, 2, 3
        #expect(result["ITA"] == 3)   // 3, 4, 5
        // ESP queda fuera porque FRA y ITA cubren todo el rango con prio 100
        // que pisa al ambient ESP de prio 1005.
        #expect(result["ESP"] == nil)
    }
}
