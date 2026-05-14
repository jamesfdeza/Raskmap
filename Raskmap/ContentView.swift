//
//  ContentView.swift
//  Raskmap
//

import SwiftUI
import SwiftData
import Combine
import MapKit
import Photos
import WidgetKit
import CoreLocation
import MessageUI
import StoreKit
import ActivityKit
import UserNotifications

class MapStore: ObservableObject {
    var centerOnCountry: ((String) -> Void)?
}

struct ContentView: View {
    var onContentReady: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Query private var countries: [Country]
    @Query private var trips: [Trip]

    @State private var selectedCountry: Country? = nil
    @State private var statusListFilter: CountryStatus? = nil
    @State private var showSheet: Bool = false
    @State private var features: [CountryFeature] = []
    @State private var showSearch: Bool = false
    @State private var showAllCountries: Bool = false
    @State private var pendingDateCountry: Country? = nil
    @State private var pendingDateIsNew: Bool = false
    @State private var locationIsoCode: String? = nil
    @State private var visitedToastMessages: [String] = []
    /// ISO del país que acaba de marcarse como visitado por primera vez.
    /// Cuando es non-nil, el mapa muestra un ripple celebratorio centrado
    /// durante ~0.9s y luego se limpia. Combina con UINotificationFeedback.
    @State private var rippleCountryIso: String? = nil
    @State private var pendingAddTripCountry: Country? = nil
    @State private var statusBeforeVisit: CountryStatus = .none
    @State private var refreshTrigger: Bool = false
    @State private var shouldOpenAddTrip: Bool = false
    @State private var lastModifiedCountry: Country? = nil
    @State private var editingFutureTrip: Trip? = nil
    @State private var lastEditedFutureTripIso: String? = nil
    @State private var bannerTappedCountry: Country? = nil
    @StateObject private var locationManager = LocationManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @State private var pendingDateStatus: CountryStatus = .none
    @State private var deferredDateCountry: Country? = nil
    @State private var showHelpToast: Bool = false
    @State private var searchText: String = ""
    @StateObject private var mapStore = MapStore()
    @EnvironmentObject private var colorTheme: ColorThemeManager
    @AppStorage("username") private var username: String = ""
    @AppStorage("didShowLocationToast") private var didShowLocationToast: Bool = false
    @State private var showLocationToast: Bool = false
    @State private var showOnboarding: Bool = false
    @AppStorage("didShowOnboarding") private var didShowOnboarding: Bool = false

    /// Tarea cancelable para coordinar transiciones entre sheets (cierra
    /// CountryBottomSheet → abre next sheet) sin condiciones de carrera por
    /// tap-spam. Antes usábamos DispatchQueue.asyncAfter sin cancelación, así
    /// que un tap rápido en otro país antes de los 350ms ejecutaba ambas
    /// transiciones y dejaba sheets en cola.
    @State private var sheetTransitionTask: Task<Void, Never>? = nil

    /// Cierra el CountryBottomSheet y, tras 350ms (margen para que SwiftUI
    /// complete la animación de dismiss), ejecuta el bloque de apertura.
    /// Cancela cualquier transición previa pendiente.
    private func scheduleSheetTransition(_ block: @escaping () -> Void) {
        sheetTransitionTask?.cancel()
        selectedCountry = nil
        sheetTransitionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            block()
        }
    }
    @State private var usernameInput: String = ""
    @State private var onboardingStep: Int = 0
    @State private var isLoadingFeatures: Bool = true
    @State private var pendingShowSheet: Bool = false
    @State private var showProfile: Bool = false
    @AppStorage("countingMode") private var countingModeRaw: String = CountingMode.all.rawValue
    @AppStorage("menuPosition")    private var menuPositionRaw: String = "bottom"
    @AppStorage("showBucketList") private var showBucketList: Bool = true
    @AppStorage("showCountdown")  private var showCountdown: Bool = true
    @AppStorage("topTable")  private var topTable:  String = "{}"
    @AppStorage("multiContinentRaw") private var multiContinentRaw: String = "{}"
    @AppStorage("multiHemisphereRaw") private var multiHemisphereRaw: String = "{}"
    @AppStorage("appFontFamily") private var _appFontFamily: String = "satoshi"
    @AppStorage("isRaskmapPro") private var isRaskmapPro: Bool = false
    @AppStorage("mapQuadrantsData") private var mapQuadrantsData: String = "{}"
    @AppStorage("earnedPassportAchievementsRaw") private var earnedPassportRaw: String = "[]"
    /// AppStorage de las maravillas modernas marcadas (Set<String> JSON).
    /// Declarado aquí (además de en `ModernWondersSheet`) para que SwiftUI
    /// rastree los cambios y re-evalúe `multiContAchievedNow` — sin esto,
    /// el logro `sieteMaravillas` no dispararía celebración al marcar la 7ª.
    @AppStorage("modernWondersVisited") private var modernWondersRaw: String = "[]"
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled: Bool = false
    @AppStorage("neverShowReview") private var neverShowReview: Bool = false
    @AppStorage("tripRemindersEnabled") private var tripRemindersEnabled: Bool = false
    @State private var showSubscription: Bool = false
    @State private var showReviewAlert: Bool = false
    @State private var prevAchieved: Set<AchievementKind>? = nil
    @State private var highlightedIsoCode: String? = nil
    @State private var flightMode: Bool = false
    @State private var flightTransitionTarget: Bool? = nil
    @State private var flightRouteFilter: FlightRouteFilter = .past
    @State private var flightModeHasRoutes: Bool = true
    @State private var cachedNextBanner: (days: Int, flag: String, name: String, isoCode: String, transport: String?, dateFrom: Date?, bookingRef: String, title: String?)? = nil
    @AppStorage("selectedPassport") private var selectedPassport: String = "PASSPORT"

    private var menuPositionIsTop: Bool { false }

    private var countingMode: CountingMode { CountingMode(rawValue: countingModeRaw) ?? .all }

    private var earnedPassportZones: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: Data(earnedPassportRaw.utf8))) ?? []
    }

    private func markPassportAchievementsEarned(_ kinds: Set<AchievementKind>) {
        guard !kinds.isEmpty else { return }
        var zones = earnedPassportZones
        kinds.compactMap { $0.passportZoneKey }.forEach { zones.insert($0) }
        if let data = try? JSONEncoder().encode(Array(zones)),
           let str = String(data: data, encoding: .utf8) {
            earnedPassportRaw = str
        }
    }

    private var multiContAchievedNow: Set<AchievementKind> {
        let assignments = (try? JSONDecoder().decode([String: String].self, from: Data(multiContinentRaw.utf8))) ?? [:]
        let today = Calendar.current.startOfDay(for: Date())
        let past = trips.filter { Calendar.current.startOfDay(for: $0.dateFrom) <= today }
        let visited = Set(countries.filter { $0.status == .visited || $0.status == .lived }.map { $0.isoCode })
        let allQuadrants = (try? JSONDecoder().decode([String: [MapQuadrant]].self, from: Data(mapQuadrantsData.utf8))) ?? [:]
        let earnedZones = earnedPassportZones
        let mode = countingMode
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
                let hAssign = (try? JSONDecoder().decode([String: String].self, from: Data(multiHemisphereRaw.utf8))) ?? [:]
                let (hSouth, hAmbos) = AchievementKind.adjustedHemispheres(assignments: hAssign)
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

            // ─── FASE 2: hitos numéricos VIAJES ───────────────────────────
            // Trips son trips: NO filtran por countingMode (una visita a HKG
            // sigue siendo un viaje válido aunque HKG no cuente como país en
            // modo ONU). Sólo contamos trips primarios PASADOS para que un
            // viaje futuro programado no infle el contador.
            case .trips5:  achieved = past.filter { !$0.isSegmentChild }.count >= 5
            case .trips10: achieved = past.filter { !$0.isSegmentChild }.count >= 10
            case .trips25: achieved = past.filter { !$0.isSegmentChild }.count >= 25
            case .trips50: achieved = past.filter { !$0.isSegmentChild }.count >= 50

            // ─── FASE 2: hitos numéricos PAÍSES ───────────────────────────
            // Filtran por countingMode: en ONU sólo cuenta los 193, en
            // ONU+obs los 195, en Todos los 249. Esto hace los logros
            // DINÁMICOS — cambiar de modo en ajustes recalcula al vuelo.
            case .paises10:   achieved = visited.filter { mode.counts($0) }.count >= 10
            case .paises25:   achieved = visited.filter { mode.counts($0) }.count >= 25
            case .paises50:   achieved = visited.filter { mode.counts($0) }.count >= 50
            case .paises75:   achieved = visited.filter { mode.counts($0) }.count >= 75
            case .centurion:  achieved = visited.filter { mode.counts($0) }.count >= 100

            // ─── FASE 2: grupos culturales/políticos/geográficos ──────────
            // Patrón homogéneo: el set del grupo es FIJO (no se ajusta por
            // asignación pluricontinental — un país como RUS está en BRICS
            // independientemente de si lo asignaste a Europa o Asia en
            // ajustes). Sí filtramos por countingMode por consistencia con
            // los logros existentes — si el modo activo excluye un ISO del
            // grupo, no se requiere para el logro.
            case .todosBalticos, .todosCaucaso, .todosAnglosfera,
                 .todosNordicos, .todosG7, .todosBRICS, .todosASEAN,
                 .todosLusofonos, .todosMediterraneo, .todosHispanohablantes:
                let base = kind.zoneIsoCodes
                let valid = base.filter { mode.counts($0) }
                achieved = !valid.isEmpty && valid.allSatisfy { visited.contains($0) }

            // ─── FASE 2: transporte (vuelos ✈️) ───────────────────────────
            // Conta tramos de avión legacy (tripAirports/2) y segment-based
            // (sum de (airports-1) + (returnAirports-1) por seg ✈️).
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

            // ─── FASE 2: transporte (no-✈️) ───────────────────────────────
            case .trotamundosTerrestre:
                // ≥10 trips primarios PASADOS sin ningún tramo de avión y
                // con algún transporte registrado (los trips "sin transporte"
                // — flag manual de un país — no cuentan).
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

            // ─── FASE 2: viajes por DURACIÓN ──────────────────────────────
            case .daytrip:
                // ≥1 trip primario cuyo rango es de 1 solo día. Cubre los
                // dos casos: sin dateTo (1 día implícito) Y dateTo == dateFrom
                // (ida y vuelta el mismo día tras el último cambio).
                achieved = past.contains { trip in
                    guard !trip.isSegmentChild else { return false }
                    guard let to = trip.dateTo else { return true }
                    let cal = Calendar.current
                    return cal.startOfDay(for: trip.dateFrom) == cal.startOfDay(for: to)
                }
            case .sabbatical, .nomada:
                let threshold = (kind == .sabbatical) ? 30 : 90
                achieved = past.contains { trip in
                    guard !trip.isSegmentChild, let to = trip.dateTo else { return false }
                    let days = Calendar.current.dateComponents([.day],
                        from: Calendar.current.startOfDay(for: trip.dateFrom),
                        to: Calendar.current.startOfDay(for: to)).day ?? 0
                    return days > threshold
                }

            // ─── FASE 2: países por AÑO ───────────────────────────────────
            // Cuenta ISOs distintos visitados (por dateFrom del trip) por año
            // calendario. Devuelve el máximo entre todos los años. Respeta
            // countingMode — un viaje a HKG en modo ONU no suma. Sólo trips
            // primarios PASADOS.
            case .cincoPaisesAno, .diezPaisesAno, .veintePaisesAno:
                let target: Int
                switch kind {
                case .cincoPaisesAno:   target = 5
                case .diezPaisesAno:    target = 10
                case .veintePaisesAno:  target = 20
                default:                target = 0
                }
                let cal = Calendar.current
                let byYear = Dictionary(grouping: past.filter { !$0.isSegmentChild }) { trip in
                    cal.component(.year, from: trip.dateFrom)
                }
                let maxPerYear = byYear.values.map { yearTrips -> Int in
                    Set(yearTrips.map(\.isoCode)).filter { mode.counts($0) }.count
                }.max() ?? 0
                achieved = maxPerYear >= target

            // ─── FASE 2: temporal — año completo ──────────────────────────
            // ≥1 viaje en cada uno de los 12 meses del calendario (acumulativo
            // entre años — no exige que sea el mismo año). Sólo trips
            // primarios pasados.
            case .anoCompletoViajero:
                let cal = Calendar.current
                let monthsSeen = Set(past
                    .filter { !$0.isSegmentChild }
                    .map { cal.component(.month, from: $0.dateFrom) })
                achieved = monthsSeen.count == 12

            // ─── FASE 2: temporal — navideño ──────────────────────────────
            // ≥1 trip que cubra algún día en el rango [20-dic, 6-ene].
            case .viajeroNavideno:
                achieved = past.contains { trip in
                    guard !trip.isSegmentChild else { return false }
                    let cal = Calendar.current
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

            // ─── FASE 2: 7 Maravillas modernas ────────────────────────────
            // Disparo desacoplado de países visitados — el usuario marca cada
            // maravilla manualmente en `ModernWondersSheet`. El logro salta
            // cuando las 7 están marcadas. Persistencia en AppStorage
            // `modernWondersVisited` (JSON Set<String>).
            case .sieteMaravillas:
                // Lee del @AppStorage local (`modernWondersRaw`) para que
                // SwiftUI rastree el cambio y dispare la re-evaluación —
                // UserDefaults.standard.string(...) suelto no es reactivo.
                let set = (try? JSONDecoder().decode(Set<String>.self, from: Data(modernWondersRaw.utf8))) ?? []
                achieved = set.count >= 7

            // ─── FASE 3: medio mundo ──────────────────────────────────────
            // 50% del denominador del modo activo (97 ONU / 98 ONU+obs / 125 todos).
            case .medioMundo:
                let valid = visited.filter { mode.counts($0) }.count
                achieved = valid * 2 >= mode.denominator && mode.denominator > 0

            // ─── FASE 3: transporte específico (no-✈️) ────────────────────
            // Cuenta TRAMOS del emoji indicado en trips primarios pasados.
            // Para 🚶 normalizamos a 🚶🏻 (skin-tone) que es el emoji que
            // ofrece la app por defecto en el picker — agrupamos ambas
            // codificaciones para no perder tramos guardados con la versión
            // sin modificador.
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
                // ≥1 trip primario con ≥3 transportes DISTINTOS entre sus
                // segments. Normalizamos 🚶 a 🚶🏻 para evitar contarlos como
                // medios distintos cuando son el mismo "andar".
                achieved = past.contains { trip in
                    guard !trip.isSegmentChild else { return false }
                    let segs = trip.tripSegments.filter { !$0.transport.isEmpty }
                    let normalized = Set(segs.map { $0.transport == "🚶" ? "🚶🏻" : $0.transport })
                    return normalized.count >= 3
                }

            // ─── FASE 3: aerolíneas / aeropuertos distintos ───────────────
            // No filtra por countingMode — un aeropuerto es un aeropuerto
            // independientemente del modo. Recorre tanto el array legacy
            // del trip como los de los segments.
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
                // ≥3 de los 8 mayores hubs internacionales. Lista en
                // AchievementKind.topGlobalHubs.
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

            // ─── FASE 3: maratón viajero (3 países en 30 días) ────────────
            // Algoritmo de ventana deslizante: ordena trips por dateFrom,
            // y para cada inicio comprueba cuántos ISOs distintos hay en
            // el rango [start, start+30 días]. Respeta countingMode —
            // un trip a HKG en modo ONU no cuenta como país.
            case .maratonViajero:
                let cal = Calendar.current
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

            // ─── FASE 3: patrones por 1 viaje ─────────────────────────────
            case .dosContinentesUnViaje:
                // 1 trip primario cuyos ISOs (destino + segments) cruzan
                // ≥2 macro-continentes (Europa, Asia, África, América,
                // Oceanía, Antártida). M.Oriente queda dentro de "asia".
                achieved = past.contains { trip in
                    guard !trip.isSegmentChild else { return false }
                    var isos = Set<String>([trip.isoCode])
                    for seg in trip.tripSegments { isos.formUnion(seg.isoCodes) }
                    let cs = Set(isos.compactMap { AchievementKind.macroContinent(for: $0) })
                    return cs.count >= 2
                }
            case .cincoPaisesUnViaje:
                // 1 trip primario con ≥5 ISOs distintos. No filtra por
                // countingMode — pisar un país menor en un trip largo
                // sigue siendo "5 países en 1 viaje".
                achieved = past.contains { trip in
                    guard !trip.isSegmentChild else { return false }
                    var isos = Set<String>([trip.isoCode])
                    for seg in trip.tripSegments { isos.formUnion(seg.isoCodes) }
                    return isos.count >= 5
                }

            // ─── FASE 3: fidelidad a un país (visitas repetidas) ──────────
            // Cuenta el número de trips (primarios + isSegmentChild) que
            // tienen el mismo `isoCode` como destino, y verifica si ALGÚN
            // ISO supera el threshold. Incluye trips child porque cada
            // estancia en un país es una "visita" — un trip multi-tramo a
            // Francia x3 vía train suma 3 a Francia.
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

    // Conteos totales reales (para listas)
    private var visitedCountAll: Int { countries.filter { $0.status == .visited }.count }
    private var wantCountAll: Int    { countries.filter { $0.status == .wantToVisit }.count }
    private var bucketListCountAll: Int { countries.filter { $0.status == .bucketList }.count }

    // Conteos filtrados según modo activo (para badges y contador)
    private var visitedCount: Int {
        countingMode == .all ? visitedCountAll :
        countries.filter { $0.status == .visited && countingMode.counts($0.isoCode) }.count
    }
    private var wantCount: Int {
        countingMode == .all ? wantCountAll :
        countries.filter { $0.status == .wantToVisit && countingMode.counts($0.isoCode) }.count
    }

    // Countries with a future trip registered (visited status + future Trip)
    private var visitedWithFutureTrip: [Country] {
        let today = Calendar.current.startOfDay(for: Date())
        let futureIsoCodes = Set(trips.compactMap { trip -> String? in
            guard Calendar.current.startOfDay(for: trip.dateFrom) >= today else { return nil }
            return trip.isoCode
        })
        return countries.filter { $0.status == .visited && futureIsoCodes.contains($0.isoCode) }
    }

    // All "próximos": one ProximoRow per future trip (supports multiple per country)
    private var allProximoRows: [ProximoRow] {
        let today = Calendar.current.startOfDay(for: Date())
        // Pre-indexar trips por isoCode para evitar O(n·m) al cruzar con countries.
        let tripsByIso: [String: [Trip]] = Dictionary(grouping: trips, by: { $0.isoCode })
        var rows: [ProximoRow] = []
        for country in countries where country.status == .wantToVisit {
            let futureTrips = (tripsByIso[country.isoCode] ?? [])
                .filter { Calendar.current.startOfDay(for: $0.dateFrom) > today }
                .sorted { $0.dateFrom < $1.dateFrom }
            if futureTrips.isEmpty {
                rows.append(ProximoRow(id: "c_\(country.isoCode)", country: country, trip: nil))
            } else {
                for trip in futureTrips {
                    let tid = "\(trip.isoCode)_\(trip.createdAt.timeIntervalSince1970)"
                    rows.append(ProximoRow(id: tid, country: country, trip: trip))
                }
            }
        }
        for country in visitedWithFutureTrip {
            let nearestTrip = (tripsByIso[country.isoCode] ?? [])
                .filter { Calendar.current.startOfDay(for: $0.dateFrom) >= today }
                .min(by: { $0.dateFrom < $1.dateFrom })
            rows.append(ProximoRow(id: "v_\(country.isoCode)", country: country, trip: nearestTrip))
        }
        return rows
    }

    // Extended próximos count for badge
    private var proxCount: Int {
        let base = countries.filter { $0.status == .wantToVisit && countingMode.counts($0.isoCode) }.count
        let extra = visitedWithFutureTrip.filter { countingMode.counts($0.isoCode) }.count
        return base + extra
    }
    private var bucketListCount: Int {
        countingMode == .all ? bucketListCountAll :
        countries.filter { $0.status == .bucketList && countingMode.counts($0.isoCode) }.count
    }

    private var sortedFeatures: [CountryFeature] {
        features.sorted { $0.localizedName.localizedCompare($1.localizedName) == .orderedAscending }
    }

    private var countryStatusMap: [String: CountryStatus] {
        Dictionary(uniqueKeysWithValues: countries.map { ($0.isoCode, $0.status) })
    }

    private var searchResults: [CountryFeature] {
        guard !searchText.isEmpty else { return sortedFeatures }
        let normalizedQuery = searchText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return sortedFeatures.filter {
            $0.localizedName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .contains(normalizedQuery)
        }
    }

    /// Países agrupados por primera letra para el índice lateral
    private var groupedSearchResults: [(letter: String, features: [CountryFeature])] {
        let list = searchResults
        guard searchText.isEmpty else { return [(letter: "", features: list)] }

        let grouped = Dictionary(grouping: list) { feature -> String in
            let first = feature.localizedName
                .folding(options: .diacriticInsensitive, locale: .current)
                .prefix(1)
                .uppercased()
            return first.isEmpty ? "#" : first
        }
        return grouped.keys.sorted { $0.localizedCompare($1) == .orderedAscending }.map { letter in
            (letter: letter, features: (grouped[letter] ?? []).sorted { $0.localizedName.localizedCompare($1.localizedName) == .orderedAscending })
        }
    }


    @ViewBuilder
    private func badgesRow() -> some View {
        HStack(spacing: 6) {
            StatBadge(value: visitedCount, label: "Visitados", color: colorTheme.visitedColor)
                .onTapGesture { showAllCountries = true }
            if showBucketList {
                StatBadge(value: bucketListCount, label: "Quiero", color: colorTheme.bucketListColor)
                    .onTapGesture { statusListFilter = .bucketList }
            }
            StatBadge(value: proxCount, label: "Próximos", color: colorTheme.wantToVisitColor)
                .onTapGesture { statusListFilter = .wantToVisit }
        }
    }

    /// Cuenta TOTAL de tramos de vuelo (incluye vueltas + repeticiones) para
    /// el filtro pasado/futuro. 30x ida+vuelta MAD-BCN = 60. Distinto del
    /// `FlightRoutesBuilder.routes.count` que dedupa pares no-ordenados.
    private func flightLegsCount(filter: FlightRouteFilter) -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        var count = 0
        for trip in trips where !trip.isSegmentChild {
            let day = Calendar.current.startOfDay(for: trip.dateFrom)
            switch filter {
            case .past:     if day > today { continue }
            case .upcoming: if day <= today { continue }
            }
            let segs = trip.tripSegments
            if !segs.isEmpty {
                for seg in segs where seg.transport == "✈️" {
                    let out = max(0, (seg.airports?.count ?? 0) - 1)
                    let ret = max(0, (seg.returnAirports?.count ?? 0) - 1)
                    count += out + ret
                }
            } else if trip.transport == "✈️" {
                let airports = trip.tripAirports
                if airports.count > 1 {
                    let totalTouches = airports.reduce(0) { $0 + $1.count }
                    count += totalTouches / 2
                }
            }
        }
        return count
    }

    @ViewBuilder
    private func flightFilterRow() -> some View {
        let count = flightLegsCount(filter: flightRouteFilter)
        let labelTotal: String = {
            switch flightRouteFilter {
            case .past:     return count == 1 ? "1 vuelo finalizado" : "\(count) vuelos finalizados"
            case .upcoming: return count == 1 ? "1 vuelo próximo"    : "\(count) vuelos próximos"
            }
        }()
        VStack(spacing: 8) {
            Text(labelTotal)
                .font(.custom("Satoshi-Bold", size: 12))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .center)
            FlightFilterSlider(selection: $flightRouteFilter)
                .frame(maxWidth: 260)
        }
    }

    @ViewBuilder
    private func counterRow(alignment: VerticalAlignment = .top) -> some View {
        HStack(alignment: alignment, spacing: 8) {
            Text("\(countingMode.denominator)")
                .font(.palatino(.title3, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.cell))
            Spacer()
            Button(action: { showSearch = true }) {
                Image(systemName: "magnifyingglass")
                    .font(.palatino(.title3))
                    .padding(10)
                    .background(.regularMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 6)
    }

    private var nextProximosBanner: (days: Int, flag: String, name: String, isoCode: String, transport: String?, dateFrom: Date?, bookingRef: String, title: String?)? {
        let today = Calendar.current.startOfDay(for: Date())
        var entries: [(days: Int, flag: String, name: String, isoCode: String, date: Date, transport: String?, dateFrom: Date?, trip: Trip?, title: String?)] = []
        // wantToVisit countries — earliest future trip
        for row in allProximoRows where row.country.status == .wantToVisit {
            guard let date = row.dateFrom else { continue }
            let d = Calendar.current.startOfDay(for: date)
            guard d > today else { continue }
            let days = Calendar.current.dateComponents([.day], from: today, to: d).day ?? 0
            let flag = features.first(where: { $0.isoCode == row.isoCode })?.flagEmoji ?? "🌐"
            let name = features.first(where: { $0.isoCode == row.isoCode })?.localizedName ?? row.country.name
            entries.append((days, flag, name, row.isoCode, d, row.transport, date, row.trip, row.rowTitle))
        }
        // visited countries with future trips
        for trip in trips where trip.isoCode != "" {
            let d = Calendar.current.startOfDay(for: trip.dateFrom)
            guard d >= today else { continue }
            guard countries.first(where: { $0.isoCode == trip.isoCode })?.status == .visited else { continue }
            let days = Calendar.current.dateComponents([.day], from: today, to: d).day ?? 0
            guard days > 0 else { continue }
            let flag = features.first(where: { $0.isoCode == trip.isoCode })?.flagEmoji ?? "🌐"
            let name = features.first(where: { $0.isoCode == trip.isoCode })?.localizedName ?? trip.isoCode
            entries.append((days, flag, name, trip.isoCode, d, trip.transport, trip.dateFrom, trip, trip.title))
        }
        guard let next = entries.sorted(by: { $0.date < $1.date }).first else { return nil }
        let ref = bookingRefFromTrip(next.trip)
        return (next.days, next.flag, next.name, next.isoCode, next.transport, next.dateFrom, ref, title: next.title)
    }

    private func bookingRefFromTrip(_ trip: Trip?) -> String {
        guard let trip else { return "" }
        if let seg = trip.tripSegments.first(where: { $0.transport == "✈️" }),
           let ref = seg.flightInfo?.bookingRef, !ref.isEmpty { return ref }
        return trip.flightDetails?.bookingRef ?? ""
    }

    /// Días que faltan hasta el próximo vuelo + IATA del aeropuerto de salida.
    /// Análogo a `nextProximosBanner` pero para el contador del modo vuelo —
    /// muestra "Quedan N días · MAD" arriba del mapa de vuelos. Devuelve nil
    /// si no hay ningún trip ✈️ futuro con aeropuertos guardados.
    /// Usa la misma heurística que `nextFlightAirportsAny()`: ordena trips
    /// primarios futuros por dateFrom, y para el primero busca un segment
    /// ✈️ con airports ≥ 2 (o trip legacy con tripAirports ≥ 2).
    private var nextFlightCounter: (days: Int, depIATA: String)? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let candidates = trips.filter {
            !$0.isSegmentChild && cal.startOfDay(for: $0.dateFrom) >= today
        }.sorted { $0.dateFrom < $1.dateFrom }
        for trip in candidates {
            // Caso segments: prioriza el primer segmento ✈️ del trip por
            // orden cronológico de partida.
            if let seg = trip.tripSegments.sorted(by: { $0.dateFrom < $1.dateFrom })
                            .first(where: { $0.transport == "✈️" && ($0.airports?.count ?? 0) >= 1 }),
               let firstAp = seg.airports?.first {
                let days = cal.dateComponents([.day],
                    from: today,
                    to: cal.startOfDay(for: seg.dateFrom)).day ?? 0
                return (max(0, days), firstAp.iata)
            }
            // Caso legacy: trip sin segments pero con transport ✈️ + airports.
            if trip.tripSegments.isEmpty, trip.transport == "✈️",
               let firstAp = trip.tripAirports.first {
                let days = cal.dateComponents([.day],
                    from: today,
                    to: cal.startOfDay(for: trip.dateFrom)).day ?? 0
                return (max(0, days), firstAp.iata)
            }
        }
        return nil
    }

    /// Aeropuertos (IATA) y coordenadas del próximo vuelo. Busca el primer
    /// trip ✈️ futuro en TODOS los trips (no solo el país del banner) — para
    /// que el widget de mapa de vuelos muestre la ruta aunque el siguiente
    /// viaje del banner no sea ✈️ pero haya un próximo vuelo después.
    /// nil si no hay ningún trip ✈️ futuro con aeropuertos conocidos.
    private func nextFlightAirportsAny() -> (depIATA: String, arrIATA: String, depCoord: CLLocationCoordinate2D, arrCoord: CLLocationCoordinate2D)? {
        let today = Calendar.current.startOfDay(for: Date())
        let candidates = trips.filter {
            !$0.isSegmentChild &&
            Calendar.current.startOfDay(for: $0.dateFrom) >= today
        }.sorted { $0.dateFrom < $1.dateFrom }
        for trip in candidates {
            if let seg = trip.tripSegments.sorted(by: { $0.dateFrom < $1.dateFrom })
                            .first(where: { $0.transport == "✈️" && ($0.airports?.count ?? 0) >= 2 }),
               let aps = seg.airports,
               let firstAp = aps.first,
               let lastAp = aps.last,
               let depCoord = AirportCoordinates.coordinate(for: firstAp.iata),
               let arrCoord = AirportCoordinates.coordinate(for: lastAp.iata) {
                return (firstAp.iata, lastAp.iata, depCoord, arrCoord)
            }
            if trip.tripSegments.isEmpty, trip.transport == "✈️", trip.tripAirports.count >= 2,
               let depCoord = AirportCoordinates.coordinate(for: trip.tripAirports[0].iata),
               let arrCoord = AirportCoordinates.coordinate(for: trip.tripAirports[1].iata) {
                return (trip.tripAirports[0].iata, trip.tripAirports[1].iata, depCoord, arrCoord)
            }
        }
        return nil
    }

    /// Pre-índice de features por ISO. Se invocaba O(n²) antes desde
    /// `topVisitedFlagsString` y `allProximosFlagsString` (cada bandera hacía
    /// `features.first(where:)`). Este dict reduce a O(1) por lookup.
    private var featuresByIso: [String: CountryFeature] {
        Dictionary(uniqueKeysWithValues: features.map { ($0.isoCode, $0) })
    }

    private var allProximosFlagsString: String {
        let today = Calendar.current.startOfDay(for: Date())
        let byIsoIndex = featuresByIso
        // Para cada iso, la PRIMERA fecha futura que tengamos (de cualquier
        // trip futuro de ese país, incluyendo children por segmentos). Si no
        // hay trip pero sí `country.plannedDate`, usamos eso. Esto evita que
        // un país tipo "Chipre del Norte" aparezca con una fecha stale y
        // quede mal ordenado en el widget.
        let tripsByIso: [String: [Trip]] = Dictionary(grouping: trips, by: { $0.isoCode })
        func nextFutureDate(forIso iso: String, fallback: Date?) -> Date? {
            let tripDates = (tripsByIso[iso] ?? [])
                .map { Calendar.current.startOfDay(for: $0.dateFrom) }
                .filter { $0 > today }
            if let earliest = tripDates.min() { return earliest }
            if let fb = fallback {
                let d = Calendar.current.startOfDay(for: fb)
                if d > today { return d }
            }
            return nil
        }
        var byIso: [String: (flag: String, date: Date)] = [:]
        func add(iso: String, date: Date) {
            let flag = byIsoIndex[iso]?.flagEmoji ?? "🌐"
            byIso[iso] = (flag, date)
        }
        for country in countries where country.status == .wantToVisit {
            guard let date = nextFutureDate(forIso: country.isoCode, fallback: country.plannedDate) else { continue }
            add(iso: country.isoCode, date: date)
        }
        for country in countries where country.status == .visited || country.status == .lived {
            guard let date = nextFutureDate(forIso: country.isoCode, fallback: nil) else { continue }
            add(iso: country.isoCode, date: date)
        }
        // Orden estable: fecha asc, tiebreaker por iso asc.
        return byIso.map { (iso: $0.key, flag: $0.value.flag, date: $0.value.date) }
            .sorted { a, b in
                if a.date != b.date { return a.date < b.date }
                return a.iso < b.iso
            }
            .map { $0.flag }
            .joined()
    }

    /// Banderas de países visitados ordenados por fecha del último viaje finalizado
    /// (más reciente primero). Hasta 12 para el widget grande.
    private var topVisitedFlagsString: String {
        let today = Date()
        let byIsoIndex = featuresByIso
        let visited = countries.filter { $0.status == .visited || $0.status == .lived }
        let lastDateByIso: [String: Date] = trips.reduce(into: [:]) { acc, t in
            let end = t.dateTo ?? t.dateFrom
            guard end <= today else { return }
            if let prev = acc[t.isoCode], prev >= end { return }
            acc[t.isoCode] = end
        }
        let sorted = visited.sorted { lhs, rhs in
            let ld = lastDateByIso[lhs.isoCode] ?? .distantPast
            let rd = lastDateByIso[rhs.isoCode] ?? .distantPast
            if ld != rd { return ld > rd }
            return lhs.isoCode < rhs.isoCode
        }
        return sorted.prefix(12).map { c in
            byIsoIndex[c.isoCode]?.flagEmoji ?? "🌐"
        }.joined()
    }

    @ViewBuilder
    private func menuOverlay() -> some View {
        // En modo vuelo el dock se reduce a SOLO el slider Visitados/Próximos
        // centrado — sin botón de pasaporte ni lupa. Fuera de modo vuelo mantiene
        // avatar + badges + búsqueda.
        let dock = Group {
            if flightMode {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    flightFilterRow()
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
            } else {
                HStack(spacing: 0) {
                    Button { showProfile = true } label: {
                        PassportAvatarView(key: selectedPassport, height: 44)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 14)

                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 0.5, height: 34)
                        .padding(.horizontal, 12)

                    Spacer(minLength: 4)
                    badgesRow()
                    Spacer(minLength: 4)

                    Button(action: { showSearch = true }) {
                        VStack(spacing: 2) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 15, weight: .semibold))
                            Text("\(countingMode.denominator)")
                                .font(.custom("Satoshi-Bold", size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.primary)
                        .frame(width: 46, height: 46)
                        .background(Color(.systemGray5), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 14)
                }
                .frame(height: 70)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 6)
                .padding(.horizontal, 12)
            }
        }

        if menuPositionIsTop {
            VStack(spacing: 0) {
                dock.padding(.top, 28)
                Spacer()
            }
        } else {
            VStack(spacing: 0) {
                Spacer()
                dock.padding(.bottom, 28)
            }
        }
    }

    var body: some View {
        bodyContent()
            .ignoresSafeArea(.keyboard)
            .alert("¿Te gusta Raskmap?", isPresented: $showReviewAlert) {
                Button("Valorar ahora") { requestReview() }
                Button("Ahora no", role: .cancel) { }
                Button("No mostrar más", role: .destructive) { neverShowReview = true }
            } message: {
                Text("Si te está siendo útil, una valoración nos ayuda mucho.")
            }
    }

    @ViewBuilder
    private func bodyContent() -> some View {
        bodyWithAchievementHandlers()
            .onChange(of: flightMode) { _, _ in recalculateFlightRouteAvailability() }
            .onChange(of: flightRouteFilter) { _, _ in recalculateFlightRouteAvailability() }
            .onChange(of: liveActivityEnabled) { _, enabled in handleLiveActivityEnabledChange(enabled) }
            .onChange(of: liveActivityKey) { _, _ in handleLiveActivityKeyChange() }
            .onChange(of: isRaskmapPro) { _, isPro in handleProChange(isPro) }
            .onChange(of: _appFontFamily) { _, family in handleFontFamilyChange(family) }
    }

    /// Fingerprint compacto de los trips: dispara `handleTripsCountChange` no
    /// solo al insertar/borrar (count), sino también cuando un trip existente
    /// cambia `dateFrom`, `dateTo`, `transport` o `isoCode`. Antes el banner
    /// del próximo viaje y el snapshot del widget de mapa quedaban stale al
    /// editar un trip sin alterar el número total.
    private var tripsFingerprint: String {
        trips.map { t in
            "\(t.isoCode)|\(t.dateFrom.timeIntervalSince1970)|\(t.dateTo?.timeIntervalSince1970 ?? 0)|\(t.transport ?? "")"
        }
        .sorted()
        .joined(separator: "·")
    }

    @ViewBuilder
    private func bodyWithAchievementHandlers() -> some View {
        bodyWithCoreHandlers()
            .onChange(of: multiContinentRaw) { _, _ in checkAndShowAchievementToasts() }
            .onChange(of: multiHemisphereRaw) { _, _ in checkAndShowAchievementToasts() }
            .onChange(of: tripsFingerprint) { _, _ in handleTripsCountChange() }
            .onChange(of: mapQuadrantsData) { _, _ in checkAndShowAchievementToasts() }
            // Re-evaluar logros al marcar/desmarcar maravillas modernas —
            // dispara la celebración del logro `sieteMaravillas` cuando se
            // marca la 7ª desde `ModernWondersSheet`.
            .onChange(of: modernWondersRaw) { _, _ in checkAndShowAchievementToasts() }
            .onChange(of: visitedCountAll) { _, newCount in handleVisitedCountChange(newCount) }
            .onChange(of: countingModeRaw) { _, newMode in handleCountingModeChange(newMode) }
    }

    @ViewBuilder
    private func bodyWithCoreHandlers() -> some View {
        mapWithSheets()
            .overlay { loadingOverlay() }
            .overlay { helpToastOverlay() }
            .onChange(of: locationManager.currentLocation) { old, loc in handleLocationChange(old: old, location: loc) }
            .task { await handleInitialTask() }
            .onChange(of: scenePhase) { _, phase in handleScenePhaseActive(phase) }
    }

    @ViewBuilder
    private func helpToastOverlay() -> some View {
        if showHelpToast {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showHelpToast = false } }
                VStack(spacing: 18) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(BrandColor.accent)
                    Text("Ayuda")
                        .font(.custom("Satoshi-Bold", size: 22))
                    Text("Si te faltan aeropuertos, aerolíneas o has tenido un bug, repórtalo en **Ajustes › Contacto**.")
                        .font(.palatino(.body))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showHelpToast = false }
                    } label: {
                        Text("Entendido")
                            .font(.custom("Satoshi-Bold", size: 15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(BrandColor.accent, in: RoundedRectangle(cornerRadius: Radius.card))
                    }.buttonStyle(.plain)
                }
                .padding(28)
                .frame(maxWidth: 340)
                .background(.thickMaterial, in: RoundedRectangle(cornerRadius: Radius.sheet))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sheet)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .padding(.horizontal, 28)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showHelpToast)
        }
    }

    @ViewBuilder
    private func loadingOverlay() -> some View {
        if isLoadingFeatures {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0x12/255, green: 0x1B/255, blue: 0x3A/255),
                        Color(red: 0x1E/255, green: 0x33/255, blue: 0x6A/255),
                        Color(red: 0x40/255, green: 0x6E/255, blue: 0xC9/255)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ).ignoresSafeArea()
                VStack(spacing: 32) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            .frame(width: 132, height: 132)
                        Circle()
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                            .frame(width: 168, height: 168)
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(.white)
                    }
                    VStack(spacing: 6) {
                        Text("RASKMAP")
                            .font(.custom("Satoshi-Bold", size: 30))
                            .tracking(6)
                            .foregroundStyle(.white)
                        Text("Cargando el mundo...")
                            .font(.custom("Satoshi-Regular", size: 12))
                            .tracking(1.5)
                            .textCase(.uppercase)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.0)
                }
            }
            .transition(.opacity)
            .animation(.easeOut(duration: 0.5), value: isLoadingFeatures)
        }
    }

    fileprivate func handleLocationChange(old: CLLocation?, location: CLLocation?) {
        guard let location else { locationIsoCode = nil; return }
        checkLocationCountry(location, immediate: old == nil)
    }


    fileprivate func handleTripsCountChange() {
        // Re-evalúa Country.status: si tras borrar el último trip de un país
        // visited queda sin pasados ni futuros ni visitCount manual, vuelve
        // a .none (o .wantToVisit si tenía planned). Antes esto solo corría
        // al arrancar la app y dejaba estados stale entre sesiones.
        cleanupZeroXVisitedStates()
        cleanupOrphanChildTrips()
        checkAndShowAchievementToasts()
        WidgetDataWriter.sync(countries: countries)
        WidgetDataWriter.syncCountingMode(countingMode.rawValue)
        WidgetDataWriter.syncTopVisitedFlags(topVisitedFlagsString)
        let b = nextProximosBanner
        cachedNextBanner = b
        WidgetDataWriter.syncNextTrip(flag: b?.flag, days: b?.days, name: b?.name, transport: b?.transport, dateFrom: b?.dateFrom, bookingRef: b?.bookingRef, title: b?.title)
        WidgetDataWriter.syncAllFlags(allProximosFlagsString)
        let af = nextFlightAirportsAny()
        WidgetDataWriter.syncNextFlightSnapshot(depIATA: af?.depIATA, arrIATA: af?.arrIATA, depCoord: af?.depCoord, arrCoord: af?.arrCoord)
        recalculateFlightRouteAvailability()
        // Reprograma recordatorios de viaje si el usuario los tiene activos.
        if tripRemindersEnabled {
            TripNotifications.reschedule(trips: trips, featuresByIso: featuresByIso)
        }
    }

    /// Borra child trips (`isSegmentChild`) cuyo primary ya no existe en
    /// `trips` (mismo `segmentGroupID`). Sin esto, los huérfanos siguen
    /// apareciendo en stats y en listas de país después de borrar el
    /// primary. Sucede principalmente con borrados parciales (delete
    /// manual desde country list sin cascada).
    fileprivate func cleanupOrphanChildTrips() {
        let primaryGIDs = Set(trips.compactMap { $0.isSegmentChild ? nil : $0.segmentGroupID })
        var changed = false
        for trip in trips where trip.isSegmentChild {
            guard let gid = trip.segmentGroupID, !primaryGIDs.contains(gid) else { continue }
            modelContext.delete(trip)
            changed = true
        }
        if changed { modelContext.saveOrWarn() }
    }

    fileprivate func handleVisitedCountChange(_ newCount: Int) {
        if newCount == 5 && !neverShowReview { showReviewAlert = true }
        let b = nextProximosBanner
        cachedNextBanner = b
        WidgetDataWriter.syncNextTrip(flag: b?.flag, days: b?.days, name: b?.name, transport: b?.transport, dateFrom: b?.dateFrom, bookingRef: b?.bookingRef, title: b?.title)
        WidgetDataWriter.syncAllFlags(allProximosFlagsString)
        let af = nextFlightAirportsAny()
        WidgetDataWriter.syncNextFlightSnapshot(depIATA: af?.depIATA, arrIATA: af?.arrIATA, depCoord: af?.depCoord, arrCoord: af?.arrCoord)
    }

    fileprivate func handleCountingModeChange(_ newMode: String) {
        WidgetDataWriter.syncCountingMode(newMode)
        WidgetCenter.shared.reloadAllTimelines()
    }

    fileprivate func handleLiveActivityEnabledChange(_ enabled: Bool) {
        if enabled { startOrUpdateLiveActivity() } else { stopLiveActivity() }
    }

    fileprivate func handleLiveActivityKeyChange() {
        if liveActivityEnabled { startOrUpdateLiveActivity() }
    }

    fileprivate func handleProChange(_ isPro: Bool) {
        if !isPro {
            stopLiveActivity()
            showCountdown = false
            liveActivityEnabled = false
        } else {
            showCountdown = true
        }
        WidgetDataWriter.syncPro(isPro)
    }

    fileprivate func handleFontFamilyChange(_ family: String) {
        WidgetDataWriter.syncFontFamily(family)
    }

    @ViewBuilder
    private func mapWithSheets() -> some View {
        mapCore()
            .sheet(item: $selectedCountry, onDismiss: {
                highlightedIsoCode = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.1))
                    recheckLocationIfNeeded()
                }
                // Open AddTripSheet after country sheet fully dismissed
                if shouldOpenAddTrip, let lastCountry = lastModifiedCountry {
                    shouldOpenAddTrip = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.2))
                        pendingAddTripCountry = lastCountry
                    }
                }
            }) { country in
                CountryBottomSheet(
                    country: country,
                    displayName: localizedName(for: country),
                    flagEmoji: flagEmoji(for: country),
                    isoA2: features.first(where: { $0.isoCode == country.isoCode })?.isoA2,
                    onStatusChange: { newStatus in
                        updateCountryStatus(country: country, newStatus: newStatus)
                        selectedCountry = nil
                    },
                    onDismiss: {
                        selectedCountry = nil
                        highlightedIsoCode = nil
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.1))
                            recheckLocationIfNeeded()
                        }
                    },
                    showBucketList: showBucketList,
                    onAddPastTrip: {
                        scheduleSheetTransition { pendingAddTripCountry = country }
                    },
                    onAddNextTrip: {
                        scheduleSheetTransition {
                            pendingDateIsNew = true
                            pendingDateCountry = country
                            pendingDateStatus = .wantToVisit
                        }
                    },
                    onEditTrips: {
                        scheduleSheetTransition { bannerTappedCountry = country }
                    }
                )
                .presentationDetents(country.status == .visited ? [.fraction(0.60)] : (country.status == .lived ? [.fraction(0.38)] : [.fraction(0.50)]))
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showSearch, onDismiss: {
                if pendingShowSheet { pendingShowSheet = false; showSheet = true }
            }) { searchSheet() }
            .fullScreenCover(isPresented: $showOnboarding) { onboardingSheet() }
            .sheet(isPresented: $showAllCountries) {
                let visitedCodes: Set<String> = Set(countries.compactMap { country -> String? in
                    if country.status == .visited || country.status == .lived { return country.isoCode }
                    return nil
                })
                AllCountriesSheet(features: features, mode: countingMode, visitedIsoCodes: visitedCodes, countries: countries, trips: trips,
                    onCountryDeleted: { isoCode in
                        if let emoji = features.first(where: { $0.isoCode == isoCode })?.flagEmoji {
                            removeFromTopTable(flagEmojis: Set([emoji]))
                        }
                    })
            }
            .sheet(item: $statusListFilter) { filter in
                StatusListSheet(
                    filter: filter,
                    countries: filter == .wantToVisit ? [] : countries,
                    proximoRows: filter == .wantToVisit ? allProximoRows : [],
                    features: features,
                    trips: trips,
                    onRemove: { country in
                        let today = Calendar.current.startOfDay(for: Date())
                        switch filter {
                        case .visited:
                            // Delete ALL trips + cascade groups + unmark as visited
                            var processedGroupIDs = Set<String>()
                            var seenIDs = Set<ObjectIdentifier>()
                            var allToDelete: [Trip] = []
                            for trip in trips where trip.isoCode == country.isoCode {
                                if let gid = trip.segmentGroupID, !processedGroupIDs.contains(gid) {
                                    processedGroupIDs.insert(gid)
                                    let desc = FetchDescriptor<Trip>(predicate: #Predicate { $0.segmentGroupID == gid })
                                    for t in modelContext.fetchOrWarn(desc, fallback: [trip]) {
                                        if seenIDs.insert(ObjectIdentifier(t)).inserted { allToDelete.append(t) }
                                    }
                                } else if trip.segmentGroupID == nil {
                                    if seenIDs.insert(ObjectIdentifier(trip)).inserted { allToDelete.append(trip) }
                                }
                            }
                            let siblingIsos = Set(allToDelete.map { $0.isoCode }).subtracting([country.isoCode])
                            let removedEmoji = flagEmoji(for: country).map { Set([$0]) } ?? []
                            country.status = .none
                            country.visitCount = 0
                            country.hasLived = false
                            country.plannedDate = nil
                            country.plannedDateTo = nil
                            country.transport = nil
                            country.plannedTitle = nil
                            for t in allToDelete { modelContext.delete(t) }
                            removeFromTopTable(flagEmojis: removedEmoji)
                            modelContext.saveOrWarn()
                            for iso in siblingIsos {
                                let cd = FetchDescriptor<Country>(predicate: #Predicate { $0.isoCode == iso })
                                guard let c = modelContext.fetchFirstOrWarn(cd) else { continue }
                                guard c.status == .visited || c.status == .lived else { continue }
                                let td = FetchDescriptor<Trip>(predicate: #Predicate { $0.isoCode == iso })
                                let remaining = modelContext.fetchOrWarn(td)
                                let today = Calendar.current.startOfDay(for: Date())
                                let hasPast = remaining.contains { Calendar.current.startOfDay(for: $0.dateFrom) <= today }
                                let hasFuture = remaining.contains { Calendar.current.startOfDay(for: $0.dateFrom) > today }
                                guard !hasPast && c.visitCount == 0 else { continue }
                                if c.plannedDate != nil || hasFuture {
                                    c.status = .wantToVisit
                                } else {
                                    c.status = .none
                                    c.hasLived = false
                                    c.plannedDate = nil
                                    c.plannedDateTo = nil
                                    c.transport = nil
                                    c.plannedTitle = nil
                                }
                            }
                            // Antes: si el país coincidía con la ubicación actual,
                            // se re-marcaba automáticamente como visitado vía
                            // autoMarkIfNeeded. Esa lógica se eliminó — la
                            // detección de ubicación ya no muta el status.
                        case .wantToVisit:
                            // Delete all future trips and remove from Próximos list
                            for trip in trips where trip.isoCode == country.isoCode {
                                if Calendar.current.startOfDay(for: trip.dateFrom) >= today {
                                    modelContext.delete(trip)
                                }
                            }
                            if country.status == .wantToVisit {
                                country.status = .none
                                country.plannedDate = nil
                                country.plannedDateTo = nil
                                country.transport = nil
                                country.plannedTitle = nil
                            }
                        default:
                            // bucketList / lived / etc: just remove from list
                            country.status = .none
                            country.hasLived = false
                        }
                        modelContext.saveOrWarn()
                    },
                    onSetDate: filter == .wantToVisit ? { country, trip in
                        if let trip = trip {
                            statusListFilter = nil
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(0.35))
                                editingFutureTrip = trip
                            }
                        } else {
                            deferredDateCountry = country
                            statusListFilter = nil
                        }
                    } : nil,
                    onRemoveProximo: filter == .wantToVisit ? { row in
                        let today = Calendar.current.startOfDay(for: Date())
                        let country = row.country
                        if let trip = row.trip {
                            modelContext.delete(trip)
                            // Recalculate plannedDate to next earliest future trip
                            let tripID = ObjectIdentifier(trip)
                            let remaining = trips.filter {
                                $0.isoCode == country.isoCode &&
                                ObjectIdentifier($0) != tripID &&
                                Calendar.current.startOfDay(for: $0.dateFrom) > today
                            }.sorted { $0.dateFrom < $1.dateFrom }
                            if let earliest = remaining.first {
                                country.plannedDate = earliest.dateFrom
                                country.plannedDateTo = earliest.dateTo
                                country.transport = earliest.transport
                                country.plannedTitle = earliest.title
                            } else {
                                country.status = .none
                                country.plannedDate = nil
                                country.plannedDateTo = nil
                                country.transport = nil
                                country.plannedTitle = nil
                            }
                        } else {
                            country.status = .none
                            country.plannedDate = nil
                            country.plannedDateTo = nil
                            country.transport = nil
                            country.plannedTitle = nil
                        }
                        modelContext.saveOrWarn()
                    } : nil,
                    onDeleteAll: {
                        let today = Calendar.current.startOfDay(for: Date())
                        switch filter {
                        case .visited:
                            let allTripsDesc = FetchDescriptor<Trip>()
                            let allTrips = modelContext.fetchOrWarn(allTripsDesc)
                            for t in allTrips { modelContext.delete(t) }
                            let deletedEmojis = Set(countries.filter { $0.status == .visited || $0.status == .lived }.compactMap { flagEmoji(for: $0) })
                            for c in countries where c.status == .visited || c.status == .lived {
                                c.status = .none; c.visitCount = 0; c.hasLived = false
                                c.plannedDate = nil; c.plannedDateTo = nil
                                c.transport = nil; c.plannedTitle = nil
                            }
                            removeFromTopTable(flagEmojis: deletedEmojis)
                        case .wantToVisit:
                            for c in countries where c.status == .wantToVisit {
                                let iso = c.isoCode
                                let desc = FetchDescriptor<Trip>(predicate: #Predicate { $0.isoCode == iso })
                                for t in modelContext.fetchOrWarn(desc) {
                                    if Calendar.current.startOfDay(for: t.dateFrom) > today { modelContext.delete(t) }
                                }
                                c.status = .none; c.plannedDate = nil; c.plannedDateTo = nil
                                c.transport = nil; c.plannedTitle = nil
                            }
                            for c in countries where c.status == .visited || c.status == .lived {
                                let iso = c.isoCode
                                let desc = FetchDescriptor<Trip>(predicate: #Predicate { $0.isoCode == iso })
                                for t in modelContext.fetchOrWarn(desc) {
                                    if Calendar.current.startOfDay(for: t.dateFrom) > today { modelContext.delete(t) }
                                }
                            }
                        default:
                            for c in countries where c.status == filter {
                                c.status = .none; c.hasLived = false
                            }
                        }
                        modelContext.saveOrWarn()
                    }
                )
            }
            .sheet(item: $editingFutureTrip, onDismiss: {
                guard let isoCode = lastEditedFutureTripIso else { return }
                let today = Calendar.current.startOfDay(for: Date())
                let countryDesc = FetchDescriptor<Country>(predicate: #Predicate { $0.isoCode == isoCode })
                guard let country = modelContext.fetchFirstOrWarn(countryDesc),
                      country.status == .wantToVisit else { return }
                let tripDesc = FetchDescriptor<Trip>(predicate: #Predicate { $0.isoCode == isoCode })
                let allTrips = modelContext.fetchOrWarn(tripDesc)
                let futureTrips = allTrips
                    .filter { Calendar.current.startOfDay(for: $0.dateFrom) > today && !$0.isSegmentChild }
                    .sorted { $0.dateFrom < $1.dateFrom }
                if let earliest = futureTrips.first {
                    country.transport = earliest.transport
                    country.plannedDate = earliest.dateFrom
                    country.plannedDateTo = earliest.dateTo
                    country.plannedTitle = earliest.title
                    modelContext.saveOrWarn()
                }
                let b = nextProximosBanner
                cachedNextBanner = b
                WidgetDataWriter.syncNextTrip(flag: b?.flag, days: b?.days, name: b?.name, transport: b?.transport, dateFrom: b?.dateFrom, bookingRef: b?.bookingRef, title: b?.title)
                // Evitar que el iso anterior se reutilice si el usuario reabre rápido
                // antes de que el nuevo sheet haga .onAppear.
                lastEditedFutureTripIso = nil
            }) { trip in
                EditTripSheet(trip: trip, isForFuture: true, features: features)
                    .onAppear { lastEditedFutureTripIso = trip.isoCode }
            }
            .sheet(item: $bannerTappedCountry, onDismiss: {
                let b = nextProximosBanner
                cachedNextBanner = b
                WidgetDataWriter.syncNextTrip(flag: b?.flag, days: b?.days, name: b?.name, transport: b?.transport, dateFrom: b?.dateFrom, bookingRef: b?.bookingRef, title: b?.title)
            }) { country in
                CountryTripsSheet(
                    country: country,
                    trips: trips.filter { $0.isoCode == country.isoCode },
                    displayName: localizedName(for: country),
                    flagEmoji: flagEmoji(for: country) ?? "🌐",
                    features: features
                )
            }
            .sheet(item: $pendingDateCountry, onDismiss: { pendingDateIsNew = false }) { country in datePicker(for: country) }
            .sheet(item: $pendingAddTripCountry) { country in
                AddTripSheet(
                    isoCode: country.isoCode,
                    displayName: localizedName(for: country),
                    flagEmoji: flagEmoji(for: country) ?? "🌐",
                    features: features,
                    onSave: { trip, childNames in
                        modelContext.insert(trip)
                        modelContext.saveOrWarn()
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.1))
                            refreshTrigger.toggle()
                        }
                        // Show stacked toasts for main country + newly visited segment countries
                        var msgs: [String] = []
                        if statusBeforeVisit != .visited {
                            let flag = flagEmoji(for: country) ?? ""
                            msgs.append("\(flag) \(localizedName(for: country))".trimmingCharacters(in: .whitespaces))
                        }
                        msgs.append(contentsOf: childNames)
                        if !msgs.isEmpty {
                            visitedToastMessages = msgs
                            Task { @MainActor in try? await Task.sleep(for: .seconds(2.5)); visitedToastMessages = [] }
                        }
                    },
                    onCancel: {
                        // Only revert if we changed the status (not for visited->addTrip)
                        if statusBeforeVisit != .visited {
                            country.status = statusBeforeVisit
                            modelContext.saveOrWarn()
                        } else {
                            fixZeroXVisitedIfNeeded(country: country)
                        }
                    }
                )
            }
            .onChange(of: statusListFilter) { _, newValue in
                if newValue == nil, let deferred = deferredDateCountry {
                    deferredDateCountry = nil
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.35))
                        pendingDateCountry = deferred
                    }
                }
            }
            .sheet(isPresented: $showProfile) { profileContent() }
            // El sheet de finalizados se presenta desde DENTRO de ProfileSheet
            // para evitar el bug de sheet-sobre-sheet: SwiftUI sólo puede tener
            // un sheet activo por nivel, así que presentarlo desde el root obligaba
            // a cerrar el perfil primero para que apareciera. Ver ProfileSheet.
            .sheet(isPresented: $showSubscription) { SubscriptionSheet() }
    }

    @ViewBuilder
    private func mapCore() -> some View {
        ZStack(alignment: menuPositionIsTop ? .top : .bottom) {
            let _ = refreshTrigger
            RaskMapView(
                countries: countries, features: features,
                onCountryTapped: { handleCountryTap($0) },
                highlightedIsoCode: highlightedIsoCode,
                showBucketList: showBucketList,
                locationIsoCode: locationIsoCode,
                onReady: { mapStore.centerOnCountry = $0 },
                flightMode: flightMode,
                flightRouteFilter: flightRouteFilter,
                trips: trips
            )
            .ignoresSafeArea()
            menuOverlay()
                .ignoresSafeArea(.keyboard)

            flightModeButton()

            // Próximos countdown banner / ad banner — opposite side to menu.
            // Ambos solo en modo mapa (fuera de modo vuelo).
            if !flightMode, !isRaskmapPro {
                VStack(spacing: 0) {
                    if menuPositionIsTop { Spacer() }
                    BannerAdView()
                        .frame(width: 320, height: 50)
                        .padding(.bottom, menuPositionIsTop ? 8 : 0)
                        .padding(.top, menuPositionIsTop ? 0 : 8)
                    if !menuPositionIsTop { Spacer() }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else if !flightMode, showCountdown, let banner = cachedNextBanner {
                // Pro + contador activo
                VStack {
                    if menuPositionIsTop { Spacer() }
                    let dayWord = banner.days == 1 ? "día" : "días"
                    let quedaWord = banner.days == 1 ? "Queda" : "Quedan"
                    Button {
                        statusListFilter = .wantToVisit
                    } label: {
                        HStack(spacing: 8) {
                            FlagLabel(emoji: banner.flag, size: 17)
                            Text("\(quedaWord) \(banner.days) \(dayWord)")
                                .font(.palatino(.footnote, weight: .bold))
                                .foregroundStyle(.primary)
                            Text("· \(banner.name)")
                                .font(.palatino(.footnote))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, menuPositionIsTop ? 16 : 0)
                    .padding(.top, menuPositionIsTop ? 0 : 16)
                    if !menuPositionIsTop { Spacer() }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else if flightMode, showCountdown, let info = nextFlightCounter {
                // Contador equivalente para MODO VUELO. Mismo formato visual
                // que el banner del modo mapa pero usando ✈️ + IATA del
                // aeropuerto de salida en lugar de bandera + nombre país.
                VStack {
                    if menuPositionIsTop { Spacer() }
                    let dayWord = info.days == 1 ? "día" : "días"
                    let quedaWord = info.days == 1 ? "Queda" : "Quedan"
                    HStack(spacing: 8) {
                        Text("✈️").font(.system(size: 17))
                        Text("\(quedaWord) \(info.days) \(dayWord)")
                            .font(.palatino(.footnote, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("· \(info.depIATA)")
                            .font(.palatino(.footnote))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
                    .padding(.bottom, menuPositionIsTop ? 16 : 0)
                    .padding(.top, menuPositionIsTop ? 0 : 16)
                    if !menuPositionIsTop { Spacer() }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }

            // Ripple celebratorio cuando se marca un país como visitado por
            // primera vez. Centrado en pantalla (cooperativo con el centerMap
            // que se dispara casi a la vez). Anillo verde expandiéndose +
            // fade out. ~0.9s total.
            if rippleCountryIso != nil {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(colorTheme.visitedColor.opacity(0.7), lineWidth: 3)
                            .scaleEffect(rippleCountryIso != nil ? 3.0 : 0.1)
                            .opacity(rippleCountryIso != nil ? 0 : 1)
                            .frame(width: 80, height: 80)
                            .animation(
                                .easeOut(duration: 0.9).delay(Double(i) * 0.15),
                                value: rippleCountryIso
                            )
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            // Visited toast (stacked, one per country)
            if !visitedToastMessages.isEmpty {
                VStack {
                    Spacer()
                    VStack(spacing: 8) {
                        ForEach(visitedToastMessages, id: \.self) { msg in
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(colorTheme.visitedColor)
                                    .font(.body)
                                Text(msg)
                                    .font(.palatino(.subheadline, weight: .bold))
                                    .foregroundStyle(.primary)
                            }
                            .padding(.horizontal, 20).padding(.vertical, 13)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.section, style: .continuous))
                            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
                        }
                    }
                    .padding(.bottom, menuPositionIsTop ? 40 : 124)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: visitedToastMessages.count)
            }

            // First-time location auto-mark toast (centered, manual dismiss)
            if showLocationToast {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 20) {
                        Image(systemName: "location.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.blue)
                        VStack(spacing: 8) {
                            Text("Ubicación detectada")
                                .font(.palatino(.headline, weight: .bold))
                            Text("Se ha marcado el país de tu localización como visitado. Puedes editarlo en la lista de Visitados.")
                                .font(.palatino(.subheadline))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        Button {
                            withAnimation { showLocationToast = false }
                        } label: {
                            Text("Entendido")
                                .font(.palatino(.body, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                                .foregroundStyle(.white)
                        }.buttonStyle(.plain)
                    }
                    .padding(28)
                    // .thickMaterial tiene mejor contraste sobre fondos oscuros
                    // que .regularMaterial. Border sutil refuerza separación.
                    .background(.thickMaterial, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .padding(.horizontal, 28)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showLocationToast)
            }

            // Empty state del modo vuelos: cuando no hay rutas para el filtro actual.
            // Solo se muestra cuando el overlay de transición no está activo.
            if flightMode, !flightModeHasRoutes, flightTransitionTarget == nil {
                flightEmptyState()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(50)
            }

            // Overlay full-screen al alternar modo vuelos / mapa (oculta el cambio visual).
            if let target = flightTransitionTarget {
                FlightModeTransition(toFlightMode: target)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(999)
                    .allowsHitTesting(true)
            }
        }
    }

    /// Trips que matchean el `searchText` actual — busca en título y nombre
    /// localizado del país. Ordenados por dateFrom desc (más reciente primero).
    private var matchingTrips: [Trip] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let byIso = featuresByIso
        return trips.filter { trip in
            if let title = trip.title, !title.isEmpty,
               title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(q) {
                return true
            }
            let countryName = byIso[trip.isoCode]?.localizedName ?? trip.isoCode
            return countryName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(q)
        }
        .sorted { $0.dateFrom > $1.dateFrom }
    }

    private func searchSheet() -> some View {
        NavigationStack {
            List {
                // Sección de viajes (solo cuando hay query y hay matches).
                if !searchText.isEmpty && !matchingTrips.isEmpty {
                    Section("Viajes") {
                        ForEach(matchingTrips.prefix(10), id: \.persistentModelID) { trip in
                            Button {
                                openTripFromSearch(trip)
                            } label: {
                                HStack(spacing: 10) {
                                    let feat = featuresByIso[trip.isoCode]
                                    FlagLabel(emoji: feat?.flagEmoji ?? "🌐", size: 17)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text({
                                            let t = trip.title ?? ""
                                            return t.isEmpty ? (feat?.localizedName ?? trip.isoCode) : t
                                        }())
                                            .font(.palatino(.body, weight: .bold))
                                            .foregroundStyle(.primary)
                                        Text(searchTripSubtitle(trip))
                                            .font(.palatino(.caption))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                // Sección de países (existente).
                Section(searchText.isEmpty ? "" : "Países") {
                    if searchText.isEmpty {
                        ForEach(groupedSearchResults, id: \.letter) { section in
                            Section(header: Text(section.letter)) {
                                ForEach(section.features, id: \.isoCode) { feature in
                                    countryRow(feature)
                                }
                            }
                        }
                    } else {
                        ForEach(groupedSearchResults.flatMap { $0.features }, id: \.isoCode) { feature in
                            countryRow(feature)
                        }
                    }
                }
                // Empty state visualmente rich: query no vacía pero sin matches.
                // SF Symbol grande + título bold + sugerencia + emoji decorativo.
                if !searchText.isEmpty && matchingTrips.isEmpty
                    && groupedSearchResults.allSatisfy({ $0.features.isEmpty }) {
                    Section {
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color(.systemGray6))
                                    .frame(width: 92, height: 92)
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 38, weight: .regular))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 28)
                            Text("Sin resultados")
                                .font(.palatino(.title3, weight: .bold))
                            Text("Prueba con otro nombre de país o viaje 🌍")
                                .font(.palatino(.subheadline))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                                .padding(.bottom, 24)
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .scrollIndicators(.visible)
            .searchable(text: $searchText, prompt: "Buscar país o viaje…")
            .navigationTitle("Buscar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { showSearch = false; searchText = "" }
                }
            }
        }
    }

    @ViewBuilder
    private func countryRow(_ feature: CountryFeature) -> some View {
        HStack {
            FlagLabel(emoji: feature.flagEmoji ?? "🌐", size: 17)
            Text(feature.localizedName).foregroundStyle(.primary)
            Spacer()
            if let status = countryStatusMap[feature.isoCode], status != .none {
                Text(status.label).font(.palatino(.caption)).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            let isoCode = feature.isoCode
            if let existing = countries.first(where: { $0.isoCode == isoCode }) {
                selectedCountry = existing
            } else {
                let newCountry = Country(name: feature.name, isoCode: isoCode)
                modelContext.insert(newCountry)
                selectedCountry = newCountry
            }
            highlightedIsoCode = isoCode
            centerMap(on: isoCode)
            pendingShowSheet = true
            showSearch = false
        }
    }

    private func searchTripSubtitle(_ trip: Trip) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.locale = Locale(identifier: "es_ES")
        let from = df.string(from: trip.dateFrom)
        if let to = trip.dateTo, to != trip.dateFrom {
            return "\(from) → \(df.string(from: to))"
        }
        return from
    }

    /// Tras buscar y tocar un trip: si es futuro, abre EditTripSheet en modo
    /// editar próximo; si es pasado, abre el detalle. Cierra el search sheet
    /// con el patrón scheduleSheetTransition para evitar conflictos.
    private func openTripFromSearch(_ trip: Trip) {
        showSearch = false
        searchText = ""
        let today = Calendar.current.startOfDay(for: Date())
        let isFuture = Calendar.current.startOfDay(for: trip.dateFrom) > today
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if isFuture {
                editingFutureTrip = trip
            } else {
                bannerTappedCountry = countries.first(where: { $0.isoCode == trip.isoCode })
            }
        }
    }

    @ViewBuilder
    private func onboardingSheet() -> some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                Group {
                    switch onboardingStep {
                    case 0: onboardingUsernameStep()
                    case 1: onboardingPassportStep()
                    case 2: onboardingTourCategoriesStep()
                    default: onboardingTourFinalStep()
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: onboardingStep)
            // Indicador de pasos en la parte inferior.
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(onboardingStep == i ? Color(red: 0x53/255, green: 0xA3/255, blue: 0xFE/255) : Color(.systemGray4))
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.bottom, 22)
            }
            .allowsHitTesting(false)
        }
        .interactiveDismissDisabled(true)
    }

    @ViewBuilder
    private func onboardingUsernameStep() -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 36) {
                VStack(spacing: 14) {
                    Text("🗺️")
                        .font(.system(size: 72))
                    VStack(spacing: 8) {
                        Text("Bienvenido a Raskmap")
                            .font(.custom("Satoshi-Bold", size: 26))
                            .multilineTextAlignment(.center)
                        Text("¿Cómo quieres que te llamemos?")
                            .font(.palatino(.subheadline))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                VStack(spacing: 14) {
                    TextField("Tu nombre de usuario", text: $usernameInput)
                        .font(.palatino(.body))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .submitLabel(.done)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        .onChange(of: usernameInput) {
                            usernameInput = String(usernameInput.filter { $0.isLetter || $0.isNumber }.prefix(10))
                        }
                        .padding(.horizontal, 32)
                    Button(action: {
                        let clean = String(usernameInput.filter { $0.isLetter || $0.isNumber }.prefix(10))
                        if !clean.isEmpty {
                            username = clean
                            onboardingStep = 1
                        }
                    }) {
                        Text("Continuar")
                            .font(.palatino(.body, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                usernameInput.isEmpty
                                    ? Color(.systemGray4)
                                    : Color(red: 0x53/255, green: 0xA3/255, blue: 0xFE/255),
                                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            )
                            .foregroundStyle(.white)
                    }
                    .disabled(usernameInput.isEmpty)
                    .padding(.horizontal, 32)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func onboardingPassportStep() -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("Elige tu pasaporte")
                    .font(.custom("Satoshi-Bold", size: 26))
                    .multilineTextAlignment(.center)
                Text("Será tu avatar en la app. Puedes cambiarlo más tarde.")
                    .font(.palatino(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 28)
            .padding(.bottom, 16)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16),
                                    GridItem(.flexible(), spacing: 16)],
                          spacing: 16) {
                    ForEach(PassportOption.allCases) { opt in
                        PassportSelectableCard(key: opt.rawValue,
                                               isSelected: selectedPassport == opt.rawValue)
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    selectedPassport = opt.rawValue
                                }
                            }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            Button(action: {
                onboardingStep = 2  // sigue con el tour de categorías
            }) {
                Text("Continuar")
                    .font(.palatino(.body, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 0x53/255, green: 0xA3/255, blue: 0xFE/255),
                                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    /// Step 3 — tour de categorías y mapa. Explica visited / próximos / quiero.
    @ViewBuilder
    private func onboardingTourCategoriesStep() -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(Color(red: 0x53/255, green: 0xA3/255, blue: 0xFE/255))
                    Text("Tres listas para tu mundo")
                        .font(.custom("Satoshi-Bold", size: 24))
                        .multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: 18) {
                    onboardingTourRow(
                        emoji: "✅",
                        title: "Visitados",
                        body: "Países o territorios donde ya has estado. Los pintamos de rojo."
                    )
                    onboardingTourRow(
                        emoji: "🔜",
                        title: "Próximos",
                        body: "Viajes ya planeados con fecha. Los pintamos de verde."
                    )
                    onboardingTourRow(
                        emoji: "📝",
                        title: "Quiero",
                        body: "Tu wishlist de destinos sin fecha aún. Naranja en el mapa."
                    )
                }
                .padding(.horizontal, 32)
            }
            Spacer()
            Button {
                onboardingStep = 3
            } label: {
                Text("Continuar")
                    .font(.palatino(.body, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 0x53/255, green: 0xA3/255, blue: 0xFE/255),
                                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 56)
        }
    }

    /// Step 4 — tour final: perfil, widgets, modo vuelos.
    @ViewBuilder
    private func onboardingTourFinalStep() -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(Color(red: 0x53/255, green: 0xA3/255, blue: 0xFE/255))
                    Text("Y mucho más")
                        .font(.custom("Satoshi-Bold", size: 24))
                        .multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: 18) {
                    onboardingTourRow(
                        emoji: "📊",
                        title: "Perfil con stats",
                        body: "Logros, premios personales, transporte usado y resumen anual."
                    )
                    onboardingTourRow(
                        emoji: "✈️",
                        title: "Modo vuelos",
                        body: "Botón derecha del mapa: visualiza todas tus rutas en gran círculo."
                    )
                    onboardingTourRow(
                        emoji: "📱",
                        title: "Widgets",
                        body: "Pon Raskmap en tu pantalla principal o de bloqueo."
                    )
                }
                .padding(.horizontal, 32)
            }
            Spacer()
            Button {
                showOnboarding = false
                onboardingStep = 0
                didShowOnboarding = true
            } label: {
                Text("Empezar a explorar")
                    .font(.palatino(.body, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 0x53/255, green: 0xA3/255, blue: 0xFE/255),
                                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 56)
        }
    }

    @ViewBuilder
    private func onboardingTourRow(emoji: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(emoji).font(.system(size: 28)).frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.custom("Satoshi-Bold", size: 16))
                Text(body).font(.palatino(.subheadline)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func datePicker(for country: Country) -> some View {
        AddTripSheet(
            isoCode: country.isoCode,
            displayName: localizedName(for: country),
            flagEmoji: flagEmoji(for: country) ?? "🌐",
            features: features,
            isForFuture: true,
            onSave: { trip, _ in
                modelContext.insert(trip)
                country.status = .wantToVisit
                if country.plannedDate.map({ trip.dateFrom < $0 }) ?? true {
                    country.plannedDate = trip.dateFrom
                    country.plannedDateTo = trip.dateTo
                    country.transport = trip.transport
                    country.plannedTitle = trip.title
                }
                modelContext.saveOrWarn()
                highlightedIsoCode = nil
                Task { @MainActor in try? await Task.sleep(for: .seconds(0.4)); centerMap(on: country.isoCode) }
                if country.isoCode == locationIsoCode {
                    Task { @MainActor in try? await Task.sleep(for: .seconds(0.15)); recheckLocationIfNeeded() }
                }
            }
        )
    }

    @ViewBuilder
    private func flightModeButton() -> some View {
        VStack {
            if menuPositionIsTop { Spacer() }
            HStack {
                Button { showHelpToast = true } label: {
                    Image(systemName: "questionmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ayuda")
                .accessibilityHint("Información sobre cómo reportar bugs o sugerir contenido")
                .padding(.leading, 14)
                .padding(.top, menuPositionIsTop ? 0 : 60)
                .padding(.bottom, menuPositionIsTop ? 120 : 0)
                Spacer()
                Button {
                    triggerFlightModeTransition()
                } label: {
                    Image(systemName: flightMode ? "map.fill" : "airplane")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(flightTransitionTarget != nil)
                .accessibilityLabel(flightMode ? "Volver al mapa" : "Ver mapa de vuelos")
                .accessibilityHint(flightMode
                                   ? "Cambia al mapa de países visitados"
                                   : "Muestra las rutas aéreas de tus viajes")
                .padding(.trailing, 14)
                .padding(.top, menuPositionIsTop ? 0 : 60)
                .padding(.bottom, menuPositionIsTop ? 120 : 0)
            }
            if !menuPositionIsTop { Spacer() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func flightEmptyState() -> some View {
        let isPast = flightRouteFilter == .past
        let title = isPast ? "Aún no has volado" : "Sin vuelos próximos"
        let subtitle = isPast
            ? "Cuando añadas viajes con vuelos, sus rutas aparecerán aquí."
            : "Tus próximos vuelos dibujarán su ruta en este mapa."
        VStack(spacing: 14) {
            Image(systemName: "airplane.departure")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(BrandColor.accent.opacity(0.9))
            VStack(spacing: 6) {
                Text(title)
                    .font(.custom("Satoshi-Bold", size: 17))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.custom("Satoshi-Medium", size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }

    private func triggerFlightModeTransition() {
        guard flightTransitionTarget == nil else { return }
        let target = !flightMode
        // Haptic medium al alternar de modo.
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeIn(duration: 0.22)) { flightTransitionTarget = target }
        // Cambiar el modo bajo el overlay (invisible para el usuario).
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.32))
            flightMode = target
            // Al entrar en modo vuelos siempre arrancamos en "Visitados".
            if target { flightRouteFilter = .past }
        }
        // Retirar el overlay al final de la animación (~2s).
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.0))
            withAnimation(.easeOut(duration: 0.28)) { flightTransitionTarget = nil }
        }
    }

    /// Recalcula si hay rutas visibles para el filtro actual. Early-exit barato,
    /// pensado para llamarse en onChange sin impacto perceptible.
    private func recalculateFlightRouteAvailability() {
        let has = FlightRoutesBuilder.hasAnyRoute(in: trips, filter: flightRouteFilter)
        if flightModeHasRoutes != has {
            withAnimation(.easeInOut(duration: 0.25)) { flightModeHasRoutes = has }
        }
    }

    @ViewBuilder
    private func profileContent() -> some View {
        let visitedFlags: Set<String> = Set(
            countries.filter { $0.status == .visited || $0.status == .lived }
                .compactMap { country in features.first(where: { $0.isoCode == country.isoCode })?.flagEmoji }
        )
        ProfileSheet(
            username: $username, selectedPassport: $selectedPassport,
            countingModeRaw: $countingModeRaw, menuPositionRaw: $menuPositionRaw,
            showBucketList: $showBucketList,
            showCountdown: $showCountdown,
            onClearStatus: { status in
                for country in countries where country.status == status { country.status = .none; country.hasLived = false }
                modelContext.saveOrWarn()
            },
            onProximosTap: nil,
            onDiscoveryTap: { feature in
                // Cerramos el perfil y replicamos el efecto del tap-en-mapa:
                // centerMap + highlight + sheet del país. Pequeño delay para
                // dejar a SwiftUI completar la animación de dismiss del sheet.
                showProfile = false
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.4))
                    let country = countries.first(where: { $0.isoCode == feature.isoCode })
                        ?? Country(name: feature.localizedName, isoCode: feature.isoCode)
                    handleCountryTap(country)
                }
            },
            topTable: $topTable,
            visitedFlags: visitedFlags,
            allFeatures: features,
            visitedIsoCodes: Set(countries.filter { c in
                let isVisited = c.status == .visited || c.status == .lived
                let today = Calendar.current.startOfDay(for: Date())
                let hasPastTrip = trips.contains { $0.isoCode == c.isoCode && Calendar.current.startOfDay(for: $0.dateFrom) <= today }
                return isVisited && (c.visitCount > 0 || hasPastTrip)
            }.map { $0.isoCode }),
            countries: countries,
            trips: trips
        )
    }

    // MARK: - Lógica de negocio

    private func centerMap(on isoCode: String) {
        mapStore.centerOnCountry?(isoCode)
    }

    @State private var locationCheckTask: Task<Void, Never>? = nil

    private func checkLocationCountry(_ location: CLLocation, immediate: Bool = false) {
        locationCheckTask?.cancel()
        locationCheckTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 sec debounce
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                detectCountry(for: location)
            }
        }
    }

    private func detectCountry(for location: CLLocation) {
        let point = MKMapPoint(location.coordinate)
        // Find matching country via point-in-polygon. Solo actualiza el
        // highlight visual (`locationIsoCode`) — y SOLO si el país detectado
        // está marcado como `.visited`. Para cualquier otro estado (.none,
        // .wantToVisit, .bucketList, .lived) no se aplica el aro de
        // "estás aquí". La detección no muta nunca `Country.status`.
        for feature in features {
            guard feature.boundingMapRect.contains(point) else { continue }
            for polygon in feature.polygons {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.invalidatePath()
                if renderer.path?.contains(renderer.point(for: point)) == true {
                    let iso = feature.isoCode
                    let status = countries.first(where: { $0.isoCode == iso })?.status ?? .none
                    guard status == .visited else {
                        locationIsoCode = nil
                        return
                    }
                    // Force visual refresh: clear then set so RaskMapView re-applies isUserHere style
                    locationIsoCode = nil
                    DispatchQueue.main.async {
                        locationIsoCode = iso
                    }
                    return
                }
            }
        }
        locationIsoCode = nil
    }

    private func recheckLocationIfNeeded() {
        guard let location = locationManager.currentLocation else { return }
        // Re-detect solo para refrescar `locationIsoCode` (highlight visual).
        checkLocationCountry(location, immediate: true)
    }

    private func handleCountryTap(_ tapped: Country) {
        guard !isLoadingFeatures else { return }
        let isoCode = tapped.isoCode

        // Centrar el mapa en el país tapeado
        centerMap(on: isoCode)
        // Resaltar con borde negro
        highlightedIsoCode = isoCode

        // Caso normal: país ya en SwiftData (segunda apertura o ya visitado antes)
        if let existing = countries.first(where: { $0.isoCode == isoCode }) {
            selectedCountry = existing
            return
        }

        // Primera vez viendo este país: insertar + save + esperar a @Query
        modelContext.insert(tapped)
        modelContext.saveOrWarn()

        DispatchQueue.main.async {
            if let saved = self.countries.first(where: { $0.isoCode == isoCode }) {
                self.selectedCountry = saved
            }
        }
    }

    private func checkAndShowAchievementToasts() {
        let now = multiContAchievedNow
        if let prev = prevAchieved {
            let newlyUnlocked = now.subtracting(prev)
            if !newlyUnlocked.isEmpty {
                // Persistir logros de pasaporte recién ganados para que no se pierdan al añadir cuadrantes
                let newPassport = Set(newlyUnlocked.filter { $0.passportZoneKey != nil })
                if !newPassport.isEmpty { markPassportAchievementsEarned(newPassport) }
                // Solo usuarios Pro ven los toasts
                if isRaskmapPro {
                    let sorted = newlyUnlocked.sorted { $0.medalOrder < $1.medalOrder }
                    AchievementToastController.shared.show(sorted, menuPositionIsTop: menuPositionIsTop, isRaskmapPro: isRaskmapPro)
                }
            }
        }
        prevAchieved = now
    }

    // MARK: - Live Activity

    private var liveActivityKey: String {
        guard let b = nextProximosBanner else { return "" }
        return "\(b.isoCode)_\(b.days)"
    }

    private func startOrUpdateLiveActivity() {
        guard liveActivityEnabled && isRaskmapPro, let banner = nextProximosBanner else {
            stopLiveActivity(); return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let displayName = (banner.title?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? banner.name
        let state = RaskmapTripAttributes.ContentState(
            flagEmoji: banner.flag,
            tripName: displayName,
            daysRemaining: banner.days,
            transportEmoji: banner.transport ?? "✈️",
            tripStartDate: banner.dateFrom
        )
        let stale = Calendar.current.date(byAdding: .hour, value: 12, to: .now)
        let running = Activity<RaskmapTripAttributes>.activities
        if running.isEmpty {
            let content = ActivityContent(state: state, staleDate: stale)
            do {
                _ = try Activity.request(
                    attributes: RaskmapTripAttributes(),
                    content: content,
                    pushType: nil
                )
            } catch {
                print("Live Activity request failed: \(error)")
            }
        } else {
            Task {
                let content = ActivityContent(state: state, staleDate: stale)
                for activity in running {
                    await activity.update(content)
                }
            }
        }
    }

    private func stopLiveActivity() {
        Task {
            for activity in Activity<RaskmapTripAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func localizedName(for country: Country) -> String {
        features.first(where: { $0.isoCode == country.isoCode })?.localizedName ?? country.name
    }

    private func flagEmoji(for country: Country) -> String? {
        features.first(where: { $0.isoCode == country.isoCode })?.flagEmoji
    }

    private func removeFromTopTable(flagEmojis: Set<String>) {
        guard !flagEmojis.isEmpty,
              let data = topTable.data(using: .utf8),
              var dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        let keysToRemove = dict.keys.filter { flagEmojis.contains(dict[$0] ?? "") }
        for key in keysToRemove { dict.removeValue(forKey: key) }
        if let encoded = try? JSONEncoder().encode(dict) {
            topTable = String(data: encoded, encoding: .utf8) ?? "{}"
        }
    }

    /// Si un país está en `visited`/`lived` sin ningún trip ni visitCount (y no es la ubicación actual),
    /// lo reclasifica a `wantToVisit` (si tiene viaje futuro o plannedDate) o a `.none`.
    private func fixZeroXVisitedIfNeeded(country: Country) {
        guard country.isoCode != locationIsoCode else { return }
        guard country.status == .visited || country.status == .lived else { return }
        guard country.visitCount == 0 else { return }
        let today = Calendar.current.startOfDay(for: Date())
        let hasPastTrip = trips.contains { $0.isoCode == country.isoCode && Calendar.current.startOfDay(for: $0.dateFrom) <= today }
        guard !hasPastTrip else { return }
        let hasFutureTrip = trips.contains { $0.isoCode == country.isoCode && Calendar.current.startOfDay(for: $0.dateFrom) > today }
        if hasFutureTrip || country.plannedDate != nil {
            country.status = .wantToVisit
        } else {
            country.status = .none
            country.hasLived = false
        }
        modelContext.saveOrWarn()
    }

    @MainActor
    private func handleInitialTask() async {
        if features.isEmpty {
            GeoJSONLoader.loadCountriesAsync { loadedFeatures in
                self.features = loadedFeatures
                let existingCodes = Set(self.countries.map { $0.isoCode })
                for feature in loadedFeatures {
                    if !existingCodes.contains(feature.isoCode) {
                        let country = Country(name: feature.adminName, isoCode: feature.isoCode)
                        self.modelContext.insert(country)
                    }
                }
                self.isLoadingFeatures = false
                self.onContentReady?()
                if let loc = self.locationManager.currentLocation {
                    self.checkLocationCountry(loc, immediate: true)
                }
                WidgetDataWriter.syncFontFamily(self._appFontFamily)
                WidgetDataWriter.sync(countries: self.countries)
                WidgetDataWriter.syncCountingMode(self.countingMode.rawValue)
                WidgetDataWriter.syncPro(self.isRaskmapPro)
                let b = self.nextProximosBanner
                self.cachedNextBanner = b
                WidgetDataWriter.syncNextTrip(flag: b?.flag, days: b?.days, name: b?.name, transport: b?.transport, dateFrom: b?.dateFrom, bookingRef: b?.bookingRef, title: b?.title)
                WidgetDataWriter.syncAllFlags(self.allProximosFlagsString)
                WidgetDataWriter.syncTopVisitedFlags(self.topVisitedFlagsString)
                let af = self.nextFlightAirportsAny()
                WidgetDataWriter.syncNextFlightSnapshot(depIATA: af?.depIATA, arrIATA: af?.arrIATA, depCoord: af?.depCoord, arrCoord: af?.arrCoord)
                if self.liveActivityEnabled { self.startOrUpdateLiveActivity() }
            }
        } else {
            isLoadingFeatures = false
            onContentReady?()
            if let loc = locationManager.currentLocation {
                checkLocationCountry(loc, immediate: true)
            }
            WidgetDataWriter.syncFontFamily(_appFontFamily)
            WidgetDataWriter.syncPro(isRaskmapPro)
            if liveActivityEnabled { startOrUpdateLiveActivity() }
            cachedNextBanner = nextProximosBanner
            let af = nextFlightAirportsAny()
            WidgetDataWriter.syncNextFlightSnapshot(depIATA: af?.depIATA, arrIATA: af?.arrIATA, depCoord: af?.depCoord, arrCoord: af?.arrCoord)
        }
        // Onboarding: solo si NO se ha completado nunca antes (flag local).
        // Antes el check era `username.isEmpty`, lo que volvía a abrirlo si
        // CloudKit reseteaba el username (TestFlight reinstall, sign-out, etc).
        if !didShowOnboarding && username.isEmpty { showOnboarding = true }
        flightModeHasRoutes = FlightRoutesBuilder.hasAnyRoute(in: trips, filter: flightRouteFilter)
        locationManager.requestAndStart()
        autoMarkArrivedTripsAndPlans()
        cleanupZeroXVisitedStates()
        prevAchieved = multiContAchievedNow
    }

    private func autoMarkArrivedTripsAndPlans() {
        let today = Calendar.current.startOfDay(for: Date())
        var changed = false
        for trip in trips {
            let tripDay = Calendar.current.startOfDay(for: trip.dateFrom)
            guard tripDay <= today else { continue }
            guard let country = countries.first(where: { $0.isoCode == trip.isoCode }) else { continue }
            if country.status == .none {
                country.status = .visited; changed = true
            } else if country.status == .wantToVisit {
                country.status = .visited
                country.plannedDate = nil; country.plannedDateTo = nil
                country.transport = nil; country.plannedTitle = nil
                changed = true
            }
        }
        for country in countries {
            guard country.status == .wantToVisit,
                  let planned = country.plannedDate else { continue }
            let plannedDay = Calendar.current.startOfDay(for: planned)
            guard plannedDay <= today else { continue }
            let autoTrip = Trip(isoCode: country.isoCode,
                               title: country.plannedTitle,
                               dateFrom: country.plannedDate ?? planned,
                               dateTo: country.plannedDateTo,
                               transport: country.transport)
            modelContext.insert(autoTrip)
            country.status = .visited
            country.plannedDate = nil
            country.plannedDateTo = nil
            country.transport = nil
            country.plannedTitle = nil
            changed = true
        }
        if changed { modelContext.saveOrWarn() }
    }

    private func handleScenePhaseActive(_ phase: ScenePhase) {
        guard phase == .active else { return }
        if liveActivityEnabled { startOrUpdateLiveActivity() }
        autoMarkArrivedTripsAndPlans()
    }

    /// Limpia al arrancar todos los países visited/lived con 0x que no sean la ubicación actual.
    private func cleanupZeroXVisitedStates() {
        let today = Calendar.current.startOfDay(for: Date())
        var changed = false
        for country in countries {
            guard country.status == .visited || country.status == .lived else { continue }
            guard country.isoCode != locationIsoCode else { continue }
            guard country.visitCount == 0 else { continue }
            let hasPastTrip = trips.contains { $0.isoCode == country.isoCode && Calendar.current.startOfDay(for: $0.dateFrom) <= today }
            guard !hasPastTrip else { continue }
            let hasFutureTrip = trips.contains { $0.isoCode == country.isoCode && Calendar.current.startOfDay(for: $0.dateFrom) > today }
            if hasFutureTrip || country.plannedDate != nil {
                country.status = .wantToVisit
            } else {
                country.status = .none
                country.hasLived = false
            }
            changed = true
        }
        if changed { modelContext.saveOrWarn() }
    }

    private func updateCountryStatus(country: Country, newStatus: CountryStatus) {
        if newStatus == .wantToVisit {
            if country.status == .visited {
                // Visited + future trip: open AddTripSheet, keep status as visited
                pendingAddTripCountry = country
                statusBeforeVisit = .visited  // don't revert on cancel
            } else {
                pendingDateCountry = country
                pendingDateStatus = newStatus
            }
        } else {
            let previousStatus = country.status
            country.status = newStatus

            // Clean up planned dates when leaving wantToVisit
            if previousStatus == .wantToVisit && newStatus != .wantToVisit {
                country.plannedDate = nil
                country.plannedDateTo = nil
                country.transport = nil
            }
            // Remove from medallero when un-visiting
            if newStatus == .none && (previousStatus == .visited || previousStatus == .lived) {
                if let emoji = flagEmoji(for: country) {
                    removeFromTopTable(flagEmojis: Set([emoji]))
                }
            }
            // Diferenciamos dos intenciones distintas que comparten newStatus = .none:
            //  · "Eliminar de próximos" (previousStatus == .wantToVisit): el usuario
            //    quiere QUITAR el país de próximos, por lo que también hay que
            //    borrar TODOS los trips futuros de ese país (sin ellos no se
            //    revivirá el .wantToVisit).
            //  · "Desmarcar visitado/vivido": preservamos trips futuros y, si los
            //    hay, el país pasa a .wantToVisit.
            // Antes este bloque siempre conservaba los trips futuros, lo que
            // hacía que "eliminar de próximos" reanimara el país inmediatamente.
            if newStatus == .none {
                let today = Calendar.current.startOfDay(for: Date())
                var deletedIDs: Set<ObjectIdentifier> = []
                var hasFutureTrip = false
                let removingFromProximos = (previousStatus == .wantToVisit)

                for trip in trips where trip.isoCode == country.isoCode {
                    let tripDay = Calendar.current.startOfDay(for: trip.dateFrom)
                    let shouldDelete: Bool
                    if removingFromProximos {
                        // Purga total: no queremos que ningún trip futuro
                        // resurrecte el .wantToVisit más abajo.
                        shouldDelete = true
                    } else if tripDay <= today {
                        shouldDelete = true
                    } else {
                        shouldDelete = false
                        hasFutureTrip = true
                    }
                    guard shouldDelete else { continue }
                    // Borrar trip y, si pertenece a un grupo de segmentos, sus hermanos.
                    if let groupID = trip.segmentGroupID {
                        let desc = FetchDescriptor<Trip>(predicate: #Predicate { $0.segmentGroupID == groupID })
                        let siblings = modelContext.fetchOrWarn(desc, fallback: [trip])
                        for s in siblings {
                            guard deletedIDs.insert(ObjectIdentifier(s)).inserted else { continue }
                            modelContext.delete(s)
                        }
                    } else {
                        guard deletedIDs.insert(ObjectIdentifier(trip)).inserted else { continue }
                        modelContext.delete(trip)
                    }
                }

                if hasFutureTrip {
                    // Downgrade to wantToVisit — future trip stays, country colored accordingly
                    country.status = .wantToVisit
                    country.visitCount = 0
                } else {
                    country.plannedDate = nil
                    country.plannedDateTo = nil
                    country.transport = nil
                    country.plannedTitle = nil
                    country.visitCount = 0
                }
            }

            modelContext.saveOrWarn()
            refreshTrigger.toggle()  // force @Query refresh
            highlightedIsoCode = nil
            if newStatus == .visited {
                statusBeforeVisit = previousStatus
                lastModifiedCountry = country
                shouldOpenAddTrip = true
                // Momento delight: haptic success + ripple visual cuando un
                // país NUEVO se marca como visitado (no aplica si ya estaba
                // visitado y solo cambia de wantToVisit → visited, p.ej.).
                if previousStatus != .visited {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    rippleCountryIso = country.isoCode
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.9))
                        rippleCountryIso = nil
                    }
                }
            }
            if newStatus != .none {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.4))
                    centerMap(on: country.isoCode)
                }
            }
            if country.isoCode == locationIsoCode {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.2))
                    recheckLocationIfNeeded()
                }
            }
        }
    }
}
























#Preview {
    ContentView()
        .modelContainer(for: Country.self, inMemory: true)
}

// MARK: - Extensión de fuente (Satoshi)
//
// Helper para usar la fuente Satoshi con escalas semánticas + soporte
// Dynamic Type. La clave es `Font.custom(_:size:relativeTo:)`: al pasar
// un TextStyle como `relativeTo`, SwiftUI escala el tamaño base según
// la preferencia de "Larger Text" del usuario en Settings → Accessibility.
//
// Antes esta función devolvía `Font.custom(_:size:)` sin `relativeTo`,
// por lo que el texto NO escalaba — todos los `.font(.palatino(.body))`
// de la app quedaban fijos a 17pt aunque el usuario hubiera elegido
// "Larger Text". Cambio in-place: todos los call sites heredan el fix
// sin tocar nada más.
extension Font {
    static func palatino(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        let size: CGFloat
        switch style {
        case .largeTitle:  size = 34
        case .title:       size = 28
        case .title2:      size = 22
        case .title3:      size = 20
        case .headline:    size = 17
        case .body:        size = 17
        case .callout:     size = 16
        case .subheadline: size = 15
        case .footnote:    size = 13
        case .caption:     size = 12
        case .caption2:    size = 11
        @unknown default:  size = 17
        }
        switch weight {
        case .bold, .semibold: return .custom("Satoshi-Bold",    size: size, relativeTo: style)
        case .medium:          return .custom("Satoshi-Medium",  size: size, relativeTo: style)
        case .light:           return .custom("Satoshi-Light",   size: size, relativeTo: style)
        default:               return .custom("Satoshi-Regular", size: size, relativeTo: style)
        }
    }
}


// MARK: - Data models for airports and airlines

struct AirportData: Identifiable, Codable, Hashable {
    var id: String { iata }
    let iata: String
    let name: String
    let city: String
    let country: String  // ISO2

    var flagEmoji: String {
        country.uppercased().unicodeScalars.compactMap {
            Unicode.Scalar(127397 + $0.value).map { String($0) }
        }.joined()
    }
    var countryName: String {
        Locale(identifier: "es").localizedString(forRegionCode: country) ?? country
    }
}

struct AirlineData: Identifiable, Codable, Hashable {
    var id: String { iata }
    let iata: String
    let name: String
    let country: String
}

