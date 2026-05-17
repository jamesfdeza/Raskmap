//
//  AchievementKindTests.swift
//  RaskmapTests
//
//  Tests para las funciones estáticas puras de `AchievementKind`:
//   · `adjustSet(_:forZone:assignments:)` — ajuste de sets de ISO por
//     asignación pluricontinental (RUS, TUR, EGY, etc.).
//   · `adjustedHemispheres(assignments:)` — ajuste hemisférico
//     (BRA, ECU, KEN, etc.).
//   · `macroContinent(for:)` — mapping ISO → macro-continente.
//   · Helpers `zoneIsoCodes`, `regionIsoCodes`, `medalOrder`, `medal`.
//
//  Cobertura del sistema de logros que antes era 0 — ahora cubre los
//  cálculos pure que alimentan `multiContAchievedNow` y ProfileSheet.
//  Los flujos enteros con SwiftData (Trip+Country queries) no se testean
//  aquí — requieren refactor para extraer la lógica de evaluación a
//  funciones puras testables.
//

import Testing
import Foundation
@testable import Raskmap

@MainActor
struct AchievementKindTests {

    // MARK: - adjustSet (pluricontinentales)

    @Test("adjustSet: RUS asignado a 'asia' lo saca de Europa y lo mete en Asia")
    func adjustSetRusiaAsia() {
        let assignments: [String: String] = ["RUS": "asia"]
        // Europa "completa" (subset): incluye RUS por default.
        let europeBase: Set<String> = ["FRA", "DEU", "ESP", "RUS"]
        let asiaBase: Set<String> = ["CHN", "JPN", "IND"]

        let europeAdj = AchievementKind.adjustSet(europeBase, forZone: "europa", assignments: assignments)
        let asiaAdj = AchievementKind.adjustSet(asiaBase, forZone: "asia", assignments: assignments)

        // RUS se quita de Europa (porque user la asignó a Asia).
        #expect(!europeAdj.contains("RUS"))
        // Y se mete en Asia.
        #expect(asiaAdj.contains("RUS"))
    }

    @Test("adjustSet: RUS asignado a 'ambos' aparece en Europa Y Asia")
    func adjustSetRusiaAmbos() {
        let assignments: [String: String] = ["RUS": "ambos"]
        let europeBase: Set<String> = ["FRA", "DEU", "RUS"]
        let asiaBase: Set<String> = ["CHN", "JPN"]

        let europeAdj = AchievementKind.adjustSet(europeBase, forZone: "europa", assignments: assignments)
        let asiaAdj = AchievementKind.adjustSet(asiaBase, forZone: "asia", assignments: assignments)

        #expect(europeAdj.contains("RUS"))
        #expect(asiaAdj.contains("RUS"))
    }

    @Test("adjustSet: TUR sin assignment usa default 'medioOriente'")
    func adjustSetTurquiaDefault() {
        let assignments: [String: String] = [:]  // sin entry para TUR
        let euBase: Set<String> = ["FRA", "DEU", "TUR"]
        let meBase: Set<String> = ["SAU", "ARE", "TUR"]

        let euAdj = AchievementKind.adjustSet(euBase, forZone: "europa", assignments: assignments)
        let meAdj = AchievementKind.adjustSet(meBase, forZone: "medioOriente", assignments: assignments)

        // TUR por default va a medioOriente — se quita de Europa, queda en M.O.
        #expect(!euAdj.contains("TUR"))
        #expect(meAdj.contains("TUR"))
    }

    @Test("adjustSet: EGY asignado a 'africa' (default) queda en África, no en Asia")
    func adjustSetEgiptoDefault() {
        let assignments: [String: String] = [:]  // EGY default → "africa"
        let africaBase: Set<String> = ["DZA", "EGY", "ZAF"]
        let asiaBase: Set<String> = ["CHN", "EGY"]

        let africaAdj = AchievementKind.adjustSet(africaBase, forZone: "africa", assignments: assignments)
        let asiaAdj = AchievementKind.adjustSet(asiaBase, forZone: "asia", assignments: assignments)

        #expect(africaAdj.contains("EGY"))
        #expect(!asiaAdj.contains("EGY"))
    }

    @Test("adjustSet: countries NO pluricontinentales se mantienen intactos")
    func adjustSetNoPluriIgnorado() {
        let assignments: [String: String] = ["RUS": "asia"]
        let base: Set<String> = ["FRA", "DEU", "ESP"]  // ninguno es pluri
        let adj = AchievementKind.adjustSet(base, forZone: "europa", assignments: assignments)
        #expect(adj == base)
    }

    // MARK: - adjustedHemispheres (multi-hemisferio)

    @Test("adjustedHemispheres: BRA default 'sur', está en south")
    func hemispheresBrasilDefault() {
        let (south, ambos) = AchievementKind.adjustedHemispheres(assignments: [:])
        #expect(south.contains("BRA"))
        #expect(!ambos.contains("BRA"))
    }

    @Test("adjustedHemispheres: BRA asignado 'norte' lo saca de south")
    func hemispheresBrasilNorte() {
        let (south, ambos) = AchievementKind.adjustedHemispheres(assignments: ["BRA": "norte"])
        #expect(!south.contains("BRA"))
        #expect(!ambos.contains("BRA"))
    }

    @Test("adjustedHemispheres: BRA asignado 'ambos' va a ambos set")
    func hemispheresBrasilAmbos() {
        let (south, ambos) = AchievementKind.adjustedHemispheres(assignments: ["BRA": "ambos"])
        #expect(!south.contains("BRA"))  // sale de south puro
        #expect(ambos.contains("BRA"))
    }

    @Test("adjustedHemispheres: ECU default 'sur' a pesar de cruzar ecuador")
    func hemispheresEcuadorDefault() {
        let (south, ambos) = AchievementKind.adjustedHemispheres(assignments: [:])
        #expect(south.contains("ECU"))
        #expect(!ambos.contains("ECU"))
    }

    @Test("adjustedHemispheres: countries NO multi-hemi se mantienen")
    func hemispheresNoMultiHemiIgnorado() {
        let (south, _) = AchievementKind.adjustedHemispheres(assignments: [:])
        // Argentina siempre sur.
        #expect(south.contains("ARG"))
        // Noruega siempre norte (no aparece en south).
        #expect(!south.contains("NOR"))
    }

    // MARK: - macroContinent

    @Test("macroContinent: Norteamérica/Caribe/Sudamérica/Centroamérica → 'america'")
    func macroContinentAmericaUnificada() {
        #expect(AchievementKind.macroContinent(for: "USA") == "america")
        #expect(AchievementKind.macroContinent(for: "CUB") == "america")   // Caribe
        #expect(AchievementKind.macroContinent(for: "BRA") == "america")   // Sudamérica
        #expect(AchievementKind.macroContinent(for: "CRI") == "america")   // Centroamérica
    }

    @Test("macroContinent: ME se incluye en 'asia'")
    func macroContinentMOEsAsia() {
        #expect(AchievementKind.macroContinent(for: "SAU") == "asia")
        #expect(AchievementKind.macroContinent(for: "JPN") == "asia")
        #expect(AchievementKind.macroContinent(for: "ISR") == "asia")
    }

    @Test("macroContinent: Europa, África, Oceanía, Antártida")
    func macroContinentRestoContinentes() {
        #expect(AchievementKind.macroContinent(for: "FRA") == "europa")
        #expect(AchievementKind.macroContinent(for: "EGY") == "africa")
        #expect(AchievementKind.macroContinent(for: "AUS") == "oceania")
        #expect(AchievementKind.macroContinent(for: "ATA") == "antartida")
    }

    @Test("macroContinent: ISO desconocido devuelve nil")
    func macroContinentDesconocido() {
        #expect(AchievementKind.macroContinent(for: "XXX") == nil)
        #expect(AchievementKind.macroContinent(for: "") == nil)
    }

    // MARK: - zoneIsoCodes / regionIsoCodes integrity

    @Test("zoneIsoCodes: G7 son exactamente 7 países")
    func g7SizeOk() {
        #expect(AchievementKind.todosG7.zoneIsoCodes.count == 7)
        #expect(AchievementKind.todosG7.zoneIsoCodes.contains("USA"))
        #expect(AchievementKind.todosG7.zoneIsoCodes.contains("JPN"))
        #expect(!AchievementKind.todosG7.zoneIsoCodes.contains("RUS")) // expulsado de facto
    }

    @Test("zoneIsoCodes: BRICS contiene RUS, BRA, IND, CHN, ZAF (5)")
    func bricsCompleto() {
        let set = AchievementKind.todosBRICS.zoneIsoCodes
        #expect(set == ["BRA", "RUS", "IND", "CHN", "ZAF"])
    }

    @Test("zoneIsoCodes: Hispanohablantes son 21")
    func hispanohablantesSize() {
        #expect(AchievementKind.todosHispanohablantes.zoneIsoCodes.count == 21)
    }

    @Test("zoneIsoCodes: Mediterráneo incluye TUR/CYP/EGY (pluri) + España")
    func mediterraneoIncluyePluri() {
        let med = AchievementKind.todosMediterraneo.zoneIsoCodes
        #expect(med.contains("ESP"))
        #expect(med.contains("TUR"))
        #expect(med.contains("CYP"))
        #expect(med.contains("EGY"))
    }

    // MARK: - topGlobalHubs

    @Test("topGlobalHubs: incluye los 8 hubs icónicos")
    func topGlobalHubsCompletos() {
        let hubs = AchievementKind.topGlobalHubs
        for iata in ["DXB", "LHR", "JFK", "HND", "CDG", "SIN", "ATL", "AMS"] {
            #expect(hubs.contains(iata))
        }
        #expect(hubs.count == 8)
    }

    // MARK: - medal + medalOrder consistency

    @Test("Todos los kinds tienen título, medalla y medalOrder coherente")
    func allKindsHaveTitleMedalOrder() {
        for kind in AchievementKind.allCases {
            #expect(!kind.title.isEmpty, "Kind \(kind) sin título")
            #expect(!kind.medal.isEmpty, "Kind \(kind) sin medalla")
            #expect((0...3).contains(kind.medalOrder), "Kind \(kind) medalOrder fuera de rango")
            // medal y medalOrder deben coincidir en jerarquía.
            switch kind.medalOrder {
            case 0: #expect(kind.medal == "🏆", "Kind \(kind) orden 0 no 🏆")
            case 1: #expect(kind.medal == "🥇", "Kind \(kind) orden 1 no 🥇")
            case 2: #expect(kind.medal == "🥈", "Kind \(kind) orden 2 no 🥈")
            case 3: #expect(kind.medal == "🥉", "Kind \(kind) orden 3 no 🥉")
            default: break
            }
        }
    }
}
