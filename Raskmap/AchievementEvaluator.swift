//
//  AchievementEvaluator.swift
//  Raskmap
//
//  Struct pura (sin @State / @AppStorage / @Query) que evalúa qué logros
//  están desbloqueados dado un snapshot del estado de la app. Extraído de
//  ContentView.multiContAchievedNow para permitir tests unitarios — antes
//  la lógica estaba acoplada al ciclo de vida de la View y era imposible
//  de testear sin levantar un MainActor + SwiftData stack.
//
//  Uso:
//  ```
//  let result = AchievementEvaluator(
//      trips: trips,
//      countries: countries,
//      countingMode: .all,
//      multiContinentAssignments: [:],
//      multiHemisphereAssignments: [:],
//      mapQuadrants: [:],
//      earnedPassportZones: [],
//      modernWondersRaw: "[]"
//  ).evaluate()
//  ```
//

import Foundation

struct AchievementEvaluator {
    let trips: [Trip]
    let countries: [Country]
    let countingMode: CountingMode
    let multiContinentAssignments: [String: String]
    let multiHemisphereAssignments: [String: String]
    let mapQuadrants: [String: [MapQuadrant]]
    let earnedPassportZones: Set<String>
    let modernWondersRaw: String
    /// Inyectable para tests — por defecto `Date()` real. Permite testear
    /// "trip futuro vs pasado" sin depender del clock del runner.
    let now: Date

    init(
        trips: [Trip],
        countries: [Country],
        countingMode: CountingMode,
        multiContinentAssignments: [String: String] = [:],
        multiHemisphereAssignments: [String: String] = [:],
        mapQuadrants: [String: [MapQuadrant]] = [:],
        earnedPassportZones: Set<String> = [],
        modernWondersRaw: String = "[]",
        now: Date = Date()
    ) {
        self.trips = trips
        self.countries = countries
        self.countingMode = countingMode
        self.multiContinentAssignments = multiContinentAssignments
        self.multiHemisphereAssignments = multiHemisphereAssignments
        self.mapQuadrants = mapQuadrants
        self.earnedPassportZones = earnedPassportZones
        self.modernWondersRaw = modernWondersRaw
        self.now = now
    }

    /// Devuelve el set de `AchievementKind` desbloqueados según los datos.
    @MainActor
    func evaluate() -> Set<AchievementKind> {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let past = trips.filter { cal.startOfDay(for: $0.dateFrom) <= today }
        let visited = Set(countries.filter { $0.status == .visited || $0.status == .lived }.map { $0.isoCode })
        let mode = countingMode
        let assignments = multiContinentAssignments
        let allQuadrants = mapQuadrants
        let earnedZones = earnedPassportZones

        var result = Set<AchievementKind>()
        for kind in AchievementKind.allCases {
            if let zoneKey = kind.passportZoneKey {
                if earnedZones.contains(zoneKey) {
                    result.insert(kind)
                } else {
                    let quadrants = (allQuadrants[zoneKey] ?? []).filter { $0.position >= 0 }
                    let zoneNameLower = AchievementKind.zoneName(forPassportKey: zoneKey)
                    if !quadrants.isEmpty && quadrants.allSatisfy({ q in
                        let filtered = zoneNameLower.map { AchievementKind.filterCandidatesForZone(q.candidateIsoCodes, zoneName: $0, assignments: assignments, quadrantTitle: q.title) } ?? q.candidateIsoCodes
                        return filtered.allSatisfy { visited.contains($0) }
                    }) {
                        result.insert(kind)
                    }
                }
                continue
            }
            let achieved: Bool
            switch kind {
            case .firstTrip:
                achieved = !past.isEmpty
            case .firstLayover:
                achieved = past.contains { $0.hasLayover }
            case .trips100:
                achieved = past.count >= 100
            case .primerMicroestado:
                let micro = AchievementKind.todosMicroestados.zoneIsoCodes
                achieved = past.contains { micro.contains($0.isoCode) }
            case .allWorld:
                let valid = visited.filter { mode.counts($0) }
                achieved = valid.count >= mode.denominator && mode.denominator > 0
            case .visitedNortamerica, .visitedCaribe, .visitedSudamerica, .visitedCentroamerica,
                 .visitedAfrica, .visitedEuropa, .visitedMedioOriente, .visitedOceania,
                 .visitedAsia, .visitedAntarctica:
                let base = kind.regionIsoCodes
                let adj = kind.geographicRegionName.map { AchievementKind.adjustSet(base, forZone: $0, assignments: assignments) } ?? base
                achieved = !adj.isDisjoint(with: visited)
            case .fiveEurope, .fiveAsia, .fiveAfrica, .fiveMedioOriente, .fiveOceania,
                 .fiveNortamerica, .fiveCaribe, .fiveSudamerica, .fiveCentroamerica:
                let base = kind.regionIsoCodes
                let adj = kind.geographicRegionName.map { AchievementKind.adjustSet(base, forZone: $0, assignments: assignments) } ?? base
                achieved = past.filter { adj.contains($0.isoCode) }.count >= 5
            case .europaCompleta, .asiaCompleta, .medioOrienteCompleto,
                 .africaCompleta, .americaCompleta, .oceaniaCompleta,
                 .todaLaUE, .todosEslavos, .todosEscandinavos, .todosBalcanicos, .todosMicroestados:
                let base = kind.zoneIsoCodes
                let adj = kind.geographicZoneName.map { AchievementKind.adjustSet(base, forZone: $0, assignments: assignments) } ?? base
                let valid = adj.filter { mode.counts($0) }
                achieved = !valid.isEmpty && valid.allSatisfy { visited.contains($0) }
            case .ambosHemisferios:
                let (hSouth, hAmbos) = AchievementKind.adjustedHemispheres(assignments: multiHemisphereAssignments)
                let hasSouth = visited.contains { (hSouth.contains($0) || hAmbos.contains($0)) && mode.counts($0) }
                let hasNorth = visited.contains { (!hSouth.contains($0) || hAmbos.contains($0)) && mode.counts($0) }
                achieved = hasSouth && hasNorth
            case .todosLosContinentes:
                let americaSet = AchievementKind.visitedNortamerica.regionIsoCodes
                    .union(AchievementKind.visitedCaribe.regionIsoCodes)
                    .union(AchievementKind.visitedSudamerica.regionIsoCodes)
                    .union(AchievementKind.visitedCentroamerica.regionIsoCodes)
                let continentSets: [Set<String>] = [
                    AchievementKind.visitedEuropa.regionIsoCodes,
                    AchievementKind.visitedAsia.regionIsoCodes,
                    AchievementKind.visitedAfrica.regionIsoCodes,
                    americaSet,
                    AchievementKind.visitedOceania.regionIsoCodes,
                ]
                achieved = continentSets.allSatisfy { set in
                    !set.filter { mode.counts($0) }.isDisjoint(with: visited)
                }
            case .pasaporteEuropa, .pasaporteAsia, .pasaporteMedioOriente,
                 .pasaporteAfrica, .pasaporteAmerica, .pasaporteOceania:
                achieved = false // ya tratado arriba via passportZoneKey
            case .trips5:  achieved = past.filter { !$0.isSegmentChild }.count >= 5
            case .trips10: achieved = past.filter { !$0.isSegmentChild }.count >= 10
            case .trips25: achieved = past.filter { !$0.isSegmentChild }.count >= 25
            case .trips50: achieved = past.filter { !$0.isSegmentChild }.count >= 50
            case .paises10:   achieved = visited.filter { mode.counts($0) }.count >= 10
            case .paises25:   achieved = visited.filter { mode.counts($0) }.count >= 25
            case .paises50:   achieved = visited.filter { mode.counts($0) }.count >= 50
            case .paises75:   achieved = visited.filter { mode.counts($0) }.count >= 75
            case .centurion:  achieved = visited.filter { mode.counts($0) }.count >= 100
            case .todosBalticos, .todosCaucaso, .todosAnglosfera,
                 .todosNordicos, .todosG7, .todosBRICS, .todosASEAN,
                 .todosLusofonos, .todosMediterraneo, .todosHispanohablantes:
                let base = kind.zoneIsoCodes
                let valid = base.filter { mode.counts($0) }
                achieved = !valid.isEmpty && valid.allSatisfy { visited.contains($0) }
            case .primerVuelo:
                achieved = past.contains { trip in
                    if trip.transport == "✈️" { return true }
                    return trip.tripSegments.contains { $0.transport == "✈️" }
                }
            case .vuelos10, .vuelos50, .frequentFlyer:
                let target: Int
                switch kind {
                case .vuelos10:      target = 10
                case .vuelos50:      target = 50
                case .frequentFlyer: target = 100
                default:             target = 0
                }
                var legs = 0
                for trip in past where !trip.isSegmentChild {
                    let segs = trip.tripSegments
                    if segs.isEmpty {
                        if trip.transport == "✈️" {
                            let touches = trip.tripAirports.reduce(0) { $0 + $1.count }
                            legs += max(1, touches / 2)
                        }
                    } else {
                        for seg in segs where seg.transport == "✈️" {
                            let outLegs = max(0, (seg.airports?.count ?? 0) - 1)
                            let retLegs = max(0, (seg.returnAirports?.count ?? 0) - 1)
                            legs += max(1, outLegs + retLegs)
                        }
                    }
                }
                achieved = legs >= target
            case .trotamundosTerrestre:
                let groundTrips = past.filter { trip in
                    guard !trip.isSegmentChild else { return false }
                    let segs = trip.tripSegments
                    if segs.isEmpty {
                        let tr = trip.transport ?? ""
                        return !tr.isEmpty && tr != "✈️"
                    } else {
                        let nonFlight = segs.filter { !$0.transport.isEmpty && $0.transport != "✈️" }
                        let hasFlight = segs.contains { $0.transport == "✈️" }
                        return !nonFlight.isEmpty && !hasFlight
                    }
                }
                achieved = groundTrips.count >= 10
            case .daytrip:
                achieved = past.contains { trip in
                    guard !trip.isSegmentChild else { return false }
                    guard let to = trip.dateTo else { return true }
                    return cal.startOfDay(for: trip.dateFrom) == cal.startOfDay(for: to)
                }
            case .sabbatical, .nomada:
                let threshold = (kind == .sabbatical) ? 30 : 90
                achieved = past.contains { trip in
                    guard !trip.isSegmentChild, let to = trip.dateTo else { return false }
                    let days = cal.dateComponents([.day],
                        from: cal.startOfDay(for: trip.dateFrom),
                        to: cal.startOfDay(for: to)).day ?? 0
                    return days > threshold
                }
            case .cincoPaisesAno, .diezPaisesAno, .veintePaisesAno:
                let target: Int
                switch kind {
                case .cincoPaisesAno:   target = 5
                case .diezPaisesAno:    target = 10
                case .veintePaisesAno:  target = 20
                default:                target = 0
                }
                let byYear = Dictionary(grouping: past.filter { !$0.isSegmentChild }) { trip in
                    cal.component(.year, from: trip.dateFrom)
                }
                let maxPerYear = byYear.values.map { yearTrips -> Int in
                    Set(yearTrips.map(\.isoCode)).filter { mode.counts($0) }.count
                }.max() ?? 0
                achieved = maxPerYear >= target
            case .anoCompletoViajero:
                let monthsSeen = Set(past
                    .filter { !$0.isSegmentChild }
                    .map { cal.component(.month, from: $0.dateFrom) })
                achieved = monthsSeen.count == 12
            case .viajeroNavideno:
                achieved = past.contains { trip in
                    guard !trip.isSegmentChild else { return false }
                    var date = cal.startOfDay(for: trip.dateFrom)
                    let endDate = cal.startOfDay(for: trip.dateTo ?? trip.dateFrom)
                    while date <= endDate {
                        let m = cal.component(.month, from: date)
                        let d = cal.component(.day, from: date)
                        if (m == 12 && d >= 20) || (m == 1 && d <= 6) { return true }
                        guard let next = cal.date(byAdding: .day, value: 1, to: date) else { break }
                        date = next
                    }
                    return false
                }
            case .sieteMaravillas:
                let set = (try? JSONDecoder().decode(Set<String>.self, from: Data(modernWondersRaw.utf8))) ?? []
                achieved = set.count >= 7
            case .medioMundo:
                let valid = visited.filter { mode.counts($0) }.count
                achieved = valid * 2 >= mode.denominator && mode.denominator > 0
            case .capitanBarco, .mochileroAutentico:
                let target = (kind == .capitanBarco) ? "🚢" : "🚶🏻"
                let alt    = (kind == .mochileroAutentico) ? "🚶" : ""
                func matches(_ tr: String) -> Bool {
                    return tr == target || (!alt.isEmpty && tr == alt)
                }
                var count = 0
                for trip in past where !trip.isSegmentChild {
                    let segs = trip.tripSegments
                    if segs.isEmpty {
                        if matches(trip.transport ?? "") { count += 1 }
                    } else {
                        count += segs.filter { matches($0.transport) }.count
                    }
                }
                achieved = count >= 5
            case .multimodal:
                achieved = past.contains { trip in
                    guard !trip.isSegmentChild else { return false }
                    let segs = trip.tripSegments.filter { !$0.transport.isEmpty }
                    let normalized = Set(segs.map { $0.transport == "🚶" ? "🚶🏻" : $0.transport })
                    return normalized.count >= 3
                }
            case .cincoAerolineas, .veinticincoAerolineas:
                let target = (kind == .cincoAerolineas) ? 5 : 25
                var airlines = Set<String>()
                for trip in past where !trip.isSegmentChild {
                    for al in trip.tripAirlines { airlines.insert(al.name) }
                    for seg in trip.tripSegments {
                        for al in seg.airlines ?? [] { airlines.insert(al.name) }
                    }
                }
                achieved = airlines.count >= target
            case .diezAeropuertos, .cincuentaAeropuertos:
                let target = (kind == .diezAeropuertos) ? 10 : 50
                var iatas = Set<String>()
                for trip in past where !trip.isSegmentChild {
                    for ap in trip.tripAirports { iatas.insert(ap.iata) }
                    for seg in trip.tripSegments {
                        for ap in seg.airports ?? []       { iatas.insert(ap.iata) }
                        for ap in seg.returnAirports ?? [] { iatas.insert(ap.iata) }
                    }
                }
                achieved = iatas.count >= target
            case .hubMaster:
                let hubs = AchievementKind.topGlobalHubs
                var seen = Set<String>()
                for trip in past where !trip.isSegmentChild {
                    for ap in trip.tripAirports where hubs.contains(ap.iata) { seen.insert(ap.iata) }
                    for seg in trip.tripSegments {
                        for ap in seg.airports ?? []       where hubs.contains(ap.iata) { seen.insert(ap.iata) }
                        for ap in seg.returnAirports ?? [] where hubs.contains(ap.iata) { seen.insert(ap.iata) }
                    }
                }
                achieved = seen.count >= 3
            case .maratonViajero:
                let sorted = past
                    .filter { !$0.isSegmentChild }
                    .sorted { $0.dateFrom < $1.dateFrom }
                var hit = false
                for start in sorted {
                    let windowEnd = cal.date(byAdding: .day, value: 30, to: start.dateFrom) ?? start.dateFrom
                    let windowTrips = sorted.filter { $0.dateFrom >= start.dateFrom && $0.dateFrom <= windowEnd }
                    let isos = Set(windowTrips.map(\.isoCode)).filter { mode.counts($0) }
                    if isos.count >= 3 { hit = true; break }
                }
                achieved = hit
            case .dosContinentesUnViaje:
                achieved = past.contains { trip in
                    guard !trip.isSegmentChild else { return false }
                    var isos = Set<String>([trip.isoCode])
                    for seg in trip.tripSegments { isos.formUnion(seg.isoCodes) }
                    let cs = Set(isos.compactMap { AchievementKind.macroContinent(for: $0) })
                    return cs.count >= 2
                }
            case .cincoPaisesUnViaje:
                achieved = past.contains { trip in
                    guard !trip.isSegmentChild else { return false }
                    var isos = Set<String>([trip.isoCode])
                    for seg in trip.tripSegments { isos.formUnion(seg.isoCodes) }
                    return isos.count >= 5
                }
            case .segundaCasa, .querencia:
                let threshold = (kind == .segundaCasa) ? 5 : 10
                var byIso: [String: Int] = [:]
                for trip in past { byIso[trip.isoCode, default: 0] += 1 }
                let maxCount = byIso.values.max() ?? 0
                achieved = maxCount >= threshold
            }
            if achieved { result.insert(kind) }
        }
        return result
    }
}
