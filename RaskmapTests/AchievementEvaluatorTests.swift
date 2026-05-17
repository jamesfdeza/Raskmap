//
//  AchievementEvaluatorTests.swift
//  RaskmapTests
//
//  Tests de INTEGRACIÓN para AchievementEvaluator — verifican que dados
//  trips + countries + settings, los logros correctos se desbloquean.
//
//  Antes esta lógica vivía dentro de `ContentView.multiContAchievedNow`
//  y era imposible de testear sin levantar SwiftData + MainActor.
//  Tras extraerla a `AchievementEvaluator` (pure struct) se pueden
//  testear escenarios completos con builds sintéticas de datos.
//

import Testing
import Foundation
@testable import Raskmap

@MainActor
struct AchievementEvaluatorTests {

    // MARK: - helpers

    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }()

    private static func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = day
        comps.timeZone = TimeZone(identifier: "UTC")
        return cal.date(from: comps)!
    }

    private static func trip(
        iso: String,
        from: Date,
        to: Date? = nil,
        transport: String? = nil,
        isChild: Bool = false,
        segments: [TripSegment] = []
    ) -> Trip {
        let t = Trip(isoCode: iso, title: nil, dateFrom: from, dateTo: to,
                     transport: transport, tripAirports: [], tripAirlines: [])
        t.isSegmentChild = isChild
        if !segments.isEmpty { t.tripSegments = segments }
        return t
    }

    private static func country(_ iso: String, status: CountryStatus = .visited) -> Country {
        let c = Country(isoCode: iso, name: iso, status: status)
        return c
    }

    // MARK: - tests

    @Test("firstTrip: se desbloquea con cualquier trip pasado")
    func firstTrip() {
        let trip = Self.trip(iso: "FRA", from: Self.d(2024, 5, 1))
        let eval = AchievementEvaluator(
            trips: [trip], countries: [Self.country("FRA")],
            countingMode: .all,
            now: Self.d(2025, 1, 1)
        )
        let result = eval.evaluate()
        #expect(result.contains(.firstTrip))
    }

    @Test("firstTrip: NO se desbloquea sin trips pasados")
    func firstTripNoPasados() {
        let trip = Self.trip(iso: "FRA", from: Self.d(2026, 5, 1))  // futuro
        let eval = AchievementEvaluator(
            trips: [trip], countries: [],
            countingMode: .all,
            now: Self.d(2025, 1, 1)
        )
        let result = eval.evaluate()
        #expect(!result.contains(.firstTrip))
    }

    @Test("trips5: requiere 5 trips primarios pasados")
    func trips5Threshold() {
        let trips = (0..<5).map { i in
            Self.trip(iso: "C\(i)", from: Self.d(2024, 1, i + 1))
        }
        let eval = AchievementEvaluator(
            trips: trips, countries: [],
            countingMode: .all,
            now: Self.d(2025, 1, 1)
        )
        let result = eval.evaluate()
        #expect(result.contains(.trips5))
        #expect(!result.contains(.trips10))
    }

    @Test("trips5: children NO cuentan")
    func trips5IgnoraChildren() {
        let trips = (0..<5).map { i in
            Self.trip(iso: "C\(i)", from: Self.d(2024, 1, i + 1), isChild: true)
        }
        let eval = AchievementEvaluator(
            trips: trips, countries: [],
            countingMode: .all,
            now: Self.d(2025, 1, 1)
        )
        let result = eval.evaluate()
        #expect(!result.contains(.trips5))
    }

    @Test("paises50: requiere 50 países visitados según countingMode")
    func paises50_DinamicoSegunModo() {
        // 50 ISOs visitados — 30 son ONU, 20 son territorios no-ONU.
        let unISOs = ["FRA", "DEU", "ESP", "ITA", "GBR", "USA", "MEX", "CAN", "BRA", "ARG",
                      "JPN", "CHN", "IND", "AUS", "NZL", "ZAF", "EGY", "MAR", "DZA", "NGA",
                      "KEN", "RUS", "POL", "PRT", "GRC", "NOR", "SWE", "DNK", "FIN", "ISL"]  // 30 ONU
        let nonUNISOs = ["HKG", "MAC", "TWN", "PSE", "VAT", "PRI", "GRL", "FRO", "GIB", "BMU",
                         "CYM", "VGB", "VIR", "AIA", "ABW", "CUW", "SXM", "TCA", "MSR", "KOS"]  // 20 no-ONU
        let countries = (unISOs + nonUNISOs).map { Self.country($0) }

        // Modo .all: cuenta todos los 50 → centurion no, paises50 sí.
        let evalAll = AchievementEvaluator(
            trips: [], countries: countries,
            countingMode: .all
        )
        let resultAll = evalAll.evaluate()
        #expect(resultAll.contains(.paises50))
        #expect(!resultAll.contains(.centurion))

        // Modo .un: solo 30 ONU → paises25 sí, paises50 NO.
        let evalUN = AchievementEvaluator(
            trips: [], countries: countries,
            countingMode: .un
        )
        let resultUN = evalUN.evaluate()
        #expect(resultUN.contains(.paises25))
        #expect(!resultUN.contains(.paises50))
    }

    @Test("todosG7: requiere los 7 países del G7 visitados")
    func todosG7() {
        let g7 = ["CAN", "FRA", "DEU", "ITA", "JPN", "GBR", "USA"]
        let countries = g7.map { Self.country($0) }
        let eval = AchievementEvaluator(
            trips: [], countries: countries,
            countingMode: .un
        )
        let result = eval.evaluate()
        #expect(result.contains(.todosG7))
    }

    @Test("todosG7: falla si falta 1")
    func todosG7Falla() {
        let g7 = ["CAN", "FRA", "DEU", "ITA", "JPN", "GBR"]  // sin USA
        let countries = g7.map { Self.country($0) }
        let eval = AchievementEvaluator(
            trips: [], countries: countries,
            countingMode: .un
        )
        let result = eval.evaluate()
        #expect(!result.contains(.todosG7))
    }

    @Test("daytrip: trip de 1 día desbloquea")
    func daytrip() {
        let trip = Self.trip(iso: "FRA", from: Self.d(2024, 5, 1), to: Self.d(2024, 5, 1))
        let eval = AchievementEvaluator(
            trips: [trip], countries: [],
            countingMode: .all,
            now: Self.d(2025, 1, 1)
        )
        let result = eval.evaluate()
        #expect(result.contains(.daytrip))
    }

    @Test("sabbatical: trip >30 días desbloquea")
    func sabbatical() {
        let trip = Self.trip(iso: "FRA", from: Self.d(2024, 5, 1), to: Self.d(2024, 6, 5))  // 35 días
        let eval = AchievementEvaluator(
            trips: [trip], countries: [],
            countingMode: .all,
            now: Self.d(2025, 1, 1)
        )
        let result = eval.evaluate()
        #expect(result.contains(.sabbatical))
        #expect(!result.contains(.nomada))  // requiere >90
    }

    @Test("nomada: trip >90 días desbloquea sabbatical + nomada")
    func nomada() {
        let trip = Self.trip(iso: "FRA", from: Self.d(2024, 5, 1), to: Self.d(2024, 8, 15))  // 106 días
        let eval = AchievementEvaluator(
            trips: [trip], countries: [],
            countingMode: .all,
            now: Self.d(2025, 1, 1)
        )
        let result = eval.evaluate()
        #expect(result.contains(.sabbatical))
        #expect(result.contains(.nomada))
    }

    @Test("anoCompletoViajero: requiere trips en los 12 meses (cualquier año)")
    func anoCompletoViajero() {
        // 12 trips, uno por mes, en años distintos — debe contar como completo.
        let trips = (1...12).map { m in
            Self.trip(iso: "C\(m)", from: Self.d(2020 + m, m, 15))
        }
        let eval = AchievementEvaluator(
            trips: trips, countries: [],
            countingMode: .all,
            now: Self.d(2033, 1, 1)
        )
        let result = eval.evaluate()
        #expect(result.contains(.anoCompletoViajero))
    }

    @Test("anoCompletoViajero: 11 meses NO basta")
    func anoCompletoViajeroFalla() {
        let trips = (1...11).map { m in
            Self.trip(iso: "C\(m)", from: Self.d(2024, m, 15))
        }
        let eval = AchievementEvaluator(
            trips: trips, countries: [],
            countingMode: .all,
            now: Self.d(2025, 1, 1)
        )
        let result = eval.evaluate()
        #expect(!result.contains(.anoCompletoViajero))
    }

    @Test("viajeroNavideno: trip 28 dic - 5 ene desbloquea")
    func viajeroNavideno() {
        let trip = Self.trip(iso: "FRA", from: Self.d(2024, 12, 28), to: Self.d(2025, 1, 5))
        let eval = AchievementEvaluator(
            trips: [trip], countries: [],
            countingMode: .all,
            now: Self.d(2025, 6, 1)
        )
        let result = eval.evaluate()
        #expect(result.contains(.viajeroNavideno))
    }

    @Test("sieteMaravillas: 7 ids marcadas desbloquea")
    func sieteMaravillas() {
        let raw = #"["a","b","c","d","e","f","g"]"#
        let eval = AchievementEvaluator(
            trips: [], countries: [],
            countingMode: .all,
            modernWondersRaw: raw
        )
        let result = eval.evaluate()
        #expect(result.contains(.sieteMaravillas))
    }

    @Test("sieteMaravillas: 6 ids NO basta")
    func sieteMaravillasFalla() {
        let raw = #"["a","b","c","d","e","f"]"#
        let eval = AchievementEvaluator(
            trips: [], countries: [],
            countingMode: .all,
            modernWondersRaw: raw
        )
        let result = eval.evaluate()
        #expect(!result.contains(.sieteMaravillas))
    }

    @Test("medioMundo: requiere 50% del denominator del modo")
    func medioMundo() {
        // Modo .un (193) → necesita 97. Hago 100 ONU members visitados.
        let isos = Array(CountingMode.unMembers.prefix(100))
        let countries = isos.map { Self.country($0) }
        let eval = AchievementEvaluator(
            trips: [], countries: countries,
            countingMode: .un
        )
        let result = eval.evaluate()
        #expect(result.contains(.medioMundo))
    }

    @Test("medioMundo: 50 ONU members NO basta (necesita 97)")
    func medioMundoFalla() {
        let isos = Array(CountingMode.unMembers.prefix(50))
        let countries = isos.map { Self.country($0) }
        let eval = AchievementEvaluator(
            trips: [], countries: countries,
            countingMode: .un
        )
        let result = eval.evaluate()
        #expect(!result.contains(.medioMundo))
    }

    @Test("ambosHemisferios: requiere norte Y sur visitados")
    func ambosHemisferios() {
        let countries = [
            Self.country("FRA"),  // norte
            Self.country("ARG"),  // sur
        ]
        let eval = AchievementEvaluator(
            trips: [], countries: countries,
            countingMode: .un
        )
        let result = eval.evaluate()
        #expect(result.contains(.ambosHemisferios))
    }

    @Test("ambosHemisferios: solo norte NO basta")
    func ambosHemisferiosFalla() {
        let countries = [Self.country("FRA"), Self.country("DEU")]
        let eval = AchievementEvaluator(
            trips: [], countries: countries,
            countingMode: .un
        )
        let result = eval.evaluate()
        #expect(!result.contains(.ambosHemisferios))
    }

    @Test("segundaCasa: mismo país 5+ trips desbloquea")
    func segundaCasa() {
        let trips = (0..<5).map { i in
            Self.trip(iso: "FRA", from: Self.d(2024, 1, i + 1))
        }
        let eval = AchievementEvaluator(
            trips: trips, countries: [],
            countingMode: .all,
            now: Self.d(2025, 1, 1)
        )
        let result = eval.evaluate()
        #expect(result.contains(.segundaCasa))
        #expect(!result.contains(.querencia))  // requiere 10
    }
}
