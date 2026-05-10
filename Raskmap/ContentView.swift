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
            (letter: letter, features: grouped[letter]!.sorted { $0.localizedName.localizedCompare($1.localizedName) == .orderedAscending })
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
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
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
               let depCoord = AirportCoordinates.coordinate(for: aps.first!.iata),
               let arrCoord = AirportCoordinates.coordinate(for: aps.last!.iata) {
                return (aps.first!.iata, aps.last!.iata, depCoord, arrCoord)
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
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
                        .foregroundStyle(Color(red: 64/255, green: 114/255, blue: 212/255))
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
                            .background(Color(red: 64/255, green: 114/255, blue: 212/255), in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }
                .padding(28)
                .frame(maxWidth: 340)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
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
        if changed { try? modelContext.save() }
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    recheckLocationIfNeeded()
                }
                // Open AddTripSheet after country sheet fully dismissed
                if shouldOpenAddTrip, let lastCountry = lastModifiedCountry {
                    shouldOpenAddTrip = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
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
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
                            try? modelContext.save()
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
                            if locationIsoCode == country.isoCode {
                                autoMarkIfNeeded(isoCode: country.isoCode)
                            }
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
                        try? modelContext.save()
                    },
                    onSetDate: filter == .wantToVisit ? { country, trip in
                        if let trip = trip {
                            statusListFilter = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
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
                        try? modelContext.save()
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
                        try? modelContext.save()
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
                    try? modelContext.save()
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
                        try? modelContext.save()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { visitedToastMessages = [] }
                        }
                    },
                    onCancel: {
                        // Only revert if we changed the status (not for visited->addTrip)
                        if statusBeforeVisit != .visited {
                            country.status = statusBeforeVisit
                            try? modelContext.save()
                        } else {
                            fixZeroXVisitedIfNeeded(country: country)
                        }
                    }
                )
            }
            .onChange(of: statusListFilter) { _, newValue in
                if newValue == nil, let deferred = deferredDateCountry {
                    deferredDateCountry = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
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
            // - Anuncio: solo fuera de modo vuelo y si no es Pro.
            // - Contador: si toggle on y hay viaje próximo, se muestra TAMBIÉN
            //   en modo vuelo (el usuario lo pidió así).
            if !flightMode, !isRaskmapPro {
                // No Pro: mostrar anuncio
                VStack(spacing: 0) {
                    if menuPositionIsTop { Spacer() }
                    BannerAdView()
                        .frame(width: 320, height: 50)
                        .padding(.bottom, menuPositionIsTop ? 8 : 0)
                        .padding(.top, menuPositionIsTop ? 0 : 8)
                    if !menuPositionIsTop { Spacer() }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else if showCountdown, let banner = cachedNextBanner {
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
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .foregroundStyle(.white)
                        }.buttonStyle(.plain)
                    }
                    .padding(28)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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

    @ViewBuilder
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
                                        Text(trip.title?.isEmpty == false ? trip.title! : (feat?.localizedName ?? trip.isoCode))
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
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                if country.plannedDate == nil || trip.dateFrom < country.plannedDate! {
                    country.plannedDate = trip.dateFrom
                    country.plannedDateTo = trip.dateTo
                    country.transport = trip.transport
                    country.plannedTitle = trip.title
                }
                try? modelContext.save()
                highlightedIsoCode = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { centerMap(on: country.isoCode) }
                if country.isoCode == locationIsoCode {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { recheckLocationIfNeeded() }
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
                .foregroundStyle(Color(red: 64/255, green: 114/255, blue: 212/255).opacity(0.9))
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            flightMode = target
            // Al entrar en modo vuelos siempre arrancamos en "Visitados".
            if target { flightRouteFilter = .past }
        }
        // Retirar el overlay al final de la animación (~2s).
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
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
                try? modelContext.save()
            },
            onProximosTap: nil,
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
        // Find matching country via point-in-polygon
        for feature in features {
            guard feature.boundingMapRect.contains(point) else { continue }
            for polygon in feature.polygons {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.invalidatePath()
                if renderer.path?.contains(renderer.point(for: point)) == true {
                    let iso = feature.isoCode
                    autoMarkIfNeeded(isoCode: iso)
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
        // Re-detect from scratch to update visual and auto-mark
        checkLocationCountry(location, immediate: true)
    }

    private func autoMarkIfNeeded(isoCode: String) {
        guard let country = countries.first(where: { $0.isoCode == isoCode }) else { return }
        let today = Calendar.current.startOfDay(for: Date())
        // If visited and has future trip, no location action needed
        if country.status == .visited {
            let hasFutureTrip = trips.contains { $0.isoCode == isoCode && Calendar.current.startOfDay(for: $0.dateFrom) > today }
            if hasFutureTrip { return }
            return
        }
        var didMark = false
        switch country.status {
        case .none, .wantToVisit:
            country.status = .visited
            country.plannedDate = nil
            country.plannedDateTo = nil
            country.transport = nil
            try? modelContext.save()
            didMark = true
        case .bucketList:
            let hasFutureTrip = trips.contains { $0.isoCode == isoCode && Calendar.current.startOfDay(for: $0.dateFrom) > today }
            if hasFutureTrip {
                country.status = .wantToVisit
            } else {
                // Mark as visited without date or transport (user can edit later)
                country.status = .visited
            }
            country.plannedDate = nil
            country.plannedDateTo = nil
            country.transport = nil
            try? modelContext.save()
            didMark = true
        case .lived, .visited:
            break
        }
        // Show first-time location toast once after username is set
        if didMark && !didShowLocationToast && !username.isEmpty {
            didShowLocationToast = true
            withAnimation { showLocationToast = true }
        }
        // Fire achievement toasts for location-based auto-marks (no trip created, so trips.count won't change)
        if didMark { checkAndShowAchievementToasts() }
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
        try? modelContext.save()

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
        try? modelContext.save()
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
        if changed { try? modelContext.save() }
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
        if changed { try? modelContext.save() }
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
            // When unmarking visited: delete past trips, keep future trips
            if newStatus == .none {
                let today = Calendar.current.startOfDay(for: Date())
                var deletedIDs: Set<ObjectIdentifier> = []
                var hasFutureTrip = false

                for trip in trips where trip.isoCode == country.isoCode {
                    let tripDay = Calendar.current.startOfDay(for: trip.dateFrom)
                    if tripDay > today {
                        hasFutureTrip = true
                    } else {
                        // Delete past trip and any grouped siblings
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
                }

                if hasFutureTrip {
                    // Downgrade to wantToVisit — future trip stays, country colored accordingly
                    country.status = .wantToVisit
                    country.visitCount = 0
                } else {
                    country.plannedDate = nil
                    country.plannedDateTo = nil
                    country.transport = nil
                    country.visitCount = 0
                }
            }

            try? modelContext.save()
            refreshTrigger.toggle()  // force @Query refresh
            highlightedIsoCode = nil
            if newStatus == .visited {
                statusBeforeVisit = previousStatus
                lastModifiedCountry = country
                shouldOpenAddTrip = true
            }
            if newStatus != .none {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    centerMap(on: country.isoCode)
                }
            }
            if country.isoCode == locationIsoCode {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    recheckLocationIfNeeded()
                }
            }
        }
    }
}

// MARK: - Subvistas

struct StatBadge: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.custom("Satoshi-Bold", size: 20))
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(.custom("Satoshi-Regular", size: 9))
                .foregroundStyle(.secondary)
                .tracking(0.4)
        }
        .frame(minWidth: 70)
        .padding(.vertical, 9)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color.opacity(0.8))
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(color, lineWidth: 0.5))
            Text(label)
                .font(.custom("Satoshi-Regular", size: 10))
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
    }
}

// MARK: - Bottom Sheet país
struct CountryBottomSheet: View {
    let country: Country
    let displayName: String
    let flagEmoji: String?
    var isoA2: String? = nil
    let onStatusChange: (CountryStatus) -> Void
    let onDismiss: () -> Void
    var showBucketList: Bool = true
    var onAddPastTrip: (() -> Void)? = nil
    var onAddNextTrip: (() -> Void)? = nil
    var onEditTrips: (() -> Void)? = nil

    @EnvironmentObject private var colorTheme: ColorThemeManager
    @State private var showRemoveConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Hero header — la bandera arranca con un margen amplio para no quedar
            // pegada al drag indicator del sheet ni cortarse en pantallas estrechas.
            VStack(spacing: 12) {
                Group {
                    if let iso = isoA2, !iso.isEmpty {
                        TwemojiFlag(iso2: iso, size: 64, fallbackEmoji: flagEmoji ?? "🌐")
                    } else {
                        FlagLabel(emoji: flagEmoji ?? "🌐", size: 64)
                    }
                }
                .frame(width: 80, height: 80)
                Text(displayName)
                    .font(.palatino(.title2, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 24)
                if country.status != .none {
                    Text(country.status.label)
                        .font(.custom("Satoshi-Regular", size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Color(.systemGray5), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
            .padding(.bottom, 20)

            Divider()
                .padding(.horizontal, 24)

            VStack(spacing: 8) {
                let isVisited = country.status == .visited
                ActionButton(
                    label: isVisited ? "✅ Añadido a visitados" : "✅ Añadir a visitados",
                    color: colorTheme.visitedColor,
                    isSelected: isVisited,
                    action: {
                        if isVisited { showRemoveConfirm = true }
                        else { onStatusChange(.visited) }
                    }
                )
                if isVisited {
                    ActionButton(
                        label: "🗓 Añadir viaje pasado",
                        color: .secondary,
                        isSelected: false,
                        action: { onAddPastTrip?() }
                    )
                    ActionButton(
                        label: "🗺️ Ver viajes",
                        color: .secondary,
                        isSelected: false,
                        action: { onEditTrips?() }
                    )
                }
                if country.status != .lived {
                    let isProximo = country.status == .wantToVisit
                    ActionButton(
                        label: isProximo ? "🔜 Añadido a próximos" : "🔜 Añadir próximo viaje",
                        color: colorTheme.wantToVisitColor,
                        isSelected: isProximo,
                        action: {
                            if isProximo { showRemoveConfirm = true }
                            else { onAddNextTrip?() }
                        }
                    )
                }
                if showBucketList && (country.status == .none || country.status == .bucketList) {
                    let isBucket = country.status == .bucketList
                    ActionButton(
                        label: isBucket ? "📝 Añadido a quiero ir" : "📝 Añadir a quiero ir",
                        color: colorTheme.bucketListColor,
                        isSelected: isBucket,
                        action: {
                            if isBucket { showRemoveConfirm = true }
                            else { onStatusChange(.bucketList) }
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()
        }
        .alert("¿Eliminar de la lista?", isPresented: $showRemoveConfirm) {
            Button("Eliminar \(displayName)", role: .destructive) {
                onStatusChange(.none)
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("\(displayName) se eliminará de la lista.")
        }
    }
}

struct ActionButton: View {
    let label: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.palatino(.body, weight: .medium))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(color)
                        .font(.body)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .background(
                isSelected ? color.opacity(0.12) : Color(.systemGray6),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? color.opacity(0.35) : .clear, lineWidth: 1)
            )
            .foregroundStyle(isSelected ? color : .primary)
        }
    }
}

// MARK: - Sheet lista de países por estado
struct StatusListSheet: View {
    let filter: CountryStatus
    let countries: [Country]
    var proximoRows: [ProximoRow] = []
    let features: [CountryFeature]
    var trips: [Trip] = []
    let onRemove: (Country) -> Void
    var onSetDate: ((Country, Trip?) -> Void)? = nil
    var onRemoveProximo: ((ProximoRow) -> Void)? = nil
    var onDeleteAll: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var countryToRemove: Country? = nil
    @State private var rowToRemove: ProximoRow? = nil
    @State private var showDeleteAllConfirm = false

    private var filtered: [Country] {
        return countries.filter { $0.status == filter }
    }

    private var sortedProximoRows: [ProximoRow] {
        proximoRows.sorted {
            switch ($0.dateFrom, $1.dateFrom) {
            case let (a?, b?): return a < b
            case (_?, nil):    return true
            case (nil, _?):    return false
            default:           return displayName(for: $0.country) < displayName(for: $1.country)
            }
        }
    }

    private var groupedProximoRows: [(letter: String, items: [ProximoRow])] {
        var result: [(letter: String, items: [ProximoRow])] = []
        for row in sortedProximoRows {
            let key: String
            if let date = row.dateFrom {
                let df = DateFormatter()
                df.dateFormat = "MMMM yyyy"
                df.locale = Locale(identifier: "es_ES")
                key = df.string(from: date).capitalized
            } else {
                key = "Sin fecha"
            }
            if let idx = result.firstIndex(where: { $0.letter == key }) {
                result[idx].items.append(row)
            } else {
                result.append((letter: key, items: [row]))
            }
        }
        return result
    }

    private func displayName(for country: Country) -> String {
        features.first(where: { $0.isoCode == country.isoCode })?.localizedName ?? country.name
    }

    private func flagEmoji(for country: Country) -> String {
        features.first(where: { $0.isoCode == country.isoCode })?.flagEmoji ?? "🌐"
    }

    private func futureTrip(for country: Country) -> Trip? {
        let today = Calendar.current.startOfDay(for: Date())
        let iso = country.isoCode
        let future = trips.filter { t in
            t.isoCode == iso && Calendar.current.startOfDay(for: t.dateFrom) >= today
        }
        return future.min(by: { $0.dateFrom < $1.dateFrom })
    }

    private func proximoDateFrom(for country: Country) -> Date? {
        if country.status == .wantToVisit { return country.plannedDate }
        return futureTrip(for: country)?.dateFrom
    }

    private func proximoDateTo(for country: Country) -> Date? {
        if country.status == .wantToVisit { return country.plannedDateTo }
        return futureTrip(for: country)?.dateTo
    }

    private func proximoTransport(for country: Country) -> String? {
        if country.status == .wantToVisit { return country.transport }
        return futureTrip(for: country)?.transport
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var sortedFiltered: [Country] {
        filtered.sorted { displayName(for: $0) < displayName(for: $1) }
    }

    private var grouped: [(letter: String, items: [Country])] {
        var result: [(letter: String, items: [Country])] = []
        for country in sortedFiltered {
            let letter = String(displayName(for: country)
                .folding(options: .diacriticInsensitive, locale: .current)
                .prefix(1).uppercased())
            if let idx = result.firstIndex(where: { $0.letter == letter }) {
                result[idx].items.append(country)
            } else {
                result.append((letter: letter, items: [country]))
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                let isEmpty = filter == .wantToVisit ? proximoRows.isEmpty : filtered.isEmpty
                if isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Text("Ningún país marcado como")
                            .font(.palatino(.subheadline))
                            .foregroundStyle(.secondary)
                        Text(filter.label)
                            .font(.palatino(.title3, weight: .bold))
                        Spacer()
                    }
                } else if filter == .wantToVisit {
                    List {
                        ForEach(groupedProximoRows, id: \.letter) { section in
                            Section(header: Text(section.letter).font(.palatino(.caption, weight: .bold))) {
                                ForEach(section.items) { row in
                                    HStack {
                                        FlagLabel(emoji: flagEmoji(for: row.country), size: 22)
                                        VStack(alignment: .leading, spacing: 2) {
                                            if let title = row.rowTitle, !title.isEmpty {
                                                HStack(spacing: 6) {
                                                    Text(title).font(.palatino(.body, weight: .bold))
                                                    Text("|").foregroundStyle(.secondary)
                                                    Text(displayName(for: row.country)).font(.palatino(.body)).foregroundStyle(.secondary)
                                                }
                                            } else {
                                                Text(displayName(for: row.country)).font(.palatino(.body))
                                            }
                                            HStack(spacing: 4) {
                                                if let t = row.transport { Text(t).font(.caption) }
                                                if let from = row.dateFrom {
                                                    Text(Self.dateFormatter.string(from: from))
                                                        .font(.palatino(.caption)).foregroundStyle(.secondary)
                                                    if let to = row.dateTo {
                                                        Text("→ \(Self.dateFormatter.string(from: to))")
                                                            .font(.palatino(.caption)).foregroundStyle(.secondary)
                                                    }
                                                    let today = Calendar.current.startOfDay(for: Date())
                                                    let d = Calendar.current.startOfDay(for: from)
                                                    let days = Calendar.current.dateComponents([.day], from: today, to: d).day ?? 0
                                                    if days >= 0 {
                                                        Text("\(days)d")
                                                            .font(.palatino(.caption, weight: .bold))
                                                            .foregroundStyle(.blue)
                                                    }
                                                }
                                            }
                                        }
                                        Spacer()
                                        if let onSetDate {
                                            Button {
                                                onSetDate(row.country, row.trip)
                                            } label: {
                                                Image(systemName: "calendar")
                                                    .foregroundStyle(.blue)
                                                    .font(.body)
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.trailing, 8)
                                        }
                                        Button {
                                            rowToRemove = row
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.red)
                                                .font(.title3)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                } else {
                    List {
                        ForEach(grouped, id: \.letter) { section in
                            Section(header: Text(section.letter).font(.palatino(.caption, weight: .bold))) {
                                ForEach(section.items, id: \.isoCode) { country in
                                    HStack {
                                        FlagLabel(emoji: flagEmoji(for: country), size: 22)
                                        Text(displayName(for: country)).font(.palatino(.body))
                                        Spacer()
                                        Button {
                                            countryToRemove = country
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.red)
                                                .font(.title3)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(filter.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }.font(.palatino(.body))
                }
                let listNotEmpty = filter == .wantToVisit ? !proximoRows.isEmpty : !filtered.isEmpty
                if listNotEmpty, onDeleteAll != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showDeleteAllConfirm = true } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .alert("Borrar lista completa", isPresented: $showDeleteAllConfirm) {
            Button("Borrar todo", role: .destructive) {
                onDeleteAll?()
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se eliminarán todas las entradas de esta lista. Esta acción no se puede deshacer.")
        }
        .alert("¿Eliminar de la lista?", isPresented: Binding(
            get: { countryToRemove != nil },
            set: { if !$0 { countryToRemove = nil } }
        )) {
            if let c = countryToRemove {
                Button("Eliminar \(displayName(for: c))", role: .destructive) {
                    onRemove(c)
                    countryToRemove = nil
                }
                Button("Cancelar", role: .cancel) {
                    countryToRemove = nil
                }
            }
        } message: {
            if let c = countryToRemove {
                Text("\(displayName(for: c)) se eliminará de la lista.")
            }
        }
        .alert("¿Eliminar este próximo?", isPresented: Binding(
            get: { rowToRemove != nil },
            set: { if !$0 { rowToRemove = nil } }
        )) {
            if let row = rowToRemove {
                Button("Eliminar", role: .destructive) {
                    onRemoveProximo?(row)
                    rowToRemove = nil
                }
                Button("Cancelar", role: .cancel) {
                    rowToRemove = nil
                }
            }
        } message: {
            if let row = rowToRemove {
                Text("\(displayName(for: row.country)) se eliminará de próximos.")
            }
        }
    }
}

// MARK: - Sheet lista de viajes FINALIZADOS de un año
// Refleja el look & feel del branch .wantToVisit de StatusListSheet, pero con
// filas agrupadas por mes del `dateFrom` pasado y sin botón de calendario.
struct FinalizadosListSheet: View {
    let year: Int
    let rows: [ProximoRow]
    let features: [CountryFeature]
    let onRemove: (ProximoRow) -> Void
    var onDuplicate: ((ProximoRow) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var rowToRemove: ProximoRow? = nil
    @State private var rowToShow: ProximoRow? = nil
    @State private var rowToDuplicate: ProximoRow? = nil
    @State private var transportFilter: String? = nil   // emoji, nil = todos

    /// Aplica el filtro de transporte sobre las filas. Compara con
    /// `row.transport` y, si el row tiene `trip.tripSegments`, también con
    /// los transports de los segments (un viaje multi-modal con un ✈️ filtra
    /// para "✈️").
    private func passesTransportFilter(_ row: ProximoRow) -> Bool {
        guard let f = transportFilter else { return true }
        if let t = row.transport, normalizeWalkEmoji(t) == normalizeWalkEmoji(f) { return true }
        let segs = row.trip?.tripSegments ?? []
        return segs.contains { normalizeWalkEmoji($0.transport) == normalizeWalkEmoji(f) }
    }
    private func normalizeWalkEmoji(_ e: String) -> String {
        e == "🚶" ? "🚶🏻" : e
    }

    private func displayName(for country: Country) -> String {
        features.first(where: { $0.isoCode == country.isoCode })?.localizedName ?? country.name
    }
    private func flagEmoji(for country: Country) -> String {
        features.first(where: { $0.isoCode == country.isoCode })?.flagEmoji ?? "🌐"
    }
    /// ISO-3166-1 alpha-2 code used by Twemoji asset lookup.
    private func isoA2(for country: Country) -> String {
        features.first(where: { $0.isoCode == country.isoCode })?.isoA2 ?? ""
    }
    private func displayName(for iso: String) -> String {
        features.first(where: { $0.isoCode == iso })?.localizedName ?? iso
    }
    private func flagEmoji(for iso: String) -> String {
        features.first(where: { $0.isoCode == iso })?.flagEmoji ?? "🌐"
    }
    private func isoA2(for iso: String) -> String {
        features.first(where: { $0.isoCode == iso })?.isoA2 ?? ""
    }
    @ViewBuilder
    private func filterChip(emoji: String?, label: String) -> some View {
        let active = transportFilter == emoji
        Button { transportFilter = emoji } label: {
            Text(label)
                .font(.custom("Satoshi-Bold", size: 13))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(active ? Color(red: 64/255, green: 114/255, blue: 212/255) : Color(.systemGray5),
                            in: Capsule())
                .foregroundStyle(active ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    /// País del trip donde se han pasado más días. Empate → primero alfabético.
    private func mainCountryIso(for row: ProximoRow) -> String {
        guard let trip = row.trip else { return row.country.isoCode }
        let days = daysPerCountry(trips: [trip])
        guard let maxDays = days.values.max(), maxDays > 0 else { return row.country.isoCode }
        let tied = days.filter { $0.value == maxDays }.keys.sorted()
        return tied.first ?? row.country.isoCode
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()

    private var sorted: [ProximoRow] {
        rows.filter(passesTransportFilter).sorted {
            let a = $0.dateFrom ?? .distantPast
            let b = $1.dateFrom ?? .distantPast
            return a < b
        }
    }

    private var grouped: [(label: String, items: [ProximoRow])] {
        var result: [(label: String, items: [ProximoRow])] = []
        for row in sorted {
            let key: String
            if let date = row.dateFrom {
                let df = DateFormatter()
                df.dateFormat = "MMMM yyyy"
                df.locale = Locale(identifier: "es_ES")
                key = df.string(from: date).capitalized
            } else {
                key = "Sin fecha"
            }
            if let idx = result.firstIndex(where: { $0.label == key }) {
                result[idx].items.append(row)
            } else {
                result.append((label: key, items: [row]))
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filtros de transporte — chips horizontales scrollables.
                // Se calculan los transports presentes en los rows del año
                // (no la lista fija de 6) para no mostrar opciones vacías.
                let availableTransports: [String] = {
                    var seen = Set<String>()
                    var result: [String] = []
                    for r in rows {
                        if let t = r.transport, seen.insert(normalizeWalkEmoji(t)).inserted {
                            result.append(normalizeWalkEmoji(t))
                        }
                        for s in r.trip?.tripSegments ?? [] {
                            if seen.insert(normalizeWalkEmoji(s.transport)).inserted {
                                result.append(normalizeWalkEmoji(s.transport))
                            }
                        }
                    }
                    return result
                }()
                if availableTransports.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filterChip(emoji: nil, label: "Todos")
                            ForEach(availableTransports, id: \.self) { emoji in
                                filterChip(emoji: emoji, label: emoji)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                    }
                    Divider()
                }
            Group {
                if rows.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Text("Sin viajes finalizados").font(.palatino(.subheadline)).foregroundStyle(.secondary)
                        Text(String(year)).font(.palatino(.title3, weight: .bold))
                        Spacer()
                    }
                } else if sorted.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Text("Sin resultados con este filtro").font(.palatino(.subheadline)).foregroundStyle(.secondary)
                        Button("Quitar filtro") { transportFilter = nil }
                            .font(.palatino(.body, weight: .bold))
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(grouped, id: \.label) { section in
                            Section(header: Text(section.label).font(.palatino(.caption, weight: .bold))) {
                                ForEach(section.items) { row in
                                    let mainIso = mainCountryIso(for: row)
                                    HStack {
                                        TwemojiFlag(
                                            iso2: isoA2(for: mainIso),
                                            size: 22,
                                            fallbackEmoji: flagEmoji(for: mainIso)
                                        )
                                        VStack(alignment: .leading, spacing: 2) {
                                            if let title = row.rowTitle, !title.isEmpty {
                                                HStack(spacing: 6) {
                                                    Text(title).font(.palatino(.body, weight: .bold))
                                                    Text("|").foregroundStyle(.secondary)
                                                    Text(displayName(for: mainIso)).font(.palatino(.body)).foregroundStyle(.secondary)
                                                }
                                            } else {
                                                Text(displayName(for: mainIso)).font(.palatino(.body))
                                            }
                                            HStack(spacing: 4) {
                                                if let t = row.transport { Text(t).font(.caption) }
                                                if let from = row.dateFrom {
                                                    Text(Self.dateFormatter.string(from: from))
                                                        .font(.palatino(.caption)).foregroundStyle(.secondary)
                                                    if let to = row.dateTo {
                                                        Text("→ \(Self.dateFormatter.string(from: to))")
                                                            .font(.palatino(.caption)).foregroundStyle(.secondary)
                                                    }
                                                }
                                            }
                                        }
                                        Spacer()
                                        // Chevron: indica que la fila es tappable para ver el detalle.
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                        Button {
                                            rowToRemove = row
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.red)
                                                .font(.title3)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 2)
                                    .contentShape(Rectangle())
                                    .onTapGesture { rowToShow = row }
                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                        if onDuplicate != nil {
                                            Button {
                                                rowToDuplicate = row
                                            } label: {
                                                Label("Duplicar", systemImage: "plus.square.on.square")
                                            }
                                            .tint(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            } // end VStack
            .navigationTitle("Finalizados \(String(year))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .confirmationDialog("¿Eliminar este viaje?",
                            isPresented: Binding(get: { rowToRemove != nil },
                                                 set: { if !$0 { rowToRemove = nil } }),
                            titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) {
                if let row = rowToRemove { onRemove(row) }
                rowToRemove = nil
            }
            Button("Cancelar", role: .cancel) { rowToRemove = nil }
        } message: {
            if let row = rowToRemove {
                Text("Se borrará el viaje a \(displayName(for: mainCountryIso(for: row))) (y sus tramos asociados).")
            }
        }
        // Detalle del viaje: al tocar una fila se abre esta hoja mostrando
        // todos los tramos (países + transportes) del trip seleccionado.
        .sheet(item: $rowToShow) { row in
            FinalizadoTripDetailSheet(row: row, features: features)
        }
        .confirmationDialog(
            "¿Duplicar este viaje a futuro?",
            isPresented: Binding(
                get: { rowToDuplicate != nil },
                set: { if !$0 { rowToDuplicate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Duplicar a +1 año") {
                if let row = rowToDuplicate { onDuplicate?(row) }
                rowToDuplicate = nil
            }
            Button("Cancelar", role: .cancel) { rowToDuplicate = nil }
        } message: {
            if let row = rowToDuplicate {
                Text("Se creará una copia de \(displayName(for: mainCountryIso(for: row))) con las mismas fechas pero +365 días en el futuro. Podrás editarla luego.")
            }
        }
        .appColorScheme()
    }
}

// MARK: - Sheet de detalle de un viaje FINALIZADO
// Muestra título, bandera principal, rango de fechas y — si el trip tiene
// tramos — todos ellos en orden cronológico con su bandera(s), nombre(s) de
// país, transporte y fecha. Si el trip no tiene segmentos, renderiza una
// única fila con los datos básicos del ProximoRow.
struct FinalizadoTripDetailSheet: View {
    let row: ProximoRow
    let features: [CountryFeature]

    @Environment(\.dismiss) private var dismiss

    /// `daysPerCountry` es O(días * segmentos) y se llamaba en cada render
    /// del scroll (FPS drops con muchos países). Cacheamos por `tripID` y solo
    /// recomputamos en `.onAppear` o si cambia el row.
    @State private var cachedDays: [(iso: String, days: Int)] = []
    @State private var cachedTripFingerprint: String = ""

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = Locale(identifier: "es_ES")
        return f
    }()

    /// Lookup O(1) por iso. Si `features` cambia por viewBuilder, se rebuilda.
    private var byIso: [String: CountryFeature] {
        Dictionary(uniqueKeysWithValues: features.map { ($0.isoCode, $0) })
    }
    private func displayName(for iso: String) -> String { byIso[iso]?.localizedName ?? iso }
    private func isoA2(for iso: String) -> String { byIso[iso]?.isoA2 ?? "" }
    private func flagEmoji(for iso: String) -> String { byIso[iso]?.flagEmoji ?? "🌐" }

    /// Segmentos del trip en orden cronológico. Vacío si el trip no tiene
    /// segmentos embebidos (viaje simple de un único país + transporte).
    private var segments: [TripSegment] {
        (row.trip?.tripSegments ?? []).sorted { $0.dateFrom < $1.dateFrom }
    }

    /// Fingerprint que detecta cambios en el trip (fechas, segs) para
    /// invalidar el cache de días.
    private var tripFingerprint: String {
        guard let t = row.trip else {
            return "c|\(row.country.isoCode)|\(row.dateFrom?.timeIntervalSince1970 ?? 0)|\(row.dateTo?.timeIntervalSince1970 ?? 0)"
        }
        let segPart = segments.map {
            "\($0.dateFrom.timeIntervalSince1970)-\($0.dateTo?.timeIntervalSince1970 ?? 0)-\($0.transport)-\($0.isoCodes.sorted().joined(separator: ","))"
        }.joined(separator: ";")
        return "t|\(t.isoCode)|\(t.dateFrom.timeIntervalSince1970)|\(t.dateTo?.timeIntervalSince1970 ?? 0)|\(segPart)"
    }

    private var daysByCountry: [(iso: String, days: Int)] {
        cachedDays
    }

    private func recomputeDays() {
        let fp = tripFingerprint
        guard fp != cachedTripFingerprint else { return }
        cachedTripFingerprint = fp
        guard let trip = row.trip else {
            let from = row.dateFrom ?? Date()
            let to = row.dateTo ?? from
            let cnt = max(1, (Calendar.current.dateComponents([.day], from: from, to: to).day ?? 0) + 1)
            cachedDays = [(row.country.isoCode, cnt)]
            return
        }
        let map = daysPerCountry(trips: [trip])
        cachedDays = map.map { (iso: $0.key, days: $0.value) }.sorted {
            if $0.days != $1.days { return $0.days > $1.days }
            return $0.iso < $1.iso
        }
    }

    private var headerTitle: String {
        if let t = row.rowTitle, !t.isEmpty { return t }
        return displayName(for: row.country.isoCode)
    }

    private var dateRangeText: String? {
        guard let from = row.dateFrom else { return nil }
        let s = Self.dateFormatter.string(from: from)
        if let to = row.dateTo, to != from {
            return "\(s) → \(Self.dateFormatter.string(from: to))"
        }
        return s
    }

    /// Devuelve la ruta aeroportuaria (ida / vuelta si existe) para un segment ✈️.
    /// Nil si no aplica (no es vuelo o no hay aeropuertos).
    private func airportRoute(for seg: TripSegment) -> String? {
        guard seg.transport == "✈️", let aps = seg.airports, !aps.isEmpty else { return nil }
        var route = aps.map { $0.iata }.joined(separator: " → ")
        if let ret = seg.returnAirports, !ret.isEmpty {
            route += "  /  " + ret.map { $0.iata }.joined(separator: " → ")
        }
        return route
    }

    /// Ruta aeroportuaria para trips legacy sin segmentos (✈️ guardado como
    /// `trip.tripAirports` con counts 2x para round-trip directo). Si no hay
    /// aeropuertos suficientes devolvemos nil.
    private func legacyAirportRoute(for trip: Trip) -> String? {
        guard trip.transport == "✈️" else { return nil }
        let aps = trip.tripAirports
        guard aps.count >= 2 else { return nil }
        let iatas = aps.map(\.iata)
        let totalCount = aps.reduce(0) { $0 + $1.count }
        // Heurística: si todos los counts son ≥2 (round-trip directo o con
        // escalas ida+vuelta), reconstruimos ida + vuelta invertida. Para
        // round-trip directo MAD-ARN guardado como [MAD(2), ARN(2)] →
        // "MAD → ARN  /  ARN → MAD".
        let isLikelyRoundTrip = aps.count >= 2 && aps.allSatisfy { $0.count >= 2 } &&
                                totalCount >= aps.count * 2
        let outbound = iatas.joined(separator: " → ")
        if isLikelyRoundTrip {
            return outbound + "  /  " + iatas.reversed().joined(separator: " → ")
        }
        return outbound
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // MARK: Cabecera
                    HStack(spacing: 14) {
                        TwemojiFlag(
                            iso2: isoA2(for: row.country.isoCode),
                            size: 44,
                            fallbackEmoji: flagEmoji(for: row.country.isoCode)
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(headerTitle)
                                .font(.palatino(.title3, weight: .bold))
                                .lineLimit(2)
                            if let title = row.rowTitle, !title.isEmpty {
                                // Si el título no es el nombre del país, mostramos el país debajo.
                                Text(displayName(for: row.country.isoCode))
                                    .font(.palatino(.subheadline))
                                    .foregroundStyle(.secondary)
                            }
                            if let dr = dateRangeText {
                                Text(dr)
                                    .font(.palatino(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    Divider().padding(.horizontal, 20)

                    // MARK: Tramos
                    VStack(alignment: .leading, spacing: 10) {
                        Text(segments.isEmpty ? "VIAJE" : "TRAMOS DEL VIAJE")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1.0)
                            .padding(.horizontal, 20)

                        if segments.isEmpty {
                            // Fallback: trip sin segmentos — una única fila con
                            // la info básica del ProximoRow. Si es ✈️ y guarda
                            // aeropuertos legacy reconstruimos ruta para que
                            // siempre se muestre (bug "no aparece la ruta en
                            // un vuelo de ida y vuelta directo").
                            FinalizadoSegmentRow(
                                transport: row.transport ?? "🌍",
                                isos: [row.country.isoCode],
                                dateFrom: row.dateFrom ?? Date(),
                                dateTo: row.dateTo,
                                airportRoute: row.trip.flatMap(legacyAirportRoute(for:)),
                                displayName: displayName,
                                isoA2: isoA2,
                                flagEmoji: flagEmoji
                            )
                        } else {
                            VStack(spacing: 10) {
                                ForEach(segments) { seg in
                                    FinalizadoSegmentRow(
                                        transport: seg.transport,
                                        isos: seg.isoCodes,
                                        dateFrom: seg.dateFrom,
                                        dateTo: seg.dateTo,
                                        airportRoute: airportRoute(for: seg),
                                        displayName: displayName,
                                        isoA2: isoA2,
                                        flagEmoji: flagEmoji
                                    )
                                }
                            }
                        }
                    }

                    // MARK: Días por país
                    if !daysByCountry.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("DÍAS POR PAÍS")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .tracking(1.0)
                                .padding(.horizontal, 20)
                            VStack(spacing: 0) {
                                ForEach(Array(daysByCountry.enumerated()), id: \.offset) { idx, entry in
                                    HStack(spacing: 10) {
                                        TwemojiFlag(
                                            iso2: isoA2(for: entry.iso),
                                            size: 18,
                                            fallbackEmoji: flagEmoji(for: entry.iso)
                                        )
                                        Text(displayName(for: entry.iso))
                                            .font(.palatino(.body))
                                        Spacer()
                                        Text(entry.days == 1 ? "1 día" : "\(entry.days) días")
                                            .font(.palatino(.body, weight: .bold))
                                            .foregroundStyle(.primary)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 12)
                                    if idx < daysByCountry.count - 1 {
                                        Rectangle().fill(Color(.systemGray5)).frame(height: 0.5)
                                            .padding(.leading, 16)
                                    }
                                }
                            }
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 20)
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(.top, 8)
            }
            .navigationTitle("Detalle del viaje")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        shareTrip()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.body)
                    }
                    .accessibilityLabel("Compartir viaje")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { recomputeDays() }
        .appColorScheme()
    }

    /// Compone un texto compartible con título + rango de fechas + países +
    /// días por país. Lo lanza por UIActivityViewController para que el
    /// usuario lo mande por Mensajes, WhatsApp, Mail, etc.
    private func shareTrip() {
        let lines: [String] = {
            var parts: [String] = []
            parts.append("✈️ \(headerTitle)")
            if let r = dateRangeText { parts.append(r) }
            if !daysByCountry.isEmpty {
                parts.append("")
                parts.append("Días por país:")
                for entry in daysByCountry {
                    let flag = flagEmoji(for: entry.iso)
                    let name = displayName(for: entry.iso)
                    parts.append("\(flag) \(name) — \(entry.days) \(entry.days == 1 ? "día" : "días")")
                }
            }
            parts.append("")
            parts.append("Compartido desde Raskmap 🗺️")
            return parts
        }()
        let text = lines.joined(separator: "\n")
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let key = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else { return }
        var top = key.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        top?.present(av, animated: true)
    }
}

// MARK: - Fila de un tramo dentro de FinalizadoTripDetailSheet
//
// Renderiza: icono de transporte (ZStack circular), banderas Twemoji de los
// países involucrados (una por cada iso en `isos`), nombres de país, ruta
// aeroportuaria opcional (✈️) y fechas. Diseño alineado con el look&feel de
// las filas de tramos en EditTripSheet (línea ~8607) pero read-only.
private struct FinalizadoSegmentRow: View {
    let transport: String
    let isos: [String]
    let dateFrom: Date
    let dateTo: Date?
    let airportRoute: String?
    let displayName: (String) -> String
    let isoA2: (String) -> String
    let flagEmoji: (String) -> String

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = Locale(identifier: "es_ES")
        return f
    }()

    private var countryNames: String {
        isos.map(displayName).joined(separator: " · ")
    }

    private var dateText: String {
        let s = Self.fmt.string(from: dateFrom)
        if let to = dateTo, to != dateFrom {
            return "\(s) → \(Self.fmt.string(from: to))"
        }
        return s
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icono del transporte
            ZStack {
                Circle().fill(Color(.systemGray5)).frame(width: 40, height: 40)
                Text(transport).font(.system(size: 18))
            }
            VStack(alignment: .leading, spacing: 6) {
                // Banderas + nombres de país
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        ForEach(Array(isos.enumerated()), id: \.offset) { _, iso in
                            TwemojiFlag(
                                iso2: isoA2(iso),
                                size: 18,
                                fallbackEmoji: flagEmoji(iso)
                            )
                        }
                    }
                    Text(countryNames)
                        .font(.palatino(.body))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Ruta aeroportuaria (sólo ✈️ con aeropuertos)
                if let route = airportRoute {
                    Text(route)
                        .font(.custom("Satoshi-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
                // Fechas
                Text(dateText)
                    .font(.custom("Satoshi-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }
}

// MARK: - Avatar pequeño para el header
struct PassportAvatarView: View {
    let key: String
    let height: CGFloat

    // Proporciones reales de las imágenes de pasaporte (≈ 822×1091 px).
    static let aspect: CGFloat = 822.0 / 1091.0

    var body: some View {
        let width = height * Self.aspect
        let corner = height * 0.08
        Image(key)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
    }
}

enum PassportOption: String, CaseIterable, Identifiable {
    case one   = "PASSPORT"
    case two   = "PASSPORT 2"
    case three = "PASSPORT 3"
    case four  = "PASSPORT 4"
    var id: String { rawValue }
}

struct PassportPickerSheet: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    Text("Elige tu pasaporte")
                        .font(.custom("Satoshi-Bold", size: 20))
                        .padding(.top, 4)
                    Text("Será tu avatar en la app.")
                        .font(.palatino(.footnote))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 6)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16),
                                    GridItem(.flexible(), spacing: 16)],
                          spacing: 16) {
                    ForEach(PassportOption.allCases) { opt in
                        PassportSelectableCard(key: opt.rawValue,
                                               isSelected: selection == opt.rawValue)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    selection = opt.rawValue
                                }
                            }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Listo") { dismiss() }.font(.palatino(.body, weight: .bold))
                }
            }
        }
        .appColorScheme()
    }
}

private struct PassportSelectableCard: View {
    let key: String
    let isSelected: Bool

    var body: some View {
        VStack {
            PassportAvatarView(key: key, height: 200)
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 26))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(6)
                    }
                }
                .scaleEffect(isSelected ? 1.03 : 1.0)
                .shadow(color: isSelected ? Color.accentColor.opacity(0.55) : .black.opacity(0.18),
                        radius: isSelected ? 12 : 5, y: 3)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Segmented slider (modo vuelo)
/// Segmented control con dos opciones (Visitados / Próximos).
/// Antes usaba `.glassEffect` de iOS 26, pero el blur del thumb ocultaba el
/// texto debajo. Ahora el thumb es una cápsula TRANSPARENTE con un borde
/// blanco suave y un degradado sutil — permite leer la palabra seleccionada
/// perfectamente y sigue viéndose atractivo.
struct FlightFilterSlider: View {
    @Binding var selection: FlightRouteFilter
    @GestureState private var dragDelta: CGFloat = 0
    @GestureState private var isPressing: Bool = false

    private let segments: [(FlightRouteFilter, String, String)] = [
        (.past,     "Finalizados", "checkmark.seal.fill"),
        (.upcoming, "Próximos",    "airplane.departure")
    ]

    private func index(_ f: FlightRouteFilter) -> Int {
        segments.firstIndex(where: { $0.0 == f }) ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let segW = geo.size.width / CGFloat(segments.count)
            let h = geo.size.height
            let baseX = segW * CGFloat(index(selection))
            let rawX = baseX + dragDelta
            let clampedX = max(0, min(geo.size.width - segW, rawX))
            let pressScale: CGFloat = isPressing ? 1.06 : 1.0

            ZStack(alignment: .leading) {
                // Thumb debajo del texto para no taparlo — cápsula transparente
                // con un gradiente sutil y borde blanco suave.
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.55), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.18), radius: 6, y: 2)
                    .frame(width: segW - 4, height: h - 4)
                    .scaleEffect(pressScale)
                    // ZStack(alignment: .leading) ya centra verticalmente,
                    // así que SOLO aplicamos offset horizontal (el +2 es el
                    // margen simétrico entre thumb y borde de la cápsula
                    // exterior). Antes tenía también y:2 que empujaba el
                    // thumb 2pt por debajo del centro y chocaba con el borde.
                    .offset(x: clampedX + 2)
                    .animation(.smooth(duration: 0.32), value: selection)
                    .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.85), value: isPressing)
                    .allowsHitTesting(false)

                // Textos con icono (arriba del thumb). Cada chip ocupa su slot.
                HStack(spacing: 0) {
                    ForEach(segments, id: \.0) { seg in
                        HStack(spacing: 6) {
                            Image(systemName: seg.2)
                                .font(.system(size: 12, weight: .semibold))
                            Text(seg.1)
                                .font(.custom("Satoshi-Bold", size: 13))
                        }
                        .foregroundStyle(selection == seg.0 ? Color.white : Color.white.opacity(0.55))
                        .frame(width: segW, height: h)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard selection != seg.0 else { return }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.smooth(duration: 0.32)) { selection = seg.0 }
                        }
                        .accessibilityAddTraits(selection == seg.0 ? [.isSelected, .isButton] : .isButton)
                        .accessibilityLabel("Filtro vuelos: \(seg.1)")
                    }
                }

            }
            // Drag simultáneo al tap — arrastrar el thumb actualiza selection.
            // Se aplica al ZStack entero para no bloquear los onTapGesture de
            // cada chip. minimumDistance > 0 evita conflicto con los taps.
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .updating($isPressing) { _, state, _ in state = true }
                    .updating($dragDelta) { value, state, _ in
                        state = value.translation.width
                    }
                    .onEnded { value in
                        let finalX = baseX + value.translation.width
                        let idx = Int((finalX + segW / 2) / segW)
                        let clamped = max(0, min(segments.count - 1, idx))
                        let newSel = segments[clamped].0
                        if newSel != selection {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                        withAnimation(.smooth(duration: 0.35)) { selection = newSel }
                    }
            )
            .background(
                // Fondo del propio slider: cápsula muy transparente para que
                // se vea sobre mapa/fondo sin dar sensación de bloque opaco.
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.28))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
            )
        }
        .frame(height: 38)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Logros
enum AchievementKind: CaseIterable {
    // Especiales
    case firstTrip, firstLayover, trips100, allWorld
    // Trophy
    case visitedAntarctica, todosLosContinentes
    // Oro – zona completada
    case europaCompleta, asiaCompleta, medioOrienteCompleto, africaCompleta, americaCompleta, oceaniaCompleta
    // Oro – grupos especiales
    case todaLaUE
    // Oro – hemisferios
    case ambosHemisferios
    // Plata – grupos especiales
    case todosEslavos, todosEscandinavos, todosBalcanicos, todosMicroestados
    // Bronce – al menos 1 país visitado en la región
    case visitedNortamerica, visitedCaribe, visitedSudamerica, visitedCentroamerica
    case visitedAfrica, visitedEuropa, visitedMedioOriente, visitedOceania, visitedAsia
    // Bronce – especiales
    case primerMicroestado
    // Plata – 5 viajes en la región
    case fiveEurope, fiveAsia, fiveAfrica, fiveMedioOriente, fiveOceania
    case fiveNortamerica, fiveCaribe, fiveSudamerica, fiveCentroamerica
    // Oro – pasaporte lleno
    case pasaporteEuropa, pasaporteAsia, pasaporteMedioOriente, pasaporteAfrica, pasaporteAmerica, pasaporteOceania

    // MARK: Sets de ISO por región (logros visitados/five)
    private static let _northAmerica: Set<String> = ["USA","MEX","CAN"]
    private static let _caribbean: Set<String> = [
        "ATG","BHS","BRB","CUB","DMA","DOM","GRD","HTI","JAM","KNA","LCA","VCT","TTO",
        "ABW","AIA","BMU","VGB","CYM","CUW","MSR","PRI","BLM","MAF","SXM","TCA","VIR"
    ]
    private static let _southAmerica: Set<String> = [
        "ARG","BOL","BRA","CHL","COL","ECU","GUY","PRY","PER","SUR","URY","VEN","FLK"
    ]
    private static let _centralAmerica: Set<String> = ["BLZ","CRI","SLV","GTM","HND","NIC","PAN"]
    private static let _europe: Set<String> = [
        "ALB","AND","AUT","BLR","BEL","BIH","BGR","HRV","CYP","CZE",
        "DNK","EST","FIN","FRA","DEU","GRC","HUN","ISL","IRL","ITA",
        "LVA","LIE","LTU","LUX","MLT","MDA","MCO","MNE","NLD","MKD",
        "NOR","POL","PRT","ROU","RUS","SMR","SRB","SVK","SVN","ESP",
        "SWE","CHE","UKR","GBR","VAT","KOS","ALD","FRO","GIB","GGY","IMN","JEY"
    ]
    private static let _asia: Set<String> = [
        "AFG","ARM","AZE","BGD","BTN","BRN","KHM","CHN","GEO","IND",
        "IDN","JPN","KAZ","PRK","KOR","KGZ","LAO","MYS","MDV","MNG",
        "MMR","NPL","PAK","PHL","SGP","LKA","TWN","TJK","THA","TLS",
        "TKM","UZB","VNM","HKG","MAC","IOT"
    ]
    private static let _middleEast: Set<String> = [
        "BHR","IRN","IRQ","ISR","JOR","KWT","LBN","OMN","PSE","PSX",
        "QAT","SAU","SYR","TUR","ARE","YEM"
    ]
    private static let _africa: Set<String> = [
        "DZA","AGO","BEN","BWA","BFA","BDI","CPV","CMR","CAF","TCD",
        "COM","COD","COG","CIV","DJI","EGY","GNQ","ERI","ETH","GAB",
        "GMB","GHA","GIN","GNB","KEN","LSO","LBR","LBY","MDG","MWI",
        "MLI","MRT","MUS","MAR","MOZ","NAM","NER","NGA","RWA","STP",
        "SEN","SYC","SLE","SOM","ZAF","SSD","SDS","SDN","SWZ","TZA",
        "TGO","TUN","UGA","ZMB","ZWE","SAH","SHN"
    ]
    private static let _oceania: Set<String> = [
        "AUS","FJI","KIR","MHL","FSM","NRU","NZL","PLW","PNG","WSM",
        "SLB","TON","TUV","VUT","ASM","COK","PYF","GUM","NCL","NIU","NFK","MNP","PCN","WLF"
    ]
    private static let _antarctica: Set<String> = ["ATA"]

    // MARK: Sets de grupos especiales
    private static let _unionEuropea: Set<String> = [
        "AUT","BEL","BGR","HRV","CYP","CZE","DNK","EST","FIN","FRA",
        "DEU","GRC","HUN","IRL","ITA","LVA","LTU","LUX","MLT","NLD",
        "POL","PRT","ROU","SVK","SVN","ESP","SWE"
    ]
    private static let _eslavos: Set<String> = [
        "RUS","UKR","BLR",                        // Eslavos orientales
        "POL","CZE","SVK",                         // Eslavos occidentales
        "SRB","HRV","SVN","BGR","MKD","BIH","MNE"  // Eslavos meridionales
    ]
    private static let _escandinavos: Set<String> = ["NOR","SWE","DNK","FIN","ISL"]
    private static let _balcanicos: Set<String> = [
        "ALB","BIH","BGR","HRV","GRC","MKD","MNE","ROU","SRB","SVN","KOS"
    ]
    private static let _microestados: Set<String> = ["AND","LIE","MCO","SMR","VAT","MLT"]

    // MARK: Sets de ISO por zona de Mi mapa (logros completados)
    private static let _zoneEuropa: Set<String> = [
        "ALB","AND","AUT","BLR","BEL","BIH","BGR","HRV","CYP","CZE",
        "DNK","EST","FIN","FRA","DEU","GRC","HUN","ISL","IRL","ITA",
        "LVA","LIE","LTU","LUX","MLT","MDA","MCO","MNE","NLD","MKD",
        "NOR","POL","PRT","ROU","RUS","SMR","SRB","SVK","SVN","ESP",
        "SWE","CHE","UKR","GBR","VAT","KOS","ALD","FRO","GIB","GGY","IMN","JEY"
    ]
    private static let _zoneAsia: Set<String> = [
        "AFG","ARM","AZE","BGD","BTN","BRN","KHM","CHN","GEO","IND",
        "IDN","JPN","KAZ","PRK","KOR","KGZ","LAO","MYS","MDV","MNG",
        "MMR","NPL","PAK","PHL","SGP","LKA","TWN","TJK","THA","TLS",
        "TKM","UZB","VNM","HKG","MAC","IOT"
    ]
    private static let _zoneMedioOriente: Set<String> = [
        "BHR","IRN","IRQ","ISR","JOR","KWT","LBN","OMN","PSE","PSX",
        "QAT","SAU","SYR","TUR","ARE","YEM"
    ]
    private static let _zoneAfrica: Set<String> = [
        "DZA","AGO","BEN","BWA","BFA","BDI","CPV","CMR","CAF","TCD",
        "COM","COD","COG","CIV","DJI","EGY","GNQ","ERI","ETH","GAB",
        "GMB","GHA","GIN","GNB","KEN","LSO","LBR","LBY","MDG","MWI",
        "MLI","MRT","MUS","MAR","MOZ","NAM","NER","NGA","RWA","STP",
        "SEN","SYC","SLE","SOM","ZAF","SSD","SDS","SDN","SWZ","TZA",
        "TGO","TUN","UGA","ZMB","ZWE","SAH","SHN"
    ]
    private static let _zoneAmerica: Set<String> = [
        "ATG","ARG","BHS","BRB","BLZ","BOL","BRA","CAN","CHL","COL",
        "CRI","CUB","DMA","DOM","ECU","SLV","GRD","GTM","GUY","HTI",
        "HND","JAM","MEX","NIC","PAN","PRY","PER","KNA","LCA","VCT",
        "SUR","TTO","USA","URY","VEN","ABW","AIA","BMU","VGB","CYM",
        "CUW","FLK","GRL","MSR","PRI","BLM","MAF","SPM","SXM","TCA","VIR"
    ]
    private static let _zoneOceania: Set<String> = [
        "AUS","FJI","KIR","MHL","FSM","NRU","NZL","PLW","PNG","WSM",
        "SLB","TON","TUV","VUT","ASM","COK","PYF","GUM","NCL","NIU",
        "NFK","MNP","PCN","WLF"
    ]

    // MARK: Hemisferio sur
    static let southernHemisphere: Set<String> = [
        // Sudamérica (centro claramente al sur del ecuador)
        "ARG","BOL","BRA","CHL","ECU","PER","PRY","URY","FLK",
        // África austral
        "AGO","BDI","BWA","COM","COD","COG","GAB","LSO","MDG","MOZ","MUS","MWI",
        "NAM","RWA","SWZ","SYC","TZA","ZAF","ZMB","ZWE",
        // Oceanía / Pacífico sur
        "AUS","FJI","NRU","NZL","PNG","SLB","TLS","TON","TUV","VUT","WSM",
        "ASM","COK","NCL","NIU","NFK","PCN","PYF","WLF",
        // Atlántico / Índico
        "IOT","SHN"
    ]

    // MARK: Multi-hemisphere adjustment
    // (iso, defaultHemisphere) — países que cruzan el ecuador
    static let multiHemisphereData: [(iso: String, defaultH: String, flag: String, name: String)] = [
        // Sudamérica
        ("ECU", "sur",   "🇪🇨", "Ecuador"),
        ("COL", "norte", "🇨🇴", "Colombia"),
        ("BRA", "sur",   "🇧🇷", "Brasil"),
        // África ecuatorial
        ("GAB", "norte", "🇬🇦", "Gabón"),
        ("COG", "sur",   "🇨🇬", "Congo"),
        ("COD", "sur",   "🇨🇩", "R. D. del Congo"),
        ("UGA", "norte", "🇺🇬", "Uganda"),
        ("KEN", "sur",   "🇰🇪", "Kenia"),
        ("SOM", "norte", "🇸🇴", "Somalia"),
        // Asia / Pacífico
        ("MDV", "norte", "🇲🇻", "Maldivas"),
        ("IDN", "sur",   "🇮🇩", "Indonesia"),
        ("KIR", "norte", "🇰🇮", "Kiribati"),
    ]

    static func adjustedHemispheres(assignments: [String: String]) -> (south: Set<String>, ambos: Set<String>) {
        var south = southernHemisphere
        var ambos = Set<String>()
        for entry in multiHemisphereData {
            let assignment = assignments[entry.iso] ?? entry.defaultH
            switch assignment {
            case "norte": south.remove(entry.iso)
            case "sur":   south.insert(entry.iso)
            case "ambos": south.remove(entry.iso); ambos.insert(entry.iso)
            default:      break
            }
        }
        return (south, ambos)
    }

    // MARK: Multi-continent adjustment
    // (iso, primaryZone, secondaryZone)
    private static let multiContinentData: [(String, String, String)] = [
        ("RUS", "europa",       "asia"),
        ("TUR", "medioOriente", "europa"),
        ("CYP", "europa",       "medioOriente"),
        ("AZE", "asia",         "europa"),
        ("GEO", "asia",         "europa"),
        ("KAZ", "asia",         "europa"),
        ("EGY", "africa",       "asia"),
    ]

    /// Returns the base set adjusted for multi-continent country preferences.
    static func adjustSet(_ base: Set<String>, forZone zoneName: String, assignments: [String: String]) -> Set<String> {
        var result = base
        for (iso, primary, secondary) in multiContinentData {
            let assignment = assignments[iso] ?? primary
            let inZone: Bool
            if assignment == "ambos" {
                inZone = (zoneName == primary || zoneName == secondary)
            } else {
                inZone = (assignment == zoneName)
            }
            if inZone { result.insert(iso) } else { result.remove(iso) }
        }
        return result
    }

    /// Geographic zone name for zone-completion achievements (nil = cultural/fixed group)
    var geographicZoneName: String? {
        switch self {
        case .europaCompleta:       return "europa"
        case .asiaCompleta:         return "asia"
        case .medioOrienteCompleto: return "medioOriente"
        case .africaCompleta:       return "africa"
        case .americaCompleta:      return "america"
        case .oceaniaCompleta:      return "oceania"
        default:                    return nil
        }
    }

    /// Geographic region name for visited/five-trip achievements
    var geographicRegionName: String? {
        switch self {
        case .visitedEuropa, .fiveEurope:                   return "europa"
        case .visitedAsia, .fiveAsia:                       return "asia"
        case .visitedMedioOriente, .fiveMedioOriente:       return "medioOriente"
        case .visitedAfrica, .fiveAfrica:                   return "africa"
        default:                                            return nil
        }
    }

    /// ExportZone rawValue key for passport-completion achievements (nil = other kinds)
    var passportZoneKey: String? {
        switch self {
        case .pasaporteEuropa:       return "Europa"
        case .pasaporteAsia:         return "Asia"
        case .pasaporteMedioOriente: return "M. Oriente"
        case .pasaporteAfrica:       return "África"
        case .pasaporteAmerica:      return "América"
        case .pasaporteOceania:      return "Oceanía"
        default:                     return nil
        }
    }

    /// Maps a `passportZoneKey` rawValue to the lowercase `zoneName` used in
    /// `multiContinentData`. Used for filtering pluricontinental countries
    /// out of the wrong zone in passport-completion checks.
    static func zoneName(forPassportKey key: String) -> String? {
        switch key {
        case "Europa":      return "europa"
        case "Asia":        return "asia"
        case "M. Oriente":  return "medioOriente"
        case "África":      return "africa"
        case "América":     return "america"
        case "Oceanía":     return "oceania"
        default:            return nil
        }
    }

    /// Antes filtraba ISOs pluricontinentales según asignación de zona en
    /// Ajustes. Ahora devuelve los ISOs sin filtrar: el usuario decide
    /// libremente en qué cuadrante meter cada país pluri y siempre cuenta
    /// donde lo pone, independientemente del continente asignado.
    static func filterCandidatesForZone(_ isos: [String], zoneName: String, assignments: [String: String], quadrantTitle: String? = nil) -> [String] {
        return isos
    }

    var zoneIsoCodes: Set<String> {
        switch self {
        case .europaCompleta:       return Self._zoneEuropa
        case .asiaCompleta:         return Self._zoneAsia
        case .medioOrienteCompleto: return Self._zoneMedioOriente
        case .africaCompleta:       return Self._zoneAfrica
        case .americaCompleta:      return Self._zoneAmerica
        case .oceaniaCompleta:      return Self._zoneOceania
        case .todaLaUE:             return Self._unionEuropea
        case .todosEslavos:         return Self._eslavos
        case .todosEscandinavos:    return Self._escandinavos
        case .todosBalcanicos:      return Self._balcanicos
        case .todosMicroestados:    return Self._microestados
        // passport achievements use candidateIsoCodes from mapQuadrantsData, not static sets
        case .pasaporteEuropa, .pasaporteAsia, .pasaporteMedioOriente,
             .pasaporteAfrica, .pasaporteAmerica, .pasaporteOceania: return []
        default:                    return []
        }
    }

    var regionIsoCodes: Set<String> {
        switch self {
        case .visitedNortamerica, .fiveNortamerica:       return Self._northAmerica
        case .visitedCaribe, .fiveCaribe:                 return Self._caribbean
        case .visitedSudamerica, .fiveSudamerica:         return Self._southAmerica
        case .visitedCentroamerica, .fiveCentroamerica:   return Self._centralAmerica
        case .visitedEuropa, .fiveEurope:                 return Self._europe
        case .visitedAsia:                                return Self._asia.union(Self._middleEast)
        case .fiveAsia:                                   return Self._asia
        case .visitedMedioOriente, .fiveMedioOriente:     return Self._middleEast
        case .visitedAfrica, .fiveAfrica:                 return Self._africa
        case .visitedOceania, .fiveOceania:               return Self._oceania
        case .visitedAntarctica:                          return Self._antarctica
        default:                                          return []
        }
    }

    var regionName: String {
        switch self {
        case .visitedEuropa, .fiveEurope:                 return "Europa"
        case .visitedAsia, .fiveAsia:                     return "Asia"
        case .visitedAfrica, .fiveAfrica:                 return "África"
        case .visitedMedioOriente, .fiveMedioOriente:     return "Medio Oriente"
        case .visitedOceania, .fiveOceania:               return "Oceanía"
        case .visitedNortamerica, .fiveNortamerica:       return "Norteamérica"
        case .visitedCaribe, .fiveCaribe:                 return "el Caribe"
        case .visitedSudamerica, .fiveSudamerica:         return "Sudamérica"
        case .visitedCentroamerica, .fiveCentroamerica:   return "Centroamérica"
        default:                                          return ""
        }
    }

    var title: String {
        switch self {
        case .firstTrip:            return "Tu primer viaje"
        case .firstLayover:         return "Primera escala"
        case .trips100:             return "100 viajes"
        case .allWorld:             return "Todo el mundo"
        case .visitedAntarctica:    return "He estado en Antártida"
        case .todosLosContinentes:  return "Todos los continentes"
        case .europaCompleta:       return "Europa completada"
        case .asiaCompleta:         return "Asia completada"
        case .medioOrienteCompleto: return "M. Oriente completado"
        case .africaCompleta:       return "África completada"
        case .americaCompleta:      return "América completada"
        case .oceaniaCompleta:      return "Oceanía completada"
        case .ambosHemisferios:     return "Ambos hemisferios"
        case .todaLaUE:             return "Toda la UE"
        case .todosEslavos:         return "Todos los eslavos"
        case .todosEscandinavos:    return "Todos los escandinavos"
        case .todosBalcanicos:      return "Todos los balcánicos"
        case .todosMicroestados:    return "Todos los microestados"
        case .visitedNortamerica:   return "He estado en Norteamérica"
        case .visitedCaribe:        return "He estado en el Caribe"
        case .visitedSudamerica:    return "He estado en Sudamérica"
        case .visitedCentroamerica: return "He estado en Centroamérica"
        case .visitedAfrica:        return "He estado en África"
        case .visitedEuropa:        return "He estado en Europa"
        case .visitedMedioOriente:  return "He estado en Medio Oriente"
        case .visitedOceania:       return "He estado en Oceanía"
        case .visitedAsia:          return "He estado en Asia"
        case .primerMicroestado:    return "Mi primer microestado"
        case .fiveEurope:           return "Cinco veces en Europa"
        case .fiveAsia:             return "Cinco veces en Asia"
        case .fiveAfrica:           return "Cinco veces en África"
        case .fiveMedioOriente:     return "Cinco veces en Medio Oriente"
        case .fiveOceania:          return "Cinco veces en Oceanía"
        case .fiveNortamerica:      return "Cinco veces en Norteamérica"
        case .fiveCaribe:           return "Cinco veces en el Caribe"
        case .fiveSudamerica:       return "Cinco veces en Sudamérica"
        case .fiveCentroamerica:    return "Cinco veces en Centroamérica"
        case .pasaporteEuropa:      return "Pasaporte Europa completo"
        case .pasaporteAsia:        return "Pasaporte Asia completo"
        case .pasaporteMedioOriente: return "Pasaporte M. Oriente completo"
        case .pasaporteAfrica:      return "Pasaporte África completo"
        case .pasaporteAmerica:     return "Pasaporte América completo"
        case .pasaporteOceania:     return "Pasaporte Oceanía completo"
        }
    }

    var medal: String {
        switch self {
        case .allWorld, .visitedAntarctica, .todosLosContinentes:
            return "🏆"
        case .trips100, .europaCompleta, .asiaCompleta, .medioOrienteCompleto,
             .africaCompleta, .americaCompleta, .oceaniaCompleta, .ambosHemisferios,
             .todaLaUE,
             .pasaporteEuropa, .pasaporteAsia, .pasaporteMedioOriente,
             .pasaporteAfrica, .pasaporteAmerica, .pasaporteOceania:
            return "🥇"
        case .fiveEurope, .fiveAsia, .fiveAfrica, .fiveMedioOriente, .fiveOceania,
             .fiveNortamerica, .fiveCaribe, .fiveSudamerica, .fiveCentroamerica,
             .firstLayover,
             .todosEslavos, .todosEscandinavos, .todosBalcanicos, .todosMicroestados:
            return "🥈"
        case .firstTrip, .visitedNortamerica, .visitedCaribe, .visitedSudamerica,
             .visitedCentroamerica, .visitedAfrica, .visitedEuropa, .visitedMedioOriente,
             .visitedOceania, .visitedAsia, .primerMicroestado:
            return "🥉"
        }
    }

    var medalOrder: Int {
        switch self {
        case .allWorld, .visitedAntarctica, .todosLosContinentes: return 0
        case .trips100, .europaCompleta, .asiaCompleta, .medioOrienteCompleto,
             .africaCompleta, .americaCompleta, .oceaniaCompleta, .ambosHemisferios,
             .todaLaUE,
             .pasaporteEuropa, .pasaporteAsia, .pasaporteMedioOriente,
             .pasaporteAfrica, .pasaporteAmerica, .pasaporteOceania: return 1
        case .fiveEurope, .fiveAsia, .fiveAfrica, .fiveMedioOriente, .fiveOceania,
             .fiveNortamerica, .fiveCaribe, .fiveSudamerica, .fiveCentroamerica,
             .firstLayover,
             .todosEslavos, .todosEscandinavos, .todosBalcanicos, .todosMicroestados: return 2
        case .firstTrip, .visitedNortamerica, .visitedCaribe, .visitedSudamerica,
             .visitedCentroamerica, .visitedAfrica, .visitedEuropa, .visitedMedioOriente,
             .visitedOceania, .visitedAsia, .primerMicroestado: return 3
        }
    }
}

// MARK: - Pantalla de perfil
struct ProfileSheet: View {
    @Binding var username: String
    @Binding var selectedPassport: String
    @Binding var countingModeRaw: String
    @Binding var menuPositionRaw: String
    @Binding var showBucketList: Bool
    @Binding var showCountdown: Bool
    var onClearStatus: (CountryStatus) -> Void = { _ in }
    var onProximosTap: (() -> Void)? = nil
    @Binding var topTable: String
    let visitedFlags: Set<String>
    let allFeatures: [CountryFeature]
    let visitedIsoCodes: Set<String>
    let countries: [Country]
    let trips: [Trip]

    @EnvironmentObject private var colorTheme: ColorThemeManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showSettings: Bool = false
    @State private var showMapExport: Bool = false
    @State private var showLogros: Bool = false
    @State private var showVisitedFlags: Bool = false
    @State private var showMedallero: Bool = false
    @State private var showTransportStats: Bool = false
    @State private var showYearWrapped: Bool = false
    @State private var showSubscriptionFromProfile: Bool = false
    // Sheet de finalizados gestionado dentro del perfil para que no haya conflicto
    // con el propio sheet del perfil (SwiftUI sólo permite 1 sheet activo por nivel).
    @State private var finalizadosPayload: FinalizadosSheetPayload? = nil
    // Mismo motivo para Próximos: si se presenta desde el root, SwiftUI cierra
    // el perfil para abrirlo, dando un parpadeo. Se gestiona localmente.
    @State private var proximosShown: Bool = false
    @State private var editingProximoTrip: Trip? = nil
    @State private var pendingProximoCountryForDate: Country? = nil

    @AppStorage("multiContinentRaw") private var multiContinentRaw: String = "{}"
    @AppStorage("multiHemisphereRaw") private var multiHemisphereRaw: String = "{}"
    @AppStorage("isRaskmapPro") private var isRaskmapPro: Bool = false
    @AppStorage("mapQuadrantsData") private var mapQuadrantsData: String = "{}"
    @AppStorage("earnedPassportAchievementsRaw") private var earnedPassportRaw: String = "[]"
    @State private var multiContinentAssignments: [String: String] = [:]
    @State private var multiHemisphereAssignments: [String: String] = [:]
    @State private var allPassportQuadrants: [String: [MapQuadrant]] = [:]
    @State private var earnedPassportZones: Set<String> = []
    @State private var cachedPastTrips: [Trip] = []

    enum MedalSlot: String, Identifiable {
        case gold, silver, bronze
        var id: String { rawValue }
        var emoji: String {
            switch self { case .gold: "🥇"; case .silver: "🥈"; case .bronze: "🥉" }
        }
        var label: String {
            switch self { case .gold: "Oro"; case .silver: "Plata"; case .bronze: "Bronce" }
        }
    }

    private var countingMode: CountingMode { CountingMode(rawValue: countingModeRaw) ?? .all }

    // MARK: - Logros
    private var firstTrip: Trip? { cachedPastTrips.min(by: { $0.dateFrom < $1.dateFrom }) }
    private var firstLayoverTrip: Trip? { cachedPastTrips.filter { $0.hasLayover }.min(by: { $0.dateFrom < $1.dateFrom }) }
    private var firstMicroestadoTrip: Trip? {
        let microSet = AchievementKind.todosMicroestados.zoneIsoCodes
        return cachedPastTrips.filter { microSet.contains($0.isoCode) }.min(by: { $0.dateFrom < $1.dateFrom })
    }
    private var trip100: Trip? {
        let sorted = cachedPastTrips.sorted { $0.dateFrom < $1.dateFrom }
        return sorted.count >= 100 ? sorted[99] : nil
    }
    private func profileLastTripDate(for kind: AchievementKind) -> Date {
        switch kind {
        case .firstTrip:         return firstTrip?.effectiveEndDate ?? .distantPast
        case .firstLayover:      return firstLayoverTrip?.effectiveEndDate ?? .distantPast
        case .trips100:          return trip100?.effectiveEndDate ?? .distantPast
        case .primerMicroestado: return firstMicroestadoTrip?.dateFrom ?? .distantPast
        case .allWorld, .ambosHemisferios, .todosLosContinentes:
            return cachedPastTrips.map { $0.effectiveEndDate }.max() ?? .distantPast
        default:
            let isoCodes = kind.zoneIsoCodes.isEmpty ? kind.regionIsoCodes : kind.zoneIsoCodes
            return cachedPastTrips.filter { isoCodes.contains($0.isoCode) }
                .map { $0.effectiveEndDate }.max() ?? .distantPast
        }
    }

    private var visitedFlagEmojis: [String] {
        let codes = visitedIsoCodes.filter { countingMode.counts($0) }
        return allFeatures
            .filter { codes.contains($0.isoCode) && $0.flagEmoji != nil }
            .sorted { $0.localizedName.localizedCompare($1.localizedName) == .orderedAscending }
            .compactMap { $0.flagEmoji }
    }

    // Próximos rows: una fila por cada país wantToVisit (con o sin trip futuro)
    // y por cada visited con trip futuro. Mismo patrón que `allProximoRows` del root.
    private var profileProximoRows: [ProximoRow] {
        let today = Calendar.current.startOfDay(for: Date())
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
        let futureIsoCodes = Set(trips.compactMap { trip -> String? in
            guard Calendar.current.startOfDay(for: trip.dateFrom) >= today else { return nil }
            return trip.isoCode
        })
        for country in countries where country.status == .visited && futureIsoCodes.contains(country.isoCode) {
            let nearestTrip = (tripsByIso[country.isoCode] ?? [])
                .filter { Calendar.current.startOfDay(for: $0.dateFrom) >= today }
                .min(by: { $0.dateFrom < $1.dateFrom })
            rows.append(ProximoRow(id: "v_\(country.isoCode)", country: country, trip: nearestTrip))
        }
        return rows
    }

    // Filas de finalizados para un año concreto (duplicado del helper homónimo
    // en ContentView, aquí dentro de ProfileSheet para que el sheet pueda montarse
    // desde el propio perfil y presentarse al instante al tocar "Finalizados").
    private func finalizadoRows(year: Int) -> [ProximoRow] {
        let today = Calendar.current.startOfDay(for: Date())
        let countryByIso: [String: Country] = Dictionary(uniqueKeysWithValues:
            countries.map { ($0.isoCode, $0) }
        )
        var rows: [ProximoRow] = []
        for trip in trips where !trip.isSegmentChild {
            let endDay = Calendar.current.startOfDay(for: trip.effectiveEndDate)
            guard endDay <= today, trip.year == year else { continue }
            guard let country = countryByIso[trip.isoCode] else { continue }
            let tid = "t_\(trip.isoCode)_\(trip.createdAt.timeIntervalSince1970)"
            rows.append(ProximoRow(id: tid, country: country, trip: trip))
        }
        let tripIsosInYear = Set(trips.filter { !$0.isSegmentChild && $0.year == year }.map { $0.isoCode })
        for country in countries {
            guard !tripIsosInYear.contains(country.isoCode) else { continue }
            let endDate = country.plannedDateTo ?? country.plannedDate
            guard let end = endDate else { continue }
            let endDay = Calendar.current.startOfDay(for: end)
            let yearOfEnd = Calendar.current.component(.year, from: end)
            guard endDay <= today, yearOfEnd == year else { continue }
            rows.append(ProximoRow(id: "c_\(country.isoCode)", country: country, trip: nil))
        }
        return rows.sorted {
            let a = $0.dateFrom ?? .distantPast
            let b = $1.dateFrom ?? .distantPast
            return a < b
        }
    }

    private func isPassportAchieved(_ kind: AchievementKind) -> Bool {
        guard let zoneKey = kind.passportZoneKey else { return false }
        // Una vez ganado, se mantiene aunque se añadan nuevos cuadrantes incompletos
        if earnedPassportZones.contains(zoneKey) { return true }
        let quadrants = (allPassportQuadrants[zoneKey] ?? []).filter { $0.position >= 0 }
        guard !quadrants.isEmpty else { return false }
        let zoneNameLower = AchievementKind.zoneName(forPassportKey: zoneKey)
        return quadrants.allSatisfy { q in
            let filtered = zoneNameLower.map { AchievementKind.filterCandidatesForZone(q.candidateIsoCodes, zoneName: $0, assignments: multiContinentAssignments, quadrantTitle: q.title) } ?? q.candidateIsoCodes
            return filtered.allSatisfy { visitedIsoCodes.contains($0) }
        }
    }

    private func isAchieved(_ kind: AchievementKind) -> Bool {
        let assignments = multiContinentAssignments
        switch kind {
        case .pasaporteEuropa, .pasaporteAsia, .pasaporteMedioOriente,
             .pasaporteAfrica, .pasaporteAmerica, .pasaporteOceania:
            return isPassportAchieved(kind)
        case .firstTrip:         return firstTrip != nil
        case .firstLayover:      return firstLayoverTrip != nil
        case .trips100:          return trip100 != nil
        case .primerMicroestado: return firstMicroestadoTrip != nil
        case .allWorld:
            let visited = countries.filter { c in
                let isVisited = (c.status == .visited || c.status == .lived) && countingMode.counts(c.isoCode)
                let hasPastTrip = cachedPastTrips.contains { $0.isoCode == c.isoCode }
                return isVisited && (c.visitCount > 0 || hasPastTrip)
            }.count
            return visited >= countingMode.denominator && countingMode.denominator > 0
        case .visitedNortamerica, .visitedCaribe, .visitedSudamerica, .visitedCentroamerica,
             .visitedAfrica, .visitedEuropa, .visitedMedioOriente, .visitedOceania,
             .visitedAsia, .visitedAntarctica:
            let base = kind.regionIsoCodes
            let adjusted = kind.geographicRegionName.map { AchievementKind.adjustSet(base, forZone: $0, assignments: assignments) } ?? base
            return !adjusted.isDisjoint(with: visitedIsoCodes)
        case .fiveEurope, .fiveAsia, .fiveAfrica, .fiveMedioOriente, .fiveOceania,
             .fiveNortamerica, .fiveCaribe, .fiveSudamerica, .fiveCentroamerica:
            let base = kind.regionIsoCodes
            let adjusted = kind.geographicRegionName.map { AchievementKind.adjustSet(base, forZone: $0, assignments: assignments) } ?? base
            return cachedPastTrips.filter { adjusted.contains($0.isoCode) }.count >= 5
        case .europaCompleta, .asiaCompleta, .medioOrienteCompleto,
             .africaCompleta, .americaCompleta, .oceaniaCompleta,
             .todaLaUE, .todosEslavos, .todosEscandinavos, .todosBalcanicos, .todosMicroestados:
            let base = kind.zoneIsoCodes
            let adjusted = kind.geographicZoneName.map { AchievementKind.adjustSet(base, forZone: $0, assignments: assignments) } ?? base
            let valid = adjusted.filter { countingMode.counts($0) }
            return !valid.isEmpty && valid.allSatisfy { visitedIsoCodes.contains($0) }
        case .ambosHemisferios:
            let (hSouth, hAmbos) = AchievementKind.adjustedHemispheres(assignments: multiHemisphereAssignments)
            let hasSouth = visitedIsoCodes.contains { (hSouth.contains($0) || hAmbos.contains($0)) && countingMode.counts($0) }
            let hasNorth = visitedIsoCodes.contains { (!hSouth.contains($0) || hAmbos.contains($0)) && countingMode.counts($0) }
            return hasSouth && hasNorth
        case .todosLosContinentes:
            let americaSet = AchievementKind.visitedNortamerica.regionIsoCodes
                .union(AchievementKind.visitedCaribe.regionIsoCodes)
                .union(AchievementKind.visitedSudamerica.regionIsoCodes)
                .union(AchievementKind.visitedCentroamerica.regionIsoCodes)
            let continentSets = [
                AchievementKind.visitedEuropa.regionIsoCodes,
                AchievementKind.visitedAsia.regionIsoCodes,
                AchievementKind.visitedAfrica.regionIsoCodes,
                americaSet,
                AchievementKind.visitedOceania.regionIsoCodes,
            ]
            return continentSets.allSatisfy { set in
                !set.filter { countingMode.counts($0) }.isDisjoint(with: visitedIsoCodes)
            }
        }
    }

    @ViewBuilder
    private func profileMenuRow(icon: String, iconColor: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor)
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(label)
                    .font(.palatino(.body))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color(.systemGray3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tabla Top
    enum TopRegion: String, CaseIterable, Identifiable {
        case europa       = "Europa"
        case asia         = "Asia"
        case medioOriente = "M. Oriente"
        case africa       = "África"
        case america      = "América"
        case oceania      = "Oceanía"
        var id: String { rawValue }

        var isoCodes: Set<String> {
            switch self {
            case .europa:
                return ["ALB","AND","AUT","BLR","BEL","BIH","BGR","HRV","CYP","CZE",
                        "DNK","EST","FIN","FRA","DEU","GRC","HUN","ISL","IRL","ITA",
                        "LVA","LIE","LTU","LUX","MLT","MDA","MCO","MNE","NLD","MKD",
                        "NOR","POL","PRT","ROU","RUS","SMR","SRB","SVK","SVN","ESP",
                        "SWE","CHE","UKR","GBR","VAT","KOS",
                        // Territorios con bandera
                        "ALD","FRO","GIB","GGY","IMN","JEY"]
            case .asia:
                return ["AFG","ARM","AZE","BGD","BTN","BRN","KHM","CHN","GEO","IND",
                        "IDN","JPN","KAZ","PRK","KOR","KGZ","LAO","MYS","MDV","MNG",
                        "MMR","NPL","PAK","PHL","SGP","LKA","TWN","TJK","THA","TLS",
                        "TKM","UZB","VNM",
                        // Territorios con bandera
                        "HKG","MAC","IOT"]
            case .medioOriente:
                return ["BHR","IRN","IRQ","ISR","JOR","KWT","LBN","OMN","PSE","PSX",
                        "QAT","SAU","SYR","TUR","ARE","YEM"]
            case .africa:
                return ["DZA","AGO","BEN","BWA","BFA","BDI","CPV","CMR","CAF","TCD",
                        "COM","COD","COG","CIV","DJI","EGY","GNQ","ERI","ETH","GAB",
                        "GMB","GHA","GIN","GNB","KEN","LSO","LBR","LBY","MDG","MWI",
                        "MLI","MRT","MUS","MAR","MOZ","NAM","NER","NGA","RWA","STP",
                        "SEN","SYC","SLE","SOM","ZAF","SSD","SDS","SDN","SWZ","TZA",
                        "TGO","TUN","UGA","ZMB","ZWE",
                        // Territorios con bandera
                        "SAH","SHN"]
            case .america:
                return ["ATG","ARG","BHS","BRB","BLZ","BOL","BRA","CAN","CHL","COL",
                        "CRI","CUB","DMA","DOM","ECU","SLV","GRD","GTM","GUY","HTI",
                        "HND","JAM","MEX","NIC","PAN","PRY","PER","KNA","LCA","VCT",
                        "SUR","TTO","USA","URY","VEN",
                        // Territorios con bandera
                        "ABW","AIA","BMU","VGB","CYM","CUW","FLK","GRL","MSR",
                        "PRI","BLM","MAF","SPM","SXM","TCA","VIR"]
            case .oceania:
                return ["AUS","FJI","KIR","MHL","FSM","NRU","NZL","PLW","PNG","WSM",
                        "SLB","TON","TUV","VUT",
                        // Territorios con bandera
                        "ASM","COK","PYF","GUM","NCL","NIU","NFK","MNP","PCN","WLF"]
            }
        }
    }

    struct TopSpot: Identifiable {
        let region: TopRegion
        let medal: MedalSlot
        var id: String { "\(region.rawValue)_\(medal.rawValue)" }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // ── Porcentaje ──
                    let pastTripIsoCodes = Set(cachedPastTrips.map { $0.isoCode })
                    let visitedCount: Int = countries.filter { c in
                        (c.status == .visited || c.status == .lived) && (c.visitCount > 0 || pastTripIsoCodes.contains(c.isoCode))
                    }.count
                    let denominator = countingMode.denominator
                    let pct = denominator > 0 ? Double(visitedCount) / Double(denominator) * 100.0 : 0.0
                    HStack(alignment: .center, spacing: 16) {
                        // Número grande — zona tapeable independiente
                        Button {
                            if isRaskmapPro { showVisitedFlags = true }
                            else { showSubscriptionFromProfile = true }
                        } label: {
                            ZStack {
                                VStack(spacing: 2) {
                                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                                        Text(String(format: "%.1f", pct))
                                            .font(.custom("Satoshi-Bold", size: 48))
                                            .minimumScaleFactor(0.5)
                                            .lineLimit(1)
                                        Text("%")
                                            .font(.custom("Satoshi-Bold", size: 22))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("del mundo visitado")
                                        .font(.palatino(.caption))
                                        .foregroundStyle(.secondary)
                                }
                                .blur(radius: isRaskmapPro ? 0 : 8)
                                if !isRaskmapPro {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(.purple)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)

                        // Divisor vertical
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(width: 0.5, height: 60)

                        // Logros — zona tapeable independiente
                        let topAchieved = AchievementKind.allCases
                            .filter { isAchieved($0) }
                            .sorted { a, b in
                                if a.medalOrder != b.medalOrder { return a.medalOrder < b.medalOrder }
                                return profileLastTripDate(for: a) > profileLastTripDate(for: b)
                            }
                            .prefix(3)
                        Button {
                            if isRaskmapPro { showLogros = true }
                            else { showSubscriptionFromProfile = true }
                        } label: {
                            ZStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Logros")
                                        .font(.custom("Satoshi-Bold", size: 11))
                                        .foregroundStyle(.secondary)
                                        .tracking(0.5)
                                        .textCase(.uppercase)
                                    if topAchieved.isEmpty {
                                        Text("Sin logros aún")
                                            .font(.palatino(.caption))
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(Array(topAchieved), id: \.title) { kind in
                                            HStack(spacing: 5) {
                                                Text(kind.medal).font(.caption)
                                                Text(kind.title)
                                                    .font(.palatino(.caption))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Text("Ver todos →")
                                            .font(.palatino(.caption))
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .blur(radius: isRaskmapPro ? 0 : 5)
                                if !isRaskmapPro {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.purple)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 4)

                    // ── Años + Finalizados/Próximos ──
                    YearTravelView(
                        countries: countries,
                        features: allFeatures,
                        trips: trips,
                        onProximosTap: { proximosShown = true },
                        onFinalizadosTap: { year in
                            finalizadosPayload = FinalizadosSheetPayload(year: year)
                        }
                    )

                    Divider().padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)

                    // ── Menú accesos rápidos ──
                    VStack(spacing: 0) {
                        profileMenuRow(icon: "trophy.fill", iconColor: .orange, label: "Premios personales") {
                            showMedallero = true
                        }
                        Divider().padding(.leading, 52)
                        profileMenuRow(icon: "map.fill", iconColor: .blue, label: "Mi mapa") {
                            showMapExport = true
                        }
                        Divider().padding(.leading, 52)
                        profileMenuRow(icon: "airplane", iconColor: Color(red: 0x53/255, green: 0xA3/255, blue: 0xFE/255), label: "Transportes") {
                            showTransportStats = true
                        }
                        Divider().padding(.leading, 52)
                        profileMenuRow(icon: "sparkles", iconColor: .purple, label: "Resumen \(Calendar.current.component(.year, from: Date()) - 1)") {
                            showYearWrapped = true
                        }
                    }
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                        .font(.palatino(.body))
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        if isRaskmapPro {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.purple)
                        }
                        Text(username.isEmpty ? "Perfil" : username)
                            .font(.palatino(.headline, weight: .bold))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.body)
                    }
                }
            }
        }
        .sheet(isPresented: $showTransportStats) {
            TransportStatsSheet(
                visitedCountries: countries.filter { $0.status == .visited || $0.status == .lived },
                trips: trips,
                allFeatures: allFeatures
            )
        }
        .fullScreenCover(isPresented: $showYearWrapped) {
            YearWrappedSheet(trips: trips, allFeatures: allFeatures)
        }
        .sheet(isPresented: $showMedallero) {
            MedalleroSheet(topTable: $topTable, allFeatures: allFeatures, visitedIsoCodes: visitedIsoCodes)
        }
        .sheet(isPresented: $showMapExport) {
            MapExportSheet(
                visitedCountries: countries.filter { $0.status == .visited || $0.status == .lived },
                features: allFeatures,
                countingModeRaw: countingModeRaw,
                visitedColor: colorTheme.visitedColor,
                trips: trips
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                username: $username,
                selectedPassport: $selectedPassport,
                countingModeRaw: $countingModeRaw,
                menuPositionRaw: $menuPositionRaw,
                showBucketList: $showBucketList,
                onClearStatus: onClearStatus
            )
            .environmentObject(colorTheme)
        }
        .sheet(isPresented: $showSubscriptionFromProfile) {
            SubscriptionSheet()
        }
        .sheet(isPresented: $proximosShown) {
            StatusListSheet(
                filter: .wantToVisit,
                countries: [],
                proximoRows: profileProximoRows,
                features: allFeatures,
                trips: trips,
                onRemove: { country in
                    let today = Calendar.current.startOfDay(for: Date())
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
                    try? modelContext.save()
                },
                onSetDate: { country, trip in
                    if let trip = trip {
                        proximosShown = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            editingProximoTrip = trip
                        }
                    } else {
                        proximosShown = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            pendingProximoCountryForDate = country
                        }
                    }
                },
                onRemoveProximo: { row in
                    let today = Calendar.current.startOfDay(for: Date())
                    let country = row.country
                    if let trip = row.trip {
                        modelContext.delete(trip)
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
                    try? modelContext.save()
                },
                onDeleteAll: {
                    let today = Calendar.current.startOfDay(for: Date())
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
                    try? modelContext.save()
                }
            )
        }
        .sheet(item: $editingProximoTrip) { trip in
            EditTripSheet(trip: trip, isForFuture: true, features: allFeatures)
                .environmentObject(colorTheme)
        }
        .sheet(item: $pendingProximoCountryForDate) { country in
            AddTripSheet(
                isoCode: country.isoCode,
                displayName: allFeatures.first(where: { $0.isoCode == country.isoCode })?.localizedName ?? country.name,
                flagEmoji: allFeatures.first(where: { $0.isoCode == country.isoCode })?.flagEmoji ?? "🌐",
                features: allFeatures,
                isForFuture: true,
                onSave: { trip, _ in
                    modelContext.insert(trip)
                    country.status = .wantToVisit
                    if country.plannedDate == nil || trip.dateFrom < country.plannedDate! {
                        country.plannedDate = trip.dateFrom
                        country.plannedDateTo = trip.dateTo
                        country.transport = trip.transport
                        country.plannedTitle = trip.title
                    }
                    try? modelContext.save()
                }
            )
            .environmentObject(colorTheme)
        }
        .sheet(item: $finalizadosPayload) { payload in
            FinalizadosListSheet(
                year: payload.year,
                rows: finalizadoRows(year: payload.year),
                features: allFeatures,
                onRemove: { row in
                    // Borrar el trip + cascada de grupo. Mismo comportamiento que el
                    // sheet antiguo del root: cascada por segmentGroupID y reeval
                    // de Country.status al final.
                    guard let trip = row.trip else { return }
                    let today = Calendar.current.startOfDay(for: Date())
                    var seenIDs = Set<ObjectIdentifier>()
                    var allToDelete: [Trip] = []
                    if let gid = trip.segmentGroupID {
                        let desc = FetchDescriptor<Trip>(predicate: #Predicate { $0.segmentGroupID == gid })
                        for t in modelContext.fetchOrWarn(desc, fallback: [trip]) {
                            if seenIDs.insert(ObjectIdentifier(t)).inserted { allToDelete.append(t) }
                        }
                    } else {
                        if seenIDs.insert(ObjectIdentifier(trip)).inserted { allToDelete.append(trip) }
                    }
                    for t in allToDelete { modelContext.delete(t) }
                    try? modelContext.save()
                    // Reevaluar el estado de los países tocados
                    let touched = Set(allToDelete.map { $0.isoCode })
                    for iso in touched {
                        let cd = FetchDescriptor<Country>(predicate: #Predicate { $0.isoCode == iso })
                        guard let c = modelContext.fetchFirstOrWarn(cd) else { continue }
                        guard c.status == .visited || c.status == .lived else { continue }
                        let td = FetchDescriptor<Trip>(predicate: #Predicate { $0.isoCode == iso })
                        let remaining = modelContext.fetchOrWarn(td)
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
                    try? modelContext.save()
                    // Refrescar el sheet con las filas actualizadas — si no quedan, cerramos
                    let updated = finalizadoRows(year: payload.year)
                    if updated.isEmpty {
                        finalizadosPayload = nil
                    } else {
                        finalizadosPayload = FinalizadosSheetPayload(year: payload.year)
                    }
                },
                onDuplicate: { row in
                    // Duplicar viaje a +365 días: copia primary + children del
                    // mismo segmentGroupID, manteniendo segments/airports/airlines.
                    // Country se promociona a wantToVisit.
                    guard let original = row.trip else { return }
                    let cal = Calendar.current
                    let shift: TimeInterval = 365 * 24 * 60 * 60
                    let newGroupID = UUID().uuidString

                    // Buscar todos los miembros del grupo (primary + children).
                    let groupTrips: [Trip]
                    if let gid = original.segmentGroupID {
                        let desc = FetchDescriptor<Trip>(predicate: #Predicate { $0.segmentGroupID == gid })
                        groupTrips = modelContext.fetchOrWarn(desc, fallback: [original])
                    } else {
                        groupTrips = [original]
                    }

                    for src in groupTrips {
                        let newFrom = src.dateFrom.addingTimeInterval(shift)
                        let newTo = src.dateTo.map { $0.addingTimeInterval(shift) }
                        let copy = Trip(
                            isoCode: src.isoCode,
                            title: src.title,
                            dateFrom: newFrom,
                            dateTo: newTo,
                            transport: src.transport,
                            tripAirports: src.tripAirports,
                            tripAirlines: src.tripAirlines
                        )
                        copy.hasLayover = src.hasLayover
                        copy.segmentGroupID = newGroupID
                        copy.isSegmentChild = src.isSegmentChild
                        copy.flightDetails = src.flightDetails
                        copy.visitedLayoverISOs = src.visitedLayoverISOs
                        // Shift dates en los segments embebidos también.
                        if !src.tripSegments.isEmpty {
                            copy.tripSegments = src.tripSegments.map { seg in
                                var s = seg
                                s.dateFrom = seg.dateFrom.addingTimeInterval(shift)
                                s.dateTo = seg.dateTo.map { $0.addingTimeInterval(shift) }
                                return s
                            }
                        }
                        modelContext.insert(copy)

                        // Promocionar el país a wantToVisit (si no es ya visited/lived).
                        let iso = src.isoCode
                        let cd = FetchDescriptor<Country>(predicate: #Predicate { $0.isoCode == iso })
                        if let country = modelContext.fetchFirstOrWarn(cd),
                           country.status != .visited && country.status != .lived {
                            country.status = .wantToVisit
                            if country.plannedDate == nil || newFrom < country.plannedDate! {
                                country.plannedDate = newFrom
                                country.plannedDateTo = newTo
                                country.transport = src.transport
                                country.plannedTitle = src.title
                            }
                        }
                        _ = cal // suppress unused warning if calendar isn't used elsewhere
                    }
                    try? modelContext.save()
                    // Refrescar el sheet
                    finalizadosPayload = FinalizadosSheetPayload(year: payload.year)
                }
            )
        }
        .overlay {
            if showVisitedFlags {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showVisitedFlags = false } }
                    VStack(spacing: 12) {
                        let toastTitle = countingMode == .all ? "Territorios visitados" : "Países visitados"
                        Text("\(toastTitle) (\(visitedFlagEmojis.count))")
                            .font(.palatino(.subheadline, weight: .bold))
                        ScrollView {
                            VStack(alignment: .center, spacing: 6) {
                                let rows = stride(from: 0, to: visitedFlagEmojis.count, by: 7).map {
                                    Array(visitedFlagEmojis[$0..<min($0 + 7, visitedFlagEmojis.count)])
                                }
                                ForEach(rows.indices, id: \.self) { i in
                                    HStack(spacing: 2) {
                                        ForEach(rows[i], id: \.self) { flag in
                                            FlagLabel(emoji: flag, size: 22)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 240, alignment: .center)
                            .padding(.horizontal, 4)
                        }
                        .frame(height: 260)
                        Button { withAnimation(.easeInOut(duration: 0.2)) { showVisitedFlags = false } } label: {
                            Text("Cerrar")
                                .font(.palatino(.body, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 10)
                                .background(Color.blue, in: Capsule())
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 340)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20))
                    .shadow(radius: 20)
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showVisitedFlags)
        .sheet(isPresented: $showLogros) {
            LogrosSheet(
                firstTrip: firstTrip,
                firstLayoverTrip: firstLayoverTrip,
                trip100: trip100,
                firstMicroestadoTrip: firstMicroestadoTrip,
                features: allFeatures,
                pastTrips: cachedPastTrips,
                visitedIsoCodes: visitedIsoCodes
            ) { kind in isAchieved(kind) }
        }
        .presentationDetents([.fraction(0.70)])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(colorTheme.isDarkMode ? .dark : .light)
        .onAppear { refreshProfileCaches() }
        .onChange(of: multiContinentRaw) { _, _ in
            multiContinentAssignments = (try? JSONDecoder().decode([String: String].self, from: Data(multiContinentRaw.utf8))) ?? [:]
        }
        .onChange(of: multiHemisphereRaw) { _, _ in
            multiHemisphereAssignments = (try? JSONDecoder().decode([String: String].self, from: Data(multiHemisphereRaw.utf8))) ?? [:]
        }
        .onChange(of: mapQuadrantsData) { _, _ in
            allPassportQuadrants = (try? JSONDecoder().decode([String: [MapQuadrant]].self, from: Data(mapQuadrantsData.utf8))) ?? [:]
        }
        .onChange(of: earnedPassportRaw) { _, _ in
            earnedPassportZones = (try? JSONDecoder().decode(Set<String>.self, from: Data(earnedPassportRaw.utf8))) ?? []
        }
        .onChange(of: trips.count) { _, _ in refreshPastTripsCache() }
    }

    private func refreshProfileCaches() {
        multiContinentAssignments = (try? JSONDecoder().decode([String: String].self, from: Data(multiContinentRaw.utf8))) ?? [:]
        multiHemisphereAssignments = (try? JSONDecoder().decode([String: String].self, from: Data(multiHemisphereRaw.utf8))) ?? [:]
        allPassportQuadrants = (try? JSONDecoder().decode([String: [MapQuadrant]].self, from: Data(mapQuadrantsData.utf8))) ?? [:]
        earnedPassportZones = (try? JSONDecoder().decode(Set<String>.self, from: Data(earnedPassportRaw.utf8))) ?? []
        refreshPastTripsCache()
    }

    private func refreshPastTripsCache() {
        let today = Calendar.current.startOfDay(for: Date())
        cachedPastTrips = trips.filter { Calendar.current.startOfDay(for: $0.dateFrom) <= today }
    }
}

// MARK: - Logros
struct LogrosSheet: View {
    let firstTrip: Trip?
    let firstLayoverTrip: Trip?
    let trip100: Trip?
    let firstMicroestadoTrip: Trip?
    let features: [CountryFeature]
    let pastTrips: [Trip]
    let visitedIsoCodes: Set<String>
    let isAchieved: (AchievementKind) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selectedKind: AchievementKind? = nil

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = Locale(identifier: "es")
        return f
    }()

    private func tripDateStr(_ trip: Trip) -> String {
        let start = Self.dateFmt.string(from: trip.dateFrom)
        if let end = trip.dateTo, end != trip.dateFrom {
            return "\(start) – \(Self.dateFmt.string(from: end))"
        }
        return start
    }

    private func lastTripDate(for kind: AchievementKind) -> Date {
        switch kind {
        case .firstTrip:         return firstTrip?.effectiveEndDate ?? .distantPast
        case .firstLayover:      return firstLayoverTrip?.effectiveEndDate ?? .distantPast
        case .trips100:          return trip100?.effectiveEndDate ?? .distantPast
        case .primerMicroestado: return firstMicroestadoTrip?.dateFrom ?? .distantPast
        case .allWorld, .ambosHemisferios, .todosLosContinentes:
            return pastTrips.map { $0.effectiveEndDate }.max() ?? .distantPast
        default:
            let isoCodes = kind.zoneIsoCodes.isEmpty ? kind.regionIsoCodes : kind.zoneIsoCodes
            return pastTrips.filter { isoCodes.contains($0.isoCode) }
                .map { $0.effectiveEndDate }.max() ?? .distantPast
        }
    }

    private func timeAgo(from date: Date) -> String {
        let now = Date()
        let days = Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0
        if days < 30 { return days == 1 ? "Hace 1 día" : "Hace \(days) días" }
        let months = Calendar.current.dateComponents([.month], from: date, to: now).month ?? 0
        if months < 12 { return months == 1 ? "Hace 1 mes" : "Hace \(months) meses" }
        let years = Calendar.current.dateComponents([.year], from: date, to: now).year ?? 0
        return years == 1 ? "Hace 1 año" : "Hace \(years) años"
    }

    @ViewBuilder
    private func tripToastContent(_ trip: Trip) -> some View {
        VStack(spacing: 4) {
            let flag = features.first(where: { $0.isoCode == trip.isoCode })?.flagEmoji ?? "🌐"
            let name = features.first(where: { $0.isoCode == trip.isoCode })?.localizedName ?? trip.isoCode
            HStack(spacing: 6) {
                FlagLabel(emoji: flag, size: 17)
                Text(name).font(.palatino(.headline))
            }
            if let title = trip.title {
                Text(title).font(.palatino(.subheadline)).foregroundStyle(.secondary)
            }
            Text(tripDateStr(trip)).font(.palatino(.caption)).foregroundStyle(.secondary)
            Text(timeAgo(from: trip.dateFrom))
                .font(.palatino(.caption, weight: .bold))
                .foregroundStyle(.blue)
        }
    }

    private func regionTripCount(_ kind: AchievementKind) -> Int {
        pastTrips.filter { kind.regionIsoCodes.contains($0.isoCode) }.count
    }
    private func regionVisitedCount(_ kind: AchievementKind) -> Int {
        visitedIsoCodes.intersection(kind.regionIsoCodes).count
    }
    private func visitedRegionDetail(_ kind: AchievementKind) -> some View {
        VStack(spacing: 4) {
            Text("\(regionVisitedCount(kind)) territorios en \(kind.regionName)")
                .font(.palatino(.subheadline, weight: .bold))
            Text("¡Lo conseguiste!")
                .font(.palatino(.caption))
                .foregroundStyle(.secondary)
        }
    }
    private func fiveTripsDetail(_ kind: AchievementKind) -> some View {
        VStack(spacing: 4) {
            Text("\(regionTripCount(kind)) viajes en \(kind.regionName)")
                .font(.palatino(.subheadline, weight: .bold))
            Text("¡Lo conseguiste!")
                .font(.palatino(.caption))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func achievementDetail(_ kind: AchievementKind) -> some View {
        switch kind {
        case .firstTrip:
            if let trip = firstTrip { tripToastContent(trip) }
        case .firstLayover:
            if let trip = firstLayoverTrip { tripToastContent(trip) }
        case .primerMicroestado:
            if let trip = firstMicroestadoTrip { tripToastContent(trip) }
        case .trips100:
            if let trip = trip100 { tripToastContent(trip) }
        case .allWorld:
            VStack(spacing: 4) {
                Text("¡Has visitado el mundo entero!")
                    .font(.palatino(.subheadline, weight: .bold))
                Text("Logro legendario")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
        case .visitedAntarctica:
            VStack(spacing: 4) {
                Text("¡Has pisado la Antártida!")
                    .font(.palatino(.subheadline, weight: .bold))
                Text("El continente más inhóspito del planeta")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
        case .visitedNortamerica:   visitedRegionDetail(kind)
        case .visitedCaribe:        visitedRegionDetail(kind)
        case .visitedSudamerica:    visitedRegionDetail(kind)
        case .visitedCentroamerica: visitedRegionDetail(kind)
        case .visitedAfrica:        visitedRegionDetail(kind)
        case .visitedEuropa:        visitedRegionDetail(kind)
        case .visitedMedioOriente:  visitedRegionDetail(kind)
        case .visitedOceania:       visitedRegionDetail(kind)
        case .visitedAsia:          visitedRegionDetail(kind)
        case .fiveEurope:           fiveTripsDetail(kind)
        case .fiveAsia:             fiveTripsDetail(kind)
        case .fiveAfrica:           fiveTripsDetail(kind)
        case .fiveMedioOriente:     fiveTripsDetail(kind)
        case .fiveOceania:          fiveTripsDetail(kind)
        case .fiveNortamerica:      fiveTripsDetail(kind)
        case .fiveCaribe:           fiveTripsDetail(kind)
        case .fiveSudamerica:       fiveTripsDetail(kind)
        case .fiveCentroamerica:    fiveTripsDetail(kind)
        case .europaCompleta, .asiaCompleta, .medioOrienteCompleto,
             .africaCompleta, .americaCompleta, .oceaniaCompleta:
            VStack(spacing: 4) {
                Text("¡Logro extraordinario!")
                    .font(.palatino(.subheadline, weight: .bold))
                Text("Has visitado todos los territorios de la zona")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
        case .todaLaUE:
            VStack(spacing: 4) {
                Text("¡Todos los países de la UE!")
                    .font(.palatino(.subheadline, weight: .bold))
                Text("Has visitado los 27 estados miembros")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
        case .todosEslavos:
            VStack(spacing: 4) {
                Text("¡Todos los pueblos eslavos!")
                    .font(.palatino(.subheadline, weight: .bold))
                Text("Has visitado los 13 países de habla eslava")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
        case .todosEscandinavos:
            VStack(spacing: 4) {
                Text("¡Escandinavia completa!")
                    .font(.palatino(.subheadline, weight: .bold))
                Text("Has visitado los 5 países nórdicos")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
        case .todosBalcanicos:
            VStack(spacing: 4) {
                Text("¡Los Balcanes completos!")
                    .font(.palatino(.subheadline, weight: .bold))
                Text("Has visitado todos los países balcánicos")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
        case .todosMicroestados:
            VStack(spacing: 4) {
                Text("¡Todos los microestados europeos!")
                    .font(.palatino(.subheadline, weight: .bold))
                Text("Andorra, Liechtenstein, Malta, Mónaco, San Marino y Vaticano")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
        case .ambosHemisferios:
            VStack(spacing: 4) {
                Text("¡Norte y sur del planeta!")
                    .font(.palatino(.subheadline, weight: .bold))
                Text("Has estado en ambos hemisferios")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
        case .todosLosContinentes:
            VStack(spacing: 4) {
                Text("¡Los 5 continentes!")
                    .font(.palatino(.subheadline, weight: .bold))
                Text("Europa, Asia, África, América y Oceanía")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
        case .pasaporteEuropa, .pasaporteAsia, .pasaporteMedioOriente,
             .pasaporteAfrica, .pasaporteAmerica, .pasaporteOceania:
            VStack(spacing: 4) {
                Text("¡Pasaporte completo!")
                    .font(.palatino(.subheadline, weight: .bold))
                Text("Has visitado todos los países de tu pasaporte")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                let achievedKinds = AchievementKind.allCases.filter { isAchieved($0) }.sorted { a, b in
                    if a.medalOrder != b.medalOrder { return a.medalOrder < b.medalOrder }
                    return lastTripDate(for: a) > lastTripDate(for: b)
                }
                let pendingKinds = AchievementKind.allCases.filter { !isAchieved($0) }
                    .sorted { $0.medalOrder < $1.medalOrder }
                ForEach(achievedKinds + pendingKinds, id: \.title) { kind in
                    let unlocked = isAchieved(kind)
                    Button {
                        if unlocked { selectedKind = kind }
                    } label: {
                        HStack(spacing: 12) {
                            Text(kind.medal)
                                .font(.title2)
                                .grayscale(unlocked ? 0 : 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title)
                                    .font(.palatino(.body))
                                    .foregroundStyle(unlocked ? .primary : .secondary)
                                if !unlocked {
                                    Text("Aún no conseguido")
                                        .font(.palatino(.caption))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            if unlocked {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .opacity(unlocked ? 1 : 0.5)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Logros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                        .font(.palatino(.body))
                }
            }
            .overlay {
                if let kind = selectedKind {
                    ZStack {
                        Color.black.opacity(0.45).ignoresSafeArea()
                        VStack(spacing: 14) {
                            Text(kind.medal).font(.system(size: 60))
                            Text(kind.title)
                                .font(.palatino(.title3, weight: .bold))
                                .multilineTextAlignment(.center)
                            achievementDetail(kind)
                            Button { selectedKind = nil } label: {
                                Text("Cerrar")
                                    .font(.palatino(.body, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(.white)
                            }
                            .padding(.top, 4)
                        }
                        .padding(24)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal, 32)
                        .shadow(radius: 20)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedKind != nil)
        }
        .appColorScheme()
    }
}

// MARK: - Pantalla de ajustes
struct SettingsSheet: View {
    @Binding var username: String
    @Binding var selectedPassport: String
    @Binding var countingModeRaw: String
    @Binding var menuPositionRaw: String
    @Binding var showBucketList: Bool
    @AppStorage("showCountdown") private var showCountdown: Bool = true
    var onClearStatus: (CountryStatus) -> Void = { _ in }

    @State private var pendingClear: CountryStatus? = nil
    @State private var showWipeConfirm: Bool = false
    @State private var showWipeFinalConfirm: Bool = false
    @State private var isWiping: Bool = false
    @State private var showWipeDoneToast: Bool = false
    @State private var showExportSheet: Bool = false
    @State private var exportFileURL: URL? = nil
    @State private var showImagePicker: Bool = false
    @State private var usernameDraft: String = ""
    @FocusState private var usernameFocused: Bool
    @State private var showContact: Bool = false
    @State private var showMultiContinent: Bool = false
    @State private var showMultiHemisphere: Bool = false

    @EnvironmentObject private var colorTheme: ColorThemeManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var showCountingToast: Bool = false
    @State private var showResetToast: Bool = false
    @State private var showFavoriteAirportPicker: Bool = false
    @State private var showSubscription: Bool = false
    @State private var showFAQ: Bool = false
    @State private var showNovedades: Bool = false
    @State private var showWidgetLockScreen: Bool = false
    @State private var showWidgetHome: Bool = false
    @State private var showWidgetWatch: Bool = false
    @State private var showLegalPrivacy: Bool = false
    @State private var showLegalTerms: Bool = false
    @State private var showLegalImprint: Bool = false
    @State private var showLegalGDPR: Bool = false
    @State private var showLegalCredits: Bool = false
    @AppStorage("isRaskmapPro") private var isRaskmapPro: Bool = false
    @AppStorage("raskmapProPlanID") private var raskmapProPlanID: String = ""
    @AppStorage("raskmapProByCode") private var raskmapProByCode: Bool = false
    @AppStorage("appFontFamily") private var appFontFamily: String = "satoshi"
    @State private var proCodeDraft: String = ""
    @State private var proCodeError: Bool = false
    @AppStorage("widgetBgColorHex") private var widgetBgColorHex: String = "#EE6E7D"
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled: Bool = false
    @AppStorage("tripRemindersEnabled") private var tripRemindersEnabled: Bool = false
    @AppStorage("multiHemisphereRaw") private var multiHemisphereRaw: String = "{}"

    @AppStorage("favoriteAirport") private var favoriteAirport: String = ""

    @State private var pendingVisitedColor: Color = ColorThemeManager.defaultVisited
    @State private var pendingWantToVisitColor: Color = ColorThemeManager.defaultWantToVisit
    @State private var pendingBucketListColor: Color = ColorThemeManager.defaultBucketList
    @State private var isApplyingColors: Bool = false

    private var countingMode: CountingMode { CountingMode(rawValue: countingModeRaw) ?? .all }

    @ViewBuilder private var proCodeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.caption)
                .foregroundStyle(.purple.opacity(0.6))
            TextField("Código de activación", text: $proCodeDraft)
                .font(.palatino(.body))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: proCodeDraft) { _, _ in proCodeError = false }
            if proCodeError {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            Button("Activar") { activateProCode() }
                .font(.palatino(.footnote, weight: .bold))
                .foregroundStyle(proCodeDraft.isEmpty ? Color.secondary : Color.purple)
                .disabled(proCodeDraft.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func activateProCode() {
        if proCodeDraft.lowercased().trimmingCharacters(in: .whitespaces) == "alexelcapo" {
            isRaskmapPro = true
            raskmapProPlanID = raskmapProLifetimeID
            raskmapProByCode = true
            proCodeDraft = ""
            proCodeError = false
        } else {
            proCodeError = true
        }
    }

    @ViewBuilder private var proRowLabel: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "crown.fill").font(.system(size: 13)).foregroundStyle(.purple)
                Text("Raskmap Pro").font(.palatino(.body, weight: .bold)).foregroundStyle(.purple)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.purple.opacity(0.5))
        }
        .padding(.horizontal, 16).padding(.vertical, 14).contentShape(Rectangle())
    }

    @ViewBuilder private func settingsRowLocked(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: isRaskmapPro ? action : { showSubscription = true }) {
            HStack {
                Label(label, systemImage: icon)
                    .font(.palatino(.body))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isRaskmapPro ? "chevron.right" : "lock.fill")
                    .font(.caption)
                    .foregroundStyle(isRaskmapPro ? Color.secondary : Color.purple)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func settingsRow(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(label, systemImage: icon)
                    .font(.palatino(.body))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var favoriteAirportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selecciona tu aeropuerto favorito:")
                .font(.palatino(.subheadline, weight: .bold))
                .foregroundStyle(.secondary)
            Button { showFavoriteAirportPicker = true } label: {
                HStack {
                    if favoriteAirport.isEmpty {
                        Text("Ninguno")
                            .font(.palatino(.body))
                            .foregroundStyle(.secondary)
                    } else {
                        let apData = RoutePickerSheet.allAirports.first { $0.iata == favoriteAirport }
                        let apLabel = "\(favoriteAirport)\(apData.map { " – \($0.name)" } ?? "")"
                        HStack(spacing: 8) {
                            FlagLabel(emoji: apData?.flagEmoji ?? "🌐", size: 17)
                            Text("⭐️").font(.caption)
                            Text(apLabel)
                                .font(.palatino(.body))
                                .foregroundStyle(.primary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder private var colorPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Colores del mapa:")
                .font(.palatino(.subheadline, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            ZStack {
                VStack(spacing: 12) {
                    VStack(spacing: 0) {
                        ColorPickerRow(label: "Visitado", color: $pendingVisitedColor)
                        Divider().padding(.leading, 56)
                        ColorPickerRow(label: "Quiero", color: $pendingBucketListColor)
                        Divider().padding(.leading, 56)
                        ColorPickerRow(label: "Próximo", color: $pendingWantToVisitColor)
                    }
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)
                    Button {
                        colorTheme.visitedColor = pendingVisitedColor
                        colorTheme.wantToVisitColor = pendingWantToVisitColor
                        colorTheme.bucketListColor = pendingBucketListColor
                        isApplyingColors = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            isApplyingColors = false
                        }
                    } label: {
                        Text("Cambiar colores")
                            .font(.palatino(.body, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 24)
                    .disabled(isApplyingColors)
                    Button {
                        pendingVisitedColor = ColorThemeManager.defaultVisited
                        pendingWantToVisitColor = ColorThemeManager.defaultWantToVisit
                        pendingBucketListColor = ColorThemeManager.defaultBucketList
                        colorTheme.resetToDefaults()
                        isApplyingColors = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            isApplyingColors = false
                        }
                    } label: {
                        Text("Restablecer colores predeterminados")
                            .font(.palatino(.footnote, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(Color.red, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 24)
                    .disabled(isApplyingColors)
                }
                .blur(radius: isRaskmapPro ? 0 : 6)
                .allowsHitTesting(isRaskmapPro)
                if !isRaskmapPro {
                    Button { showSubscription = true } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.purple)
                            Text("Función Pro")
                                .font(.palatino(.caption, weight: .bold))
                                .foregroundStyle(.purple)
                        }
                        .frame(maxWidth: .infinity, minHeight: 110)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {

                    // Perfil: foto + nombre
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 16) {
                            Button { showImagePicker = true } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    PassportAvatarView(key: selectedPassport, height: 86)
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.blue)
                                        .background(Color(.systemBackground), in: Circle())
                                        .offset(x: 4, y: 4)
                                }
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Nombre de usuario")
                                    .font(.palatino(.caption, weight: .bold))
                                    .foregroundStyle(.secondary)
                                ZStack(alignment: .leading) {
                                    HStack(spacing: 2) {
                                        Text("@")
                                            .font(.palatino(.body, weight: .bold))
                                            .foregroundStyle(.secondary)
                                        Text(usernameDraft.isEmpty ? "usuario" : usernameDraft)
                                            .font(.palatino(.body))
                                            .foregroundStyle(usernameDraft.isEmpty ? .tertiary : .primary)
                                        Button { usernameFocused = true } label: {
                                            Image(systemName: "pencil")
                                                .font(.callout)
                                                .foregroundStyle(.blue)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(10)
                                    .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
                                    TextField("", text: $usernameDraft)
                                        .font(.palatino(.body))
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                        .focused($usernameFocused)
                                        .opacity(usernameFocused ? 1 : 0.01)
                                        .padding(10)
                                        .background(usernameFocused ? Color(.systemGray5) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                                        .onChange(of: usernameDraft) {
                                            usernameDraft = String(usernameDraft.filter { $0.isLetter || $0.isNumber }.prefix(10))
                                        }
                                }
                                Text("Máx. 10 caracteres alfanuméricos")
                                    .font(.palatino(.caption))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    // ── Raskmap Pro ──
                    if raskmapProPlanID != raskmapProLifetimeID {
                        VStack(spacing: 10) {
                            Button { showSubscription = true } label: { proRowLabel }
                                .buttonStyle(.plain)
                            proCodeRow
                        }
                        .padding(.horizontal, 24)
                    } else {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.purple.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.purple)
                            }
                            Text("Raskmap Pro")
                                .font(.palatino(.body, weight: .bold))
                                .foregroundStyle(.purple)
                            Spacer()
                            Text("Vitalicio ✓")
                                .font(.palatino(.footnote))
                                .foregroundStyle(.purple.opacity(0.7))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(Color.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 24)
                    }

                    // Aeropuerto favorito
                    favoriteAirportSection

                    // Conteo de territorios
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Conteo de territorios/países:")
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 6) {
                            ForEach(CountingMode.allCases, id: \.self) { mode in
                                let isSelected = countingMode == mode
                                Button {
                                    countingModeRaw = mode.rawValue
                                    showCountingToast = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        showCountingToast = false
                                    }
                                } label: {
                                    Text(mode.label)
                                        .font(.custom(isSelected ? "Satoshi-Bold" : "Satoshi-Regular", size: 13))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(
                                            isSelected
                                                ? Color(red: 0x53/255, green: 0xA3/255, blue: 0xFE/255)
                                                : Color(.systemGray5),
                                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        )
                                        .foregroundStyle(isSelected ? .white : .primary)
                                }
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                            }
                        }
                        VStack(spacing: 8) {
                            Button { showMultiContinent = true } label: {
                                HStack {
                                    Text("Países en más de un continente")
                                        .font(.palatino(.body))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button { showMultiHemisphere = true } label: {
                                HStack {
                                    Text("Países en más de un hemisferio")
                                        .font(.palatino(.body))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)

                    // Contador próximo viaje
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Contador próximo viaje:")
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.secondary)
                        VStack(spacing: 0) {
                            HStack(spacing: 10) {
                                Image(systemName: "calendar.badge.clock")
                                    .foregroundStyle(.primary)
                                    .frame(width: 20)
                                Text("Mostrar contador")
                                    .font(.palatino(.body))
                                Spacer()
                                ZStack {
                                    Toggle("", isOn: $showCountdown)
                                        .labelsHidden()
                                        .tint(.blue)
                                        .blur(radius: isRaskmapPro ? 0 : 6)
                                        .allowsHitTesting(isRaskmapPro)
                                    if !isRaskmapPro {
                                        Button { showSubscription = true } label: {
                                            Image(systemName: "lock.fill")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(.purple)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            Rectangle().fill(Color(.separator)).frame(height: 0.5).padding(.leading, 16)
                            HStack {
                                Label("Live Activities", systemImage: "dot.radiowaves.left.and.right")
                                    .font(.palatino(.body))
                                    .foregroundStyle(.primary)
                                Spacer()
                                ZStack {
                                    Toggle("", isOn: $liveActivityEnabled)
                                        .labelsHidden()
                                        .tint(.blue)
                                        .blur(radius: isRaskmapPro ? 0 : 6)
                                        .allowsHitTesting(isRaskmapPro)
                                    if !isRaskmapPro {
                                        Button { showSubscription = true } label: {
                                            Image(systemName: "lock.fill")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(.purple)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                            Rectangle().fill(Color(.separator)).frame(height: 0.5).padding(.leading, 16)
                            // Recordatorios de viaje (notificaciones locales) — gratis.
                            HStack {
                                Label("Recordatorios de viaje", systemImage: "bell")
                                    .font(.palatino(.body))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Toggle("", isOn: $tripRemindersEnabled)
                                    .labelsHidden()
                                    .tint(.blue)
                                    .onChange(of: tripRemindersEnabled) { _, enabled in
                                        Task {
                                            if enabled {
                                                let granted = await TripNotifications.requestAuthorization()
                                                if !granted {
                                                    await MainActor.run { tripRemindersEnabled = false }
                                                }
                                            } else {
                                                TripNotifications.cancelAll()
                                            }
                                        }
                                    }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                        Text("Si activas los recordatorios, recibirás avisos 7 días antes, el día anterior y el día del viaje.")
                            .font(.palatino(.caption))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 24)

                    // Selección de colores
                    colorPickerSection

                    // Widgets
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Widgets")
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            settingsRow(label: "Pantalla principal", icon: "rectangle.grid.3x2") { showWidgetHome = true }
                            Rectangle().fill(Color(.separator)).frame(height: 0.5).padding(.leading, 16)
                            settingsRowLocked(label: "Pantalla de bloqueo", icon: "lock.display") { showWidgetLockScreen = true }
                            Rectangle().fill(Color(.separator)).frame(height: 0.5).padding(.leading, 16)
                            settingsRowLocked(label: "Apple Watch", icon: "applewatch") { showWidgetWatch = true }
                        }
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 24)

                    // Ayuda
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ayuda")
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            settingsRow(label: "Contacto", icon: "envelope") { showContact = true }
                            Divider().padding(.leading, 16)
                            settingsRow(label: "FAQ", icon: "questionmark.circle") { showFAQ = true }
                            Divider().padding(.leading, 16)
                            settingsRow(label: "Novedades", icon: "sparkles") { showNovedades = true }
                            Divider().padding(.leading, 16)
                            Button {
                                let appURL = URL(string: "instagram://user?username=jaimeviajando")!
                                let webURL = URL(string: "https://instagram.com/jaimeviajando")!
                                if UIApplication.shared.canOpenURL(appURL) {
                                    UIApplication.shared.open(appURL)
                                } else {
                                    UIApplication.shared.open(webURL)
                                }
                            } label: {
                                HStack {
                                    Label("Instagram", systemImage: "camera")
                                        .font(.palatino(.body))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("@jaimeviajando")
                                        .font(.palatino(.footnote))
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 24)

                    // Legal
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Legal")
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            settingsRow(label: "Política de privacidad", icon: "lock.shield") { showLegalPrivacy = true }
                            Divider().padding(.leading, 16)
                            settingsRow(label: "Términos de uso", icon: "doc.text") { showLegalTerms = true }
                            Divider().padding(.leading, 16)
                            settingsRow(label: "Aviso legal", icon: "building.columns") { showLegalImprint = true }
                            Divider().padding(.leading, 16)
                            settingsRow(label: "Tus derechos (RGPD)", icon: "person.badge.shield.checkmark") { showLegalGDPR = true }
                            Divider().padding(.leading, 16)
                            settingsRow(label: "Atribuciones", icon: "text.badge.checkmark") { showLegalCredits = true }
                        }
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 24)

                    // ── Datos: export + wipe (App Store / GDPR Art. 17/20) ──
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Datos")
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            // Exportar (GDPR Art. 20 — portabilidad)
                            Button {
                                showExportSheet = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.blue)
                                        .frame(width: 24)
                                    Text("Exportar mis datos")
                                        .font(.palatino(.body))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 52)
                            // Borrar (GDPR Art. 17 — derecho al olvido)
                            Button {
                                showWipeConfirm = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.red)
                                        .frame(width: 24)
                                    Text("Borrar todos mis datos")
                                        .font(.palatino(.body))
                                        .foregroundStyle(.red)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                        Text("Exportar genera un JSON con tus países, viajes y preferencias para que puedas guardarlo o moverlo a otro dispositivo. Borrar elimina todo localmente; con iCloud activo, también se sincroniza el borrado.")
                            .font(.palatino(.caption))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 24)

                    #if DEBUG
                    // ── Dev: simular planes Pro ──
                    VStack(spacing: 4) {
                        Toggle(isOn: Binding(
                            get: { raskmapProPlanID == raskmapProLifetimeID && !raskmapProByCode },
                            set: { active in
                                isRaskmapPro = active
                                raskmapProPlanID = active ? raskmapProLifetimeID : ""
                                if active { raskmapProByCode = false }
                            }
                        )) {
                            HStack(spacing: 8) {
                                Image(systemName: "wrench.and.screwdriver").foregroundStyle(.orange)
                                Text("Simular Pro vitalicio (DEV)")
                                    .font(.palatino(.footnote, weight: .bold)).foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 4)
                    #endif

                    Color.clear.frame(height: 32)
                }
                .padding(.top, 20)
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") {
                        let clean = String(usernameDraft.filter { $0.isLetter || $0.isNumber }.prefix(10))
                        if !clean.isEmpty { username = clean }
                        dismiss()
                    }
                    .font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        colorTheme.isDarkMode.toggle()
                    } label: {
                        Image(systemName: colorTheme.isDarkMode ? "sun.max" : "moon")
                            .font(.body)
                    }
                }
            }
            .onAppear { usernameDraft = username }
            .alert("¿Eliminar datos?", isPresented: Binding(
                get: { pendingClear != nil },
                set: { if !$0 { pendingClear = nil } }
            )) {
                Button("Eliminar", role: .destructive) {
                    if let status = pendingClear {
                        if status == .bucketList { showBucketList = false }
                        onClearStatus(status)
                    }
                    pendingClear = nil
                }
                Button("Cancelar", role: .cancel) {
                    pendingClear = nil
                }
            } message: {
                Text("Se eliminarán todos los países de Bucket list. Esta acción no se puede deshacer.")
            }
            .sheet(isPresented: $showExportSheet) {
                ExportDataSheet(
                    countriesProvider: { fetchAllCountries() },
                    tripsProvider: { fetchAllTrips() }
                )
            }
            // Wipe completo (App Store / GDPR): paso 1 — aviso, paso 2 — confirmación final.
            .alert("¿Borrar todos tus datos?", isPresented: $showWipeConfirm) {
                Button("Continuar", role: .destructive) { showWipeFinalConfirm = true }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Vas a borrar TODOS los países, viajes, premios, listas y preferencias. Esta acción no se puede deshacer.")
            }
            .alert("Confirmación final", isPresented: $showWipeFinalConfirm) {
                Button("Sí, borrar todo", role: .destructive) {
                    Task { await wipeAllData() }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Última oportunidad. Si tienes iCloud activo los datos también se eliminarán de tu nube tras la siguiente sincronización.")
            }
            .overlay {
                if showCountingToast || showResetToast || showWipeDoneToast {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white)
                        Text(showWipeDoneToast ? "Datos borrados" :
                             (showCountingToast ? "Conteo actualizado" : "Colores restablecidos"))
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showCountingToast)
            .animation(.easeInOut(duration: 0.2), value: showResetToast)
            .animation(.easeInOut(duration: 0.2), value: showWipeDoneToast)
        }
        .fullScreenCover(isPresented: $showImagePicker) {
            PassportPickerSheet(selection: $selectedPassport)
        }
        .sheet(isPresented: $showContact) {
            ContactSheet(username: username)
        }
        .sheet(isPresented: $showMultiContinent) {
            MultiContinentSheet()
        }
        .sheet(isPresented: $showMultiHemisphere) {
            MultiHemisphereSheet()
        }
        .sheet(isPresented: $showFavoriteAirportPicker) {
            FavoriteAirportPickerSheet(selected: $favoriteAirport)
        }
        .sheet(isPresented: $showSubscription) {
            SubscriptionSheet()
        }
        .sheet(isPresented: $showFAQ) {
            SettingsInfoSheet(title: "FAQ", icon: "questionmark.circle", content: "Aquí irán las preguntas frecuentes sobre Raskmap.\n\nPróximamente.")
        }
        .sheet(isPresented: $showNovedades) {
            SettingsInfoSheet(title: "Novedades", icon: "sparkles", content: "Aquí aparecerán las novedades de cada versión de Raskmap.\n\nPróximamente.")
        }
        .sheet(isPresented: $showWidgetLockScreen) {
            WidgetLockScreenSheet()
        }
        .sheet(isPresented: $showWidgetHome) {
            WidgetHomeColorSheet()
        }
        .sheet(isPresented: $showWidgetWatch) {
            WidgetWatchSheet()
        }
        .fullScreenCover(isPresented: $showLegalPrivacy) {
            LegalInfoSheet(
                title: "Política de privacidad",
                icon: "lock.shield",
                content: "Raskmap no recopila ningún dato personal fuera de tu dispositivo.\n\nTodos tus datos (países visitados, viajes, aeropuertos y preferencias) se almacenan localmente en tu dispositivo mediante SwiftData. Si tienes iCloud activado, se sincronizan de forma privada a través de tu propia cuenta de iCloud utilizando CloudKit (Apple Inc.). El desarrollador no tiene acceso a estos datos en ningún momento.\n\nNo compartimos información con terceros. Raskmap no incluye herramientas de análisis, publicidad ni seguimiento de ningún tipo. No se utilizan cookies, identificadores publicitarios ni SDKs externos.\n\nLas compras dentro de la aplicación (Raskmap Pro) se procesan exclusivamente a través de la App Store. El desarrollador no recibe ni almacena datos de pago; Apple gestiona la transacción conforme a su propia Política de Privacidad.\n\nEdad mínima recomendada: 13 años. Raskmap no está dirigida a menores de 13 años y no recopila conscientemente datos de esta franja de edad.\n\nRetención de datos: tus datos permanecen en tu dispositivo y/o tu iCloud mientras tú quieras conservarlos. Puedes eliminarlos en cualquier momento desde la propia aplicación o desinstalándola y borrando los datos asociados en Ajustes → [tu nombre] → iCloud.\n\nDerecho a reclamar: si resides en la Unión Europea, puedes presentar una reclamación ante la autoridad de control competente. En España, la Agencia Española de Protección de Datos (AEPD) — www.aepd.es.\n\nResponsable del tratamiento: Jaime Fernández Arenas (España)\nContacto: raskmap_soporte@icloud.com\n\nFecha de última actualización: abril de 2026."
            )
        }
        .fullScreenCover(isPresented: $showLegalTerms) {
            LegalInfoSheet(
                title: "Términos de uso",
                icon: "doc.text",
                content: "El uso de Raskmap implica la aceptación de estos términos.\n\nRaskmap es una aplicación de uso personal para el registro de viajes. El contenido introducido por el usuario (países, viajes, rutas, notas y preferencias) es de su exclusiva propiedad y permanece en su dispositivo y/o su cuenta de iCloud.\n\nEdad mínima de uso: 13 años, o la edad mínima equivalente exigida por la legislación de tu país para aceptar un contrato.\n\nLicencia de uso: la aplicación se distribuye mediante la App Store de Apple y queda sujeta, salvo indicación en contrario, al Acuerdo de Licencia de Usuario Final estándar de Apple (Apple Licensed Application End User License Agreement), disponible en https://www.apple.com/legal/internet-services/itunes/dev/stdeula/\n\nCompras dentro de la aplicación: Raskmap Pro se ofrece como pago único (no es una suscripción con renovación automática). Las condiciones de compra y devolución se rigen por los Términos y Condiciones de Apple y por la política de reembolsos de la App Store.\n\nResponsabilidad: la aplicación se proporciona «tal cual», sin garantías de ningún tipo, expresas o implícitas. El desarrollador no se hace responsable de pérdidas de datos derivadas de fallos del dispositivo, del servicio iCloud o de cambios en el sistema operativo, ni de daños directos o indirectos derivados del uso de la aplicación, en la máxima medida permitida por la legislación aplicable.\n\nModificaciones: el desarrollador se reserva el derecho a modificar, añadir o retirar funcionalidades, así como a interrumpir el servicio, con previo aviso razonable a través de la App Store.\n\nLey aplicable: legislación española y normativa de la Unión Europea.\n\nFecha de última actualización: abril de 2026."
            )
        }
        .fullScreenCover(isPresented: $showLegalImprint) {
            LegalInfoSheet(
                title: "Aviso legal",
                icon: "building.columns",
                content: "Desarrollador y responsable de la aplicación:\n\nJaime Fernández Arenas (persona física, particular)\nEspaña\n\nContacto: raskmap_soporte@icloud.com\n\nRaskmap es una aplicación independiente desarrollada a título individual. No pertenece a ninguna empresa ni entidad jurídica y no desarrolla una actividad comercial sujeta a inscripción en registros mercantiles.\n\nDistribución: Raskmap se distribuye exclusivamente a través de la App Store de Apple (Apple Inc., One Apple Park Way, Cupertino, CA 95014, EE. UU.). El uso de la aplicación queda sujeto al Acuerdo de Licencia de Usuario Final estándar de Apple.\n\nPropiedad intelectual: el nombre «Raskmap», su logotipo, interfaz y contenidos originales son propiedad del desarrollador. Los contenidos y datos de terceros se reconocen en el apartado «Atribuciones».\n\nFecha de última actualización: abril de 2026."
            )
        }
        .fullScreenCover(isPresented: $showLegalGDPR) {
            LegalInfoSheet(
                title: "Tus derechos (RGPD)",
                icon: "person.badge.shield.checkmark",
                content: "Como usuario en la Unión Europea, el Reglamento General de Protección de Datos (RGPD — Reglamento UE 2016/679) te otorga los siguientes derechos:\n\n· Acceso: puedes consultar en cualquier momento todos tus datos directamente en la app.\n\n· Rectificación: puedes editar o corregir cualquier dato desde la propia aplicación.\n\n· Supresión: puedes eliminar cualquier viaje o país visitado desde la app. Para eliminar todos los datos puedes desinstalar la aplicación y borrar los datos de iCloud desde Ajustes → [tu nombre] → iCloud → Gestionar almacenamiento.\n\n· Portabilidad: tus datos residen en tu dispositivo y/o tu cuenta de iCloud y permanecen bajo tu control en todo momento.\n\n· Limitación del tratamiento: dado que todos los datos se procesan localmente en tu dispositivo, no existe tratamiento de datos por parte del desarrollador.\n\n· Oposición: dado que no tratamos datos con fines comerciales ni de análisis, este derecho no aplica en el contexto de Raskmap.\n\n· Reclamación ante la autoridad de control: tienes derecho a presentar una reclamación ante la autoridad de protección de datos competente. En España, la Agencia Española de Protección de Datos (AEPD) — www.aepd.es.\n\nRaskmap no realiza perfilado automatizado ni toma de decisiones automatizadas sobre los usuarios. El desarrollador no transfiere datos fuera del Espacio Económico Europeo; el almacenamiento en iCloud depende de tu configuración personal con Apple.\n\nResponsable del tratamiento: Jaime Fernández Arenas (España)\nContacto: raskmap_soporte@icloud.com\n\nFecha de última actualización: abril de 2026."
            )
        }
        .fullScreenCover(isPresented: $showLegalCredits) {
            LegalInfoSheet(
                title: "Atribuciones",
                icon: "text.badge.checkmark",
                content: "Raskmap utiliza los siguientes recursos de terceros:\n\n· Datos geográficos: Natural Earth (naturalearthdata.com). Dominio público. Los polígonos de países se obtienen de su dataset vectorial de libre uso.\n\n· Fuente tipográfica: Satoshi, diseñada por Deni Anggara y distribuida bajo licencia libre a través de Fontshare (Indian Type Foundry).\n\n· Datos de fronteras adicionales: geo-countries (github.com/datasets/geo-countries), Open Database License (ODbL).\n\n· Datos de aeropuertos IATA: recopilación propia basada en fuentes públicas.\n\n· Cartografía y tiles de mapa: MapKit y Apple Maps, © Apple Inc. y sus proveedores. Los créditos y enlaces legales correspondientes se muestran en el propio mapa.\n\n· Iconos de interfaz: SF Symbols, © Apple Inc. Uso sujeto a la licencia de SF Symbols de Apple.\n\n· Iconos de banderas: Twemoji, originalmente © Twitter Inc. / X Corp. y mantenido actualmente por la comunidad en github.com/jdecked/twemoji. Distribuido bajo licencia CC-BY 4.0 (creativecommons.org/licenses/by/4.0). Los gráficos de las banderas no han sido modificados.\n\n· Almacenamiento y sincronización: SwiftData y CloudKit, © Apple Inc.\n\n· Procesamiento de pagos y entrega: App Store / StoreKit, © Apple Inc.\n\nTodos los demás componentes de la aplicación son de desarrollo propio y no incorporan librerías de terceros.\n\nFecha de última actualización: abril de 2026."
            )
        }
        .overlay {
            if isApplyingColors {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(1.4)
                            .tint(.white)
                        Text("Actualizando colores…")
                            .font(.palatino(.body, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 32)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 20))
                }
            }
        }
        .onAppear {
            pendingVisitedColor = colorTheme.visitedColor
            pendingWantToVisitColor = colorTheme.wantToVisitColor
            pendingBucketListColor = colorTheme.bucketListColor
        }
        .appColorScheme()
    }

    private func fetchAllCountries() -> [Country] {
        modelContext.fetchOrWarn(FetchDescriptor<Country>())
    }
    private func fetchAllTrips() -> [Trip] {
        modelContext.fetchOrWarn(FetchDescriptor<Trip>())
    }

    /// Borra todos los datos persistidos del usuario (cumplimiento App Store
    /// y GDPR Art. 17 — derecho al olvido). Limpia SwiftData, AppStorage,
    /// cualquier preferencia local y el estado del widget en App Group.
    /// CloudKit se sincroniza automáticamente por @Query y borra remoto.
    private func wipeAllData() async {
        await MainActor.run {
            isWiping = true
            // 1) SwiftData
            do {
                try modelContext.delete(model: Trip.self)
                try modelContext.delete(model: Country.self)
                try modelContext.delete(model: PersonalAwardModel.self)
                try modelContext.save()
            } catch {
                #if DEBUG
                print("⚠️ Wipe SwiftData error: \(error)")
                #endif
            }
            // 2) AppStorage / UserDefaults estándar
            let defaults = UserDefaults.standard
            let keysToWipe: [String] = [
                "username", "didShowOnboarding", "didShowLocationToast",
                "showBucketList", "showCountdown",
                "topTable", "multiContinentRaw", "multiHemisphereRaw",
                "appFontFamily", "favoriteAirport", "isRaskmapPro", "raskmapProPlanID",
                "raskmapProByCode", "mapQuadrantsData", "didInsertDefaultQuadrants",
                "earnedPassportAchievementsRaw", "liveActivityEnabled", "neverShowReview",
                "selectedPassport", "personalList1Title", "personalList1Content",
                "personalList2Title", "personalList2Content",
                "subjectiveCategoriesTable", "subjectiveCategoriesOrder",
                "color_visited", "color_wantToVisit", "color_bucketList", "color_lived",
                "widgetBgColorHex", "menuPosition", "countingMode",
                "tripRemindersEnabled"
            ]
            for k in keysToWipe { defaults.removeObject(forKey: k) }
            // 3) App Group del widget
            if let store = UserDefaults(suiteName: "group.com.jaime.raskmap") {
                for key in store.dictionaryRepresentation().keys {
                    store.removeObject(forKey: key)
                }
            }
            // 4) Snapshot del mapa de vuelo en disco (si existe)
            if let url = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: "group.com.jaime.raskmap")?
                .appendingPathComponent("next_flight_map.png") {
                try? FileManager.default.removeItem(at: url)
            }
            // 5) Live Activities activas
            if #available(iOS 16.1, *) {
                Task { @MainActor in
                    for activity in Activity<RaskmapTripAttributes>.activities {
                        await activity.end(nil, dismissalPolicy: .immediate)
                    }
                }
            }
            // 6) Notificaciones locales
            TripNotifications.cancelAll()
            isWiping = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation { showWipeDoneToast = true }
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await MainActor.run {
            withAnimation { showWipeDoneToast = false }
            dismiss()
        }
    }
}

// MARK: - Notificaciones locales de viajes próximos
//
// Recordatorios automáticos: 7 días antes, 1 día antes y el día del viaje.
// El usuario debe haber concedido permiso (lo pedimos al activar el toggle
// en Ajustes). Las notificaciones se reprograman cuando cambian los trips.

enum TripNotifications {

    /// Pide permiso si aún no está concedido. Devuelve true si quedó concedido.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    /// Borra todos los recordatorios y los re-genera para los trips futuros del
    /// próximo año. Idempotente; llamar siempre que cambien los datos.
    static func reschedule(trips: [Trip], featuresByIso: [String: CountryFeature]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let now = Date()
        let oneYearFromNow = Calendar.current.date(byAdding: .year, value: 1, to: now) ?? now
        for trip in trips where !trip.isSegmentChild {
            let day = Calendar.current.startOfDay(for: trip.dateFrom)
            guard day > now, day < oneYearFromNow else { continue }
            schedule(trip: trip, featuresByIso: featuresByIso, daysBefore: 7)
            schedule(trip: trip, featuresByIso: featuresByIso, daysBefore: 1)
            schedule(trip: trip, featuresByIso: featuresByIso, daysBefore: 0)
        }
    }

    private static func schedule(trip: Trip, featuresByIso: [String: CountryFeature], daysBefore: Int) {
        let cal = Calendar.current
        guard let triggerDay = cal.date(byAdding: .day, value: -daysBefore, to: trip.dateFrom) else { return }
        // 9:00 AM hora local del día anterior al evento.
        var comps = cal.dateComponents([.year, .month, .day], from: triggerDay)
        comps.hour = 9; comps.minute = 0
        guard let when = cal.date(from: comps), when > Date() else { return }

        let countryName = featuresByIso[trip.isoCode]?.localizedName ?? trip.isoCode
        let flag = featuresByIso[trip.isoCode]?.flagEmoji ?? "✈️"
        let title: String
        let body: String
        switch daysBefore {
        case 0:
            title = "¡Hoy empieza tu viaje!"
            body = "\(flag) Buen viaje a \(countryName)"
        case 1:
            title = "Mañana viajas"
            body = "\(flag) Tu viaje a \(countryName) empieza mañana"
        case 7:
            title = "En una semana"
            body = "\(flag) Tu viaje a \(countryName) empieza en 7 días"
        default:
            title = "Próximo viaje"
            body = "\(flag) \(countryName)"
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: when), repeats: false)
        let id = "trip_\(trip.isoCode)_\(Int(trip.dateFrom.timeIntervalSince1970))_d\(daysBefore)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

// MARK: - Export de datos (GDPR Art. 20 portabilidad)
struct ExportDataSheet: View {
    let countriesProvider: () -> [Country]
    let tripsProvider: () -> [Trip]

    @Environment(\.dismiss) private var dismiss
    @State private var generatedURL: URL? = nil
    @State private var format: ExportFormat = .json
    @State private var isGenerating: Bool = false
    @State private var errorMessage: String? = nil

    enum ExportFormat: String, CaseIterable, Identifiable {
        case json = "JSON"
        case csv  = "CSV"
        var id: String { rawValue }
        var ext: String { rawValue.lowercased() }
        var description: String {
            switch self {
            case .json: return "Estructurado, completo (incluye segmentos y aerolíneas)"
            case .csv:  return "Tabular, una fila por viaje (compatible con Excel/Numbers)"
            }
        }
    }

    private let accent = Color(red: 64/255, green: 114/255, blue: 212/255)

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle().fill(accent.opacity(0.12)).frame(width: 44, height: 44)
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Exportar tus datos")
                            .font(.custom("Satoshi-Bold", size: 18))
                        Text("Genera un archivo con tus países, viajes y preferencias para guardarlo o moverlo.")
                            .font(.palatino(.subheadline))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)

                Text("FORMATO")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.0)
                    .padding(.horizontal, 24)

                VStack(spacing: 0) {
                    ForEach(ExportFormat.allCases) { f in
                        Button { format = f } label: {
                            HStack(spacing: 12) {
                                Image(systemName: format == f ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(format == f ? accent : Color(.systemGray3))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.rawValue).font(.custom("Satoshi-Bold", size: 15))
                                    Text(f.description).font(.palatino(.caption)).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if f != ExportFormat.allCases.last { Divider().padding(.leading, 50) }
                    }
                }
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)

                Button {
                    generateAndShare()
                } label: {
                    HStack(spacing: 8) {
                        if isGenerating { ProgressView().tint(.white) }
                        else { Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .semibold)) }
                        Text(isGenerating ? "Generando…" : "Generar y compartir")
                            .font(.custom("Satoshi-Bold", size: 15))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isGenerating)
                .padding(.horizontal, 20)

                if let err = errorMessage {
                    Text(err).font(.palatino(.caption)).foregroundStyle(.red)
                        .padding(.horizontal, 20)
                }
                Spacer()
            }
            .padding(.top, 12)
            .navigationTitle("Exportar datos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .appColorScheme()
    }

    private func generateAndShare() {
        isGenerating = true
        errorMessage = nil
        let countries = countriesProvider()
        let trips = tripsProvider()
        Task.detached(priority: .userInitiated) {
            do {
                let url = try Self.writeExport(format: format, countries: countries, trips: trips)
                await MainActor.run {
                    isGenerating = false
                    generatedURL = url
                    presentShare(url: url)
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = "No se pudo generar el archivo: \(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor
    private func presentShare(url: URL) {
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // Buscar el presenting view controller activo (sheet anidado).
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let key = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else { return }
        var top = key.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        top?.present(av, animated: true)
    }

    private static func writeExport(format: ExportFormat, countries: [Country], trips: [Trip]) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = tmp.appendingPathComponent("raskmap-export-\(stamp).\(format.ext)")
        let data: Data
        switch format {
        case .json: data = try buildJSON(countries: countries, trips: trips)
        case .csv:  data = buildCSV(trips: trips).data(using: .utf8) ?? Data()
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func buildJSON(countries: [Country], trips: [Trip]) throws -> Data {
        let dfISO = ISO8601DateFormatter()
        let countryDicts: [[String: Any]] = countries.map { c in
            [
                "isoCode": c.isoCode,
                "name": c.name,
                "status": c.statusRaw,
                "visitCount": c.visitCount,
                "hasLived": c.hasLived,
                "plannedDate": c.plannedDate.map { dfISO.string(from: $0) } ?? NSNull(),
                "plannedDateTo": c.plannedDateTo.map { dfISO.string(from: $0) } ?? NSNull(),
                "transport": c.transport ?? NSNull(),
                "plannedTitle": c.plannedTitle ?? NSNull()
            ]
        }
        let tripDicts: [[String: Any]] = trips.map { t in
            var dict: [String: Any] = [
                "isoCode": t.isoCode,
                "title": t.title ?? NSNull(),
                "dateFrom": dfISO.string(from: t.dateFrom),
                "dateTo": t.dateTo.map { dfISO.string(from: $0) } ?? NSNull(),
                "transport": t.transport ?? NSNull(),
                "hasLayover": t.hasLayover,
                "isSegmentChild": t.isSegmentChild,
                "segmentGroupID": t.segmentGroupID ?? NSNull(),
                "tripAirports": t.tripAirports.map { ["iata": $0.iata, "count": $0.count] },
                "tripAirlines": t.tripAirlines.map { ["name": $0.name, "count": $0.count] }
            ]
            // Segments embebidos (si hay).
            if !t.tripSegments.isEmpty {
                dict["segments"] = t.tripSegments.map { seg -> [String: Any] in
                    [
                        "transport": seg.transport,
                        "isoCodes": seg.isoCodes,
                        "dateFrom": dfISO.string(from: seg.dateFrom),
                        "dateTo": seg.dateTo.map { dfISO.string(from: $0) } ?? NSNull(),
                        "airports": (seg.airports ?? []).map { ["iata": $0.iata, "count": $0.count] },
                        "returnAirports": (seg.returnAirports ?? []).map { ["iata": $0.iata, "count": $0.count] },
                        "airlines": (seg.airlines ?? []).map { ["name": $0.name, "count": $0.count] },
                        "visitedLayoverISOs": seg.visitedLayoverISOs ?? []
                    ]
                }
            }
            return dict
        }
        let root: [String: Any] = [
            "app": "Raskmap",
            "exportedAt": dfISO.string(from: Date()),
            "version": 1,
            "countries": countryDicts,
            "trips": tripDicts
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    private static func buildCSV(trips: [Trip]) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        var lines: [String] = []
        lines.append("isoCode,title,dateFrom,dateTo,transport,airports,airlines,isSegmentChild")
        for t in trips {
            let title = t.title?.replacingOccurrences(of: ",", with: " ") ?? ""
            let airports = t.tripAirports.map { "\($0.iata)x\($0.count)" }.joined(separator: ";")
            let airlines = t.tripAirlines.map { "\($0.name.replacingOccurrences(of: ",", with: " "))x\($0.count)" }.joined(separator: ";")
            lines.append([
                t.isoCode,
                "\"\(title)\"",
                df.string(from: t.dateFrom),
                t.dateTo.map(df.string(from:)) ?? "",
                t.transport ?? "",
                "\"\(airports)\"",
                "\"\(airlines)\"",
                t.isSegmentChild ? "1" : "0"
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Contacto
struct MailComposerView: UIViewControllerRepresentable {
    let toRecipients: [String]
    let subject: String
    let body: String
    @Binding var isPresented: Bool
    var onFinish: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.setToRecipients(toRecipients)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        vc.mailComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposerView
        init(_ parent: MailComposerView) { self.parent = parent }
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            parent.isPresented = false
            parent.onFinish()
        }
    }
}

struct ContactSheet: View {
    let username: String
    @Environment(\.dismiss) private var dismiss
    @State private var messageText = ""
    @State private var showMailComposer = false
    @FocusState private var editorFocused: Bool

    private let maxChars = 600
    private let accent = Color(red: 64/255, green: 114/255, blue: 212/255)
    private var subject: String { "Solicitud de \(username.isEmpty ? "usuario" : username)" }
    private var trimmed: String { messageText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // Header con icono + texto
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle().fill(accent.opacity(0.12)).frame(width: 44, height: 44)
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(accent)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Escríbenos")
                                .font(.custom("Satoshi-Bold", size: 18))
                            Text("Cuéntanos qué falta o qué falla. Leemos cada mensaje.")
                                .font(.palatino(.subheadline))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                    // Recipient pill (read-only) — destinatario visible
                    HStack(spacing: 10) {
                        Text("PARA")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.0)
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .leading)
                        Text("raskmap_soporte@icloud.com")
                            .font(.custom("Satoshi-Medium", size: 14))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)

                    // Subject pill — asunto pre-rellenado
                    HStack(spacing: 10) {
                        Text("ASUNTO")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.0)
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        Text(subject)
                            .font(.custom("Satoshi-Medium", size: 14))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)

                    // Editor del mensaje — body
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MENSAJE")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.0)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(.systemGray6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(editorFocused ? accent.opacity(0.4) : Color.clear, lineWidth: 1.5)
                                )
                            if messageText.isEmpty {
                                Text("Hola, me gustaría reportar…\n\n· Bug encontrado:\n· Aeropuerto/aerolínea que falta:\n· Sugerencia:")
                                    .font(.palatino(.body))
                                    .foregroundStyle(Color(.placeholderText))
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $messageText)
                                .font(.palatino(.body))
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .focused($editorFocused)
                                .frame(minHeight: 200)
                                .onChange(of: messageText) { _, new in
                                    if new.count > maxChars { messageText = String(new.prefix(maxChars)) }
                                }
                        }
                        HStack {
                            Spacer()
                            Text("\(messageText.count)/\(maxChars)")
                                .font(.custom("Satoshi-Medium", size: 11))
                                .foregroundStyle(messageText.count >= maxChars ? .red : .secondary)
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 20)

                    // Botón Enviar
                    Button {
                        if MFMailComposeViewController.canSendMail() {
                            showMailComposer = true
                        } else {
                            // Encoding tight para mailto: query — `&`, `=`, `?`, `#` y `+`
                            // se reservan como separadores y rompen el parser del cliente
                            // de correo si aparecen sin codificar dentro del subject/body.
                            var allowed = CharacterSet.urlQueryAllowed
                            allowed.remove(charactersIn: "&=?#+")
                            let s = subject.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                            let b = messageText.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                            if let url = URL(string: "mailto:raskmap_soporte@icloud.com?subject=\(s)&body=\(b)") {
                                UIApplication.shared.open(url)
                                dismiss()
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "paperplane.fill").font(.system(size: 14, weight: .semibold))
                            Text("Enviar mensaje").font(.custom("Satoshi-Bold", size: 15))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(trimmed.isEmpty ? Color(.systemGray4) : accent,
                                    in: RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(trimmed.isEmpty)
                    .padding(.horizontal, 20)

                    Spacer(minLength: 24)
                }
                .padding(.top, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Contacto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
            .sheet(isPresented: $showMailComposer) {
                MailComposerView(
                    toRecipients: ["raskmap_soporte@icloud.com"],
                    subject: subject,
                    body: messageText,
                    isPresented: $showMailComposer,
                    onFinish: { dismiss() }
                )
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .appColorScheme()
    }
}

// MARK: - Info sheet genérica (FAQ, Novedades, Widgets)
// MARK: - Color hex helper

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int & 0xFF)          / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Widget home color picker

struct WidgetHomeColorSheet: View {
    @AppStorage("widgetBgColorHex") private var savedHex: String = "#EE6E7D"
    @State private var selectedHex: String = "#EE6E7D"
    @State private var isApplying: Bool = false
    @Environment(\.dismiss) private var dismiss

    private let palette: [(name: String, hex: String)] = [
        ("Rosa",      "#EE6E7D"),
        ("Azul",      "#53A3FE"),
        ("Verde mar", "#1ABC9C"),
        ("Morado",    "#9B59B6"),
        ("Naranja",   "#E67E22"),
        ("Verde",     "#27AE60"),
        ("Rojo",      "#C0392B"),
        ("Índigo",    "#3949AB"),
        ("Marino",    "#2C3E50"),
        ("Negro",     "#1C1C1E"),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Mini widget preview — layout idéntico al widget real (small)
                ZStack {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color(hex: selectedHex))
                        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
                    ZStack(alignment: .topLeading) {
                        Text("✈️")
                            .font(.system(size: 26))
                        Text("#ABC123")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text("🇯🇵").font(.system(size: 14))
                                Text("Viaje Tokio")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color(red: 0x53/255.0, green: 0xA3/255.0, blue: 0xFE/255.0))
                                    .lineLimit(1)
                            }
                            Text("42 días")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(.white)
                            Text("lun., 15 jun. 2026")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(15)
                }
                .frame(width: 160, height: 160)
                .padding(.top, 16)
                .animation(.easeInOut(duration: 0.2), value: selectedHex)

                // Color palette
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 18) {
                    ForEach(palette, id: \.hex) { item in
                        Button {
                            selectedHex = item.hex
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: item.hex))
                                    .frame(width: 52, height: 52)
                                    .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 2)
                                if selectedHex == item.hex {
                                    Circle()
                                        .strokeBorder(.white, lineWidth: 3)
                                        .frame(width: 52, height: 52)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 32)

                // Tamaños disponibles
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tamaños disponibles")
                        .font(.palatino(.footnote, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)

                    VStack(spacing: 0) {
                        ForEach([
                            ("square", "Pequeño", "Transporte, destino, días y fecha"),
                            ("rectangle.split.2x1", "Mediano", "Icono + destino con más detalle"),
                            ("square.grid.2x2", "Grande", "Próximo viaje, países visitados y próximos destinos")
                        ], id: \.1) { icon, size, desc in
                            HStack(spacing: 12) {
                                Image(systemName: icon)
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(size)
                                        .font(.palatino(.subheadline, weight: .bold))
                                    Text(desc)
                                        .font(.palatino(.caption))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            if size != "Grande" {
                                Divider().padding(.leading, 60)
                            }
                        }
                    }
                }

                Spacer()

                Button {
                    savedHex = selectedHex
                    WidgetDataWriter.syncColor(hex: selectedHex)
                    isApplying = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        isApplying = false
                        dismiss()
                    }
                } label: {
                    Text("Aceptar")
                        .font(.palatino(.body, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .disabled(isApplying)
            }
            .navigationTitle("Pantalla principal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
            .overlay {
                if isApplying {
                    ZStack {
                        Color.black.opacity(0.45).ignoresSafeArea()
                        VStack(spacing: 20) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(1.4)
                                .tint(.white)
                            Text("Aplicando color…")
                                .font(.palatino(.body, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .onAppear { selectedHex = savedHex }
        .appColorScheme()
    }
}

// MARK: - FlightInfoSection

struct FlightInfoSection: View {
    @Binding var info: FlightInfo
    /// Aeropuertos IATA de ida (orden). Si tiene N elementos → N-1 tramos.
    var outboundRoute: [String] = []
    /// Aeropuertos IATA de vuelta. Vacío = one-way. Si tiene N elementos → N-1 tramos.
    var returnRoute: [String] = []

    private let seatPositions: [(String, String)] = [("Pasillo", "pasillo"), ("Medio", "medio"), ("Ventana", "ventana")]
    private let classes: [(String, String)] = [("Turista", "turista"), ("Economy+", "economy+"), ("Business", "business"), ("First", "first")]
    private let accent = Color(red: 64/255, green: 114/255, blue: 212/255)

    private var outboundLegCount: Int { max(0, outboundRoute.count - 1) }
    private var returnLegCount: Int { max(0, returnRoute.count - 1) }
    private var totalLegCount: Int { outboundLegCount + returnLegCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DETALLES DEL VUELO")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1.0)
                .padding(.horizontal, 24)

            // Reserva — compartida (la misma PNR cubre todos los tramos)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 13)).foregroundStyle(accent).frame(width: 20)
                    Text("Reserva").font(.palatino(.body))
                    Spacer()
                    TextField("ABC123", text: $info.bookingRef)
                        .font(.custom("Satoshi-Bold", size: 15))
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .foregroundStyle(accent)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)

            if totalLegCount <= 0 {
                // Sin ruta → editor único ligado a los escalares legacy (compat con trips antiguos).
                legEditor(
                    title: nil,
                    seat: $info.seatNumber,
                    pos: $info.seatPosition,
                    cabin: $info.cabinClass
                )
            } else {
                // Cuando hay >1 tramos, ofrecemos un botón rápido "Aplicar a
                // todos" que copia la clase + posición + asiento del primer
                // tramo a TODOS los demás. Asiento exacto rara vez se repite,
                // pero clase/posición sí. El usuario puede luego ajustar
                // tramos individuales que difieran.
                if totalLegCount > 1, info.outboundLegs.first?.hasAnyData == true {
                    Button { applyFirstLegToAll() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Aplicar clase y posición a todos los tramos")
                                .font(.palatino(.caption, weight: .bold))
                        }
                        .foregroundStyle(accent)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(accent.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                }
                // Ida
                if outboundLegCount > 0 {
                    if outboundRoute.count > 2 || returnLegCount > 0 {
                        sectionLabel("IDA")
                    }
                    ForEach(Array(0..<outboundLegCount), id: \.self) { idx in
                        let showTitle = totalLegCount > 1
                        let title: String? = showTitle ? legTitle(route: outboundRoute, idx: idx) : nil
                        legEditor(
                            title: title,
                            seat: outboundBinding(\.seatNumber, idx: idx),
                            pos: outboundBinding(\.seatPosition, idx: idx),
                            cabin: outboundBinding(\.cabinClass, idx: idx)
                        )
                    }
                }
                // Vuelta
                if returnLegCount > 0 {
                    sectionLabel("VUELTA")
                    ForEach(Array(0..<returnLegCount), id: \.self) { idx in
                        let title: String? = legTitle(route: returnRoute, idx: idx)
                        legEditor(
                            title: title,
                            seat: returnBinding(\.seatNumber, idx: idx),
                            pos: returnBinding(\.seatPosition, idx: idx),
                            cabin: returnBinding(\.cabinClass, idx: idx)
                        )
                    }
                }
            }
        }
        .padding(.bottom, 12)
        .onAppear { migrateLegacyAndResize() }
        .onChange(of: outboundRoute) { _, _ in ensureLegsSized() }
        .onChange(of: returnRoute)   { _, _ in ensureLegsSized() }
    }

    // MARK: - Helpers

    private func legTitle(route: [String], idx: Int) -> String {
        guard route.indices.contains(idx), route.indices.contains(idx + 1) else { return "" }
        return "\(route[idx]) → \(route[idx + 1])"
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(accent.opacity(0.85))
            .tracking(0.8)
            .padding(.horizontal, 24)
            .padding(.top, 2)
    }

    /// Garantiza que `outboundLegs.count == outboundLegCount` y lo mismo para return.
    /// Se llama en onAppear y cuando cambia la ruta.
    /// Hace UN solo round-trip por @Binding para evitar que filtros aguas arriba
    /// (p.ej. el `hasAnyData ? newValue : nil` de `segmentFlightInfoBinding`) descarten
    /// estados intermedios donde los tramos están todavía "vacíos".
    private func ensureLegsSized() {
        var current = info
        var changed = false
        while current.outboundLegs.count < outboundLegCount { current.outboundLegs.append(FlightLegInfo()); changed = true }
        if current.outboundLegs.count > outboundLegCount {
            current.outboundLegs = Array(current.outboundLegs.prefix(outboundLegCount)); changed = true
        }
        while current.returnLegs.count < returnLegCount { current.returnLegs.append(FlightLegInfo()); changed = true }
        if current.returnLegs.count > returnLegCount {
            current.returnLegs = Array(current.returnLegs.prefix(returnLegCount)); changed = true
        }
        if changed { info = current }
    }

    /// Migra los escalares legacy al primer tramo disponible y los vacía, idempotente.
    /// Single round-trip a través de `info` para no atravesar el filtro `hasAnyData`
    /// múltiples veces con estados vacíos intermedios.
    private func migrateLegacyAndResize() {
        var current = info
        // ensureLegsSized inline sobre current
        while current.outboundLegs.count < outboundLegCount { current.outboundLegs.append(FlightLegInfo()) }
        if current.outboundLegs.count > outboundLegCount {
            current.outboundLegs = Array(current.outboundLegs.prefix(outboundLegCount))
        }
        while current.returnLegs.count < returnLegCount { current.returnLegs.append(FlightLegInfo()) }
        if current.returnLegs.count > returnLegCount {
            current.returnLegs = Array(current.returnLegs.prefix(returnLegCount))
        }

        if totalLegCount > 0 {
            let legsHaveData = current.outboundLegs.contains(where: { $0.hasAnyData })
                             || current.returnLegs.contains(where: { $0.hasAnyData })
            let hasLegacy = !current.seatNumber.isEmpty || !current.seatPosition.isEmpty || !current.cabinClass.isEmpty
            if !legsHaveData && hasLegacy {
                if outboundLegCount > 0, !current.outboundLegs.isEmpty {
                    current.outboundLegs[0].seatNumber = current.seatNumber
                    current.outboundLegs[0].seatPosition = current.seatPosition
                    current.outboundLegs[0].cabinClass = current.cabinClass
                } else if returnLegCount > 0, !current.returnLegs.isEmpty {
                    current.returnLegs[0].seatNumber = current.seatNumber
                    current.returnLegs[0].seatPosition = current.seatPosition
                    current.returnLegs[0].cabinClass = current.cabinClass
                }
                current.seatNumber = ""
                current.seatPosition = ""
                current.cabinClass = ""
            }
        }

        if current != info { info = current }
    }

    /// Replica la clase y posición del primer tramo de IDA al resto (ida + vuelta).
    /// El asiento concreto NO se replica (siempre es distinto por tramo).
    private func applyFirstLegToAll() {
        guard let first = info.outboundLegs.first else { return }
        var current = info
        for i in current.outboundLegs.indices {
            if i == 0 { continue }
            current.outboundLegs[i].seatPosition = first.seatPosition
            current.outboundLegs[i].cabinClass = first.cabinClass
        }
        for i in current.returnLegs.indices {
            current.returnLegs[i].seatPosition = first.seatPosition
            current.returnLegs[i].cabinClass = first.cabinClass
        }
        info = current
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func outboundBinding(_ kp: WritableKeyPath<FlightLegInfo, String>, idx: Int) -> Binding<String> {
        Binding(
            get: {
                guard info.outboundLegs.indices.contains(idx) else { return "" }
                return info.outboundLegs[idx][keyPath: kp]
            },
            set: { newValue in
                var current = info
                while current.outboundLegs.count <= idx { current.outboundLegs.append(FlightLegInfo()) }
                current.outboundLegs[idx][keyPath: kp] = newValue
                info = current
            }
        )
    }

    private func returnBinding(_ kp: WritableKeyPath<FlightLegInfo, String>, idx: Int) -> Binding<String> {
        Binding(
            get: {
                guard info.returnLegs.indices.contains(idx) else { return "" }
                return info.returnLegs[idx][keyPath: kp]
            },
            set: { newValue in
                var current = info
                while current.returnLegs.count <= idx { current.returnLegs.append(FlightLegInfo()) }
                current.returnLegs[idx][keyPath: kp] = newValue
                info = current
            }
        )
    }

    @ViewBuilder
    private func legEditor(
        title: String?,
        seat: Binding<String>,
        pos: Binding<String>,
        cabin: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = title, !title.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "airplane")
                        .font(.system(size: 11)).foregroundStyle(accent)
                    Text(title)
                        .font(.custom("Satoshi-Bold", size: 13))
                        .foregroundStyle(accent)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 2)
            }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "seat.fill")
                        .font(.system(size: 13)).foregroundStyle(accent).frame(width: 20)
                    Text("Asiento").font(.palatino(.body))
                    Spacer()
                    TextField("19A", text: seat)
                        .font(.custom("Satoshi-Bold", size: 15))
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .foregroundStyle(accent)
                        .frame(width: 72)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)

                Rectangle().fill(Color(.systemGray5)).frame(height: 0.5).padding(.leading, 16)

                HStack(spacing: 6) {
                    ForEach(seatPositions, id: \.1) { label, val in
                        Button {
                            pos.wrappedValue = pos.wrappedValue == val ? "" : val
                        } label: {
                            Text(label).font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(pos.wrappedValue == val ? accent : Color(.systemGray5),
                                            in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(pos.wrappedValue == val ? .white : .primary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)

                Rectangle().fill(Color(.systemGray5)).frame(height: 0.5).padding(.leading, 16)

                HStack(spacing: 6) {
                    ForEach(classes, id: \.1) { label, val in
                        Button {
                            cabin.wrappedValue = cabin.wrappedValue == val ? "" : val
                        } label: {
                            Text(label).font(.system(size: 11, weight: .medium))
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(cabin.wrappedValue == val ? accent : Color(.systemGray5),
                                            in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(cabin.wrappedValue == val ? .white : .primary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - SettingsInfoSheet

struct SettingsInfoSheet: View {
    let title: String
    let icon: String
    let content: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: icon)
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                        .padding(.top, 32)
                    Text(content)
                        .font(.palatino(.body))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer(minLength: 48)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .presentationDetents([.medium])
        .appColorScheme()
    }
}

// MARK: - LegalInfoSheet

struct LegalInfoSheet: View {
    let title: String
    let icon: String
    let content: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: icon)
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                        .padding(.top, 32)
                    // `FlagAwareLongText` rendea con Twemoji cualquier
                    // bandera embebida en el texto manteniendo line wrapping
                    // nativo. Si el contenido no tiene banderas (caso de la
                    // sección legal actual) cae a `Text` plano sin overhead.
                    FlagAwareLongText(text: content,
                                      font: .palatino(.body),
                                      foreground: .primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                    Spacer(minLength: 48)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .appColorScheme()
    }
}

// MARK: - Widget Lock Screen info sheet

struct WidgetLockScreenSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct WidgetRow: Identifiable {
        let id = UUID()
        let shape: String
        let name: String
        let desc: String
    }

    private let widgets: [WidgetRow] = [
        WidgetRow(shape: "circle", name: "% del mundo (circular)",
                  desc: "Gauge circular que muestra el porcentaje del mundo que has visitado. Se configura con el modo de conteo (ONU, ONU+obs. o Todos)."),
        WidgetRow(shape: "rectangle", name: "Próximo viaje (rectangular)",
                  desc: "Muestra la bandera del país y los días que quedan hasta tu próximo viaje."),
        WidgetRow(shape: "minus", name: "Cuenta atrás (encima del reloj)",
                  desc: "Línea de texto con los días restantes y el nombre del destino. Aparece encima de la hora en la pantalla de bloqueo."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "lock.display")
                        .font(.system(size: 44))
                        .foregroundStyle(.blue)
                        .padding(.top, 28)
                    Text("Añade estos widgets en la pantalla de bloqueo manteniéndola pulsada y tocando \"Personalizar\".")
                        .font(.palatino(.subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    VStack(spacing: 0) {
                        ForEach(Array(widgets.enumerated()), id: \.element.id) { idx, w in
                            HStack(spacing: 12) {
                                Image(systemName: w.shape)
                                    .font(.system(size: 16))
                                    .foregroundStyle(.blue)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(w.name)
                                        .font(.palatino(.body, weight: .bold))
                                    Text(w.desc)
                                        .font(.palatino(.subheadline))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 24).padding(.vertical, 8)
                            if idx < widgets.count - 1 {
                                Divider().padding(.leading, 60)
                            }
                        }
                    }
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                    Spacer(minLength: 32)
                }
            }
            .navigationTitle("Pantalla de bloqueo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .appColorScheme()
    }
}

// MARK: - Widget Apple Watch info sheet

struct WidgetWatchSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct WidgetRow: Identifiable {
        let id = UUID()
        let shape: String
        let name: String
        let desc: String
    }

    private let widgets: [WidgetRow] = [
        WidgetRow(shape: "circle", name: "Próximo viaje (circular)",
                  desc: "Muestra la bandera del próximo destino como complicación circular en tu esfera de Apple Watch."),
        WidgetRow(shape: "rectangle", name: "Próximo viaje (rectangular)",
                  desc: "Bandera, días restantes y nombre del próximo destino. Ideal para esferas con complicación grande."),
        WidgetRow(shape: "circle.fill", name: "Países visitados (circular)",
                  desc: "Gauge circular con el número de países ONU que has visitado respecto al total de 193."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "applewatch")
                        .font(.system(size: 44))
                        .foregroundStyle(.blue)
                        .padding(.top, 28)
                    Text("Añade las complicaciones de Raskmap en tu esfera de Apple Watch desde la app Watch o pulsando la esfera.")
                        .font(.palatino(.subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    VStack(spacing: 0) {
                        ForEach(Array(widgets.enumerated()), id: \.element.id) { idx, w in
                            HStack(spacing: 12) {
                                Image(systemName: w.shape)
                                    .font(.system(size: 16))
                                    .foregroundStyle(.blue)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(w.name)
                                        .font(.palatino(.body, weight: .bold))
                                    Text(w.desc)
                                        .font(.palatino(.subheadline))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 24).padding(.vertical, 8)
                            if idx < widgets.count - 1 {
                                Divider().padding(.leading, 60)
                            }
                        }
                    }
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                    Spacer(minLength: 32)
                }
            }
            .navigationTitle("Apple Watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .appColorScheme()
    }
}

// MARK: - Fila de medalla con hasta 3 banderas y botón editar
// MARK: - Picker de bandera para tabla top
struct TableFlagPickerSheet: View {
    let spot: ProfileSheet.TopSpot
    let features: [CountryFeature]
    let currentEmoji: String?
    let usedEmojis: Set<String>
    let onSelect: (String) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    private var filtered: [CountryFeature] {
        guard !searchText.isEmpty else { return features }
        let q = searchText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return features.filter {
            $0.localizedName
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .contains(q)
        }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Buscar país…", text: $searchText).autocorrectionDisabled()
                }
                .padding(10)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                ScrollView {
                    if filtered.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "airplane.circle")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("No tienes países visitados en esta región.")
                                .font(.palatino(.subheadline))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 60)
                        .padding(.horizontal, 32)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(filtered, id: \.isoCode) { feature in
                                let emoji   = feature.flagEmoji ?? "🌐"
                                let isChosen = emoji == currentEmoji
                                let isUsed   = usedEmojis.contains(emoji) && !isChosen
                                Button {
                                    guard !isUsed else { return }
                                    onSelect(emoji)
                                    dismiss()
                                } label: {
                                    VStack(spacing: 4) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(isChosen
                                                      ? Color.blue.opacity(0.18)
                                                      : isUsed ? Color(.systemGray6).opacity(0.4)
                                                               : Color(.systemGray6))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .strokeBorder(isChosen ? Color.blue : Color.clear,
                                                                      lineWidth: 2)
                                                )
                                                .frame(width: 60, height: 60)
                                            FlagLabel(emoji: emoji, size: 36)
                                                .opacity(isUsed ? 0.3 : 1.0)
                                        }
                                        Text(feature.localizedName)
                                            .font(.palatino(.caption2))
                                            .foregroundStyle(isUsed ? .tertiary : .secondary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(isUsed)
                            }
                        }
                        .padding(16)
                    }
                }

                if currentEmoji != nil {
                    Divider()
                    Button(role: .destructive) {
                        onClear()
                        dismiss()
                    } label: {
                        Text("Eliminar selección")
                            .font(.palatino(.body))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("\(spot.medal.emoji) \(spot.region.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
    }
}


// MARK: - Lista de territorios visitados
struct AllCountriesSheet: View {
    let features: [CountryFeature]
    let mode: CountingMode
    let visitedIsoCodes: Set<String>
    let countries: [Country]
    let trips: [Trip]
    var onCountryDeleted: ((String) -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var editingVisitCount: Country? = nil
    @State private var addingTripFor: Country? = nil
    @State private var viewingTripsFor: Country? = nil
    @State private var confirmDeleteCountry: Country? = nil
    @State private var showInfoToast: Bool = false

    private var filtered: [CountryFeature] {
        features.filter { visitedIsoCodes.contains($0.isoCode) }
    }

    private var grouped: [(letter: String, items: [CountryFeature])] {
        let sorted = filtered.sorted { $0.localizedName.localizedCompare($1.localizedName) == .orderedAscending }
        var result: [(letter: String, items: [CountryFeature])] = []
        for feature in sorted {
            let letter = String(feature.localizedName.folding(options: .diacriticInsensitive, locale: .current).prefix(1).uppercased())
            if let idx = result.firstIndex(where: { $0.letter == letter }) {
                result[idx].items.append(feature)
            } else {
                result.append((letter: letter, items: [feature]))
            }
        }
        return result
    }

    private func country(for isoCode: String) -> Country? { countries.first { $0.isoCode == isoCode } }
    private func tripCount(for isoCode: String) -> Int { trips.filter { $0.isoCode == isoCode }.count }
    private func totalVisits(for country: Country) -> Int { country.visitCount + tripCount(for: country.isoCode) }

    var body: some View {
        NavigationStack {
            withViewTripsSheet(
                withAddTripSheet(
                    withEditVisitCountSheet(
                        withDeleteDialog(
                            countriesList
                                .listStyle(.plain)
                                .navigationTitle("Visitados (\(filtered.count))")
                                .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
                                .toolbar {
                                    ToolbarItem(placement: .navigationBarLeading) {
                                        Button("Cerrar") { dismiss() }.font(.palatino(.body))
                                    }
                                    ToolbarItem(placement: .navigationBarTrailing) {
                                        Button { withAnimation { showInfoToast = true } } label: {
                                            Image(systemName: "info.circle")
                                        }
                                    }
                                }
                        )
                    )
                )
            )
        }
        .overlay {
            if showInfoToast {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 16) {
                        Image(systemName: "info.circle.fill")
                            .font(.title2).foregroundStyle(.blue)
                        Text("La lista muestra todos los territorios que has visitado, independientemente del sistema de conteo.")
                            .font(.palatino(.body))
                            .multilineTextAlignment(.center)
                        Button {
                            withAnimation { showInfoToast = false }
                        } label: {
                            Text("Cerrar")
                                .font(.palatino(.body, weight: .bold))
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(.white)
                        }.buttonStyle(.plain)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 32)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                .animation(.spring(duration: 0.3), value: showInfoToast)
            }
        }
    }

    @ViewBuilder
    private var countriesList: some View {
        List {
            ForEach(grouped, id: \.letter) { section in
                Section(header: Text(section.letter).font(.palatino(.caption, weight: .bold))) {
                    ForEach(section.items, id: \.isoCode) { feature in
                        let c = country(for: feature.isoCode)
                        AllCountriesRowView(
                            feature: feature,
                            country: c,
                            visitCount: c.map { totalVisits(for: $0) } ?? 0,
                            onViewTrips: { if let c { viewingTripsFor = c } },
                            onAddTrip:   { if let c { addingTripFor   = c } },
                            onDelete:    { if let c { confirmDeleteCountry = c } }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Presentaciones de AllCountriesSheet (un helper por sheet para no sobrecargar el compilador)
private extension AllCountriesSheet {

    func displayName(for isoCode: String) -> String {
        features.first { $0.isoCode == isoCode }?.localizedName ?? isoCode
    }
    func flagEmoji(for isoCode: String) -> String {
        features.first { $0.isoCode == isoCode }?.flagEmoji ?? "🌐"
    }

    @ViewBuilder
    func withDeleteDialog<V: View>(_ v: V) -> some View {
        let isPresented = Binding<Bool>(
            get: { confirmDeleteCountry != nil },
            set: { if !$0 { confirmDeleteCountry = nil } }
        )
        v.alert(
            "¿Eliminar este territorio?",
            isPresented: isPresented,
            presenting: confirmDeleteCountry
        ) { country in
            Button("Eliminar", role: .destructive) {
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
                country.status = .none
                country.hasLived = false
                country.plannedDate = nil
                country.plannedDateTo = nil
                country.transport = nil
                country.visitCount = 0
                for t in allToDelete { modelContext.delete(t) }
                try? modelContext.save()
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
                try? modelContext.save()
                onCountryDeleted?(country.isoCode)
                confirmDeleteCountry = nil
            }
            Button("Cancelar", role: .cancel) { confirmDeleteCountry = nil }
        } message: { country in
            Text("Se eliminarán todos los datos de \(displayName(for: country.isoCode)): visitas, viajes y fechas.")
        }
    }

    @ViewBuilder
    func withEditVisitCountSheet<V: View>(_ v: V) -> some View {
        v.sheet(item: $editingVisitCount) { country in
            VisitCountPickerSheet(country: country)
        }
    }

    @ViewBuilder
    func withAddTripSheet<V: View>(_ v: V) -> some View {
        v.sheet(item: $addingTripFor) { country in
            AddTripSheet(
                isoCode: country.isoCode,
                displayName: displayName(for: country.isoCode),
                flagEmoji: flagEmoji(for: country.isoCode),
                features: features,
                onSave: { trip, _ in
                    modelContext.insert(trip)
                    try? modelContext.save()
                }
            )
        }
    }

    @ViewBuilder
    func withViewTripsSheet<V: View>(_ v: V) -> some View {
        v.sheet(item: $viewingTripsFor) { country in
            CountryTripsSheet(
                country: country,
                trips: trips.filter { $0.isoCode == country.isoCode },
                displayName: displayName(for: country.isoCode),
                flagEmoji: flagEmoji(for: country.isoCode),
                features: features
            )
        }
    }
}

// MARK: - Row auxiliar para AllCountriesSheet
private struct AllCountriesRowView: View {
    let feature: CountryFeature
    let country: Country?
    let visitCount: Int
    let onViewTrips: () -> Void
    let onAddTrip: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            FlagLabel(emoji: feature.flagEmoji ?? "🌐", size: 20)
            Button(action: onViewTrips) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.localizedName)
                            .font(.palatino(.body))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    HStack(spacing: 5) {
                        if country?.hasLived == true {
                            Text("🏠")
                                .font(.caption)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color(.systemGray5), in: Capsule())
                        }
                        if visitCount > 0 {
                            Text("\(visitCount)×")
                                .font(.custom("Satoshi-Bold", size: 13))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(Color(.systemGray5), in: Capsule())
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onAddTrip) {
                Image(systemName: "calendar.badge.plus")
                    .font(.callout)
                    .foregroundStyle(Color(.systemGray3))
            }
            .buttonStyle(.plain)
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.callout)
                    .foregroundStyle(.red.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Edición de nombre inline en perfil
struct UsernameEditView: View {
    @Binding var username: String
    @State private var isEditing: Bool = false
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        if isEditing {
            // Modo edición: campo centrado con ✓ a la derecha
            HStack(spacing: 0) {
                Text("@")
                    .font(.palatino(.title3))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
                TextField("usuario", text: $draft)
                    .font(.palatino(.title3))
                    .multilineTextAlignment(.leading)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focused)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 6)
                    .onChange(of: draft) {
                        draft = String(
                            draft.lowercased()
                                .filter { $0.isLetter || $0.isNumber || $0 == "_" }
                                .prefix(10)
                        )
                    }
                Button {
                    let clean = draft.trimmingCharacters(in: .whitespaces)
                    if !clean.isEmpty { username = clean }
                    isEditing = false
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .padding(.trailing, 12)
                }
            }
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: 240)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
        } else {
            // Modo lectura: @nombre centrado + lápiz justo a su derecha
            HStack(spacing: 6) {
                Text(username.isEmpty ? "usuario" : "@ \(username)")
                    .font(.palatino(.title3))
                    .foregroundStyle(username.isEmpty ? .secondary : .primary)
                Button {
                    draft = username
                    isEditing = true
                    focused = true
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
        }
    }
}



// MARK: - Modelos auxiliares para la confirmación de guardado
struct VisitEntry: Identifiable {
    var id: String { isoCode }
    let isoCode: String
    let flagEmoji: String
    let name: String
    var count: Int
}

struct ProximoRow: Identifiable {
    let id: String
    let country: Country
    let trip: Trip?

    var isoCode: String { country.isoCode }
    var dateFrom: Date? { trip?.dateFrom ?? country.plannedDate }
    var dateTo: Date? { trip?.dateTo ?? country.plannedDateTo }
    var transport: String? { trip?.transport ?? country.transport }
    var rowTitle: String? { trip?.title ?? country.plannedTitle }
}

// Payload identificable para el sheet de "Finalizados" del perfil.
// Ver YearTravelView.onFinalizadosTap.
struct FinalizadosSheetPayload: Identifiable, Equatable {
    var id: Int { year }
    let year: Int
}

struct AirportConfirmEntry: Identifiable {
    var id: String { iata }
    let iata: String
    var count: Int
}

struct AirlineConfirmEntry: Identifiable {
    var id: String { name }
    let name: String
    var count: Int
}

// MARK: - Achievement toast (UIWindow, aparece sobre modales)
final class AchievementToastController {
    static let shared = AchievementToastController()
    private var toastWindow: UIWindow?

    func show(_ toasts: [AchievementKind], menuPositionIsTop: Bool, isRaskmapPro: Bool) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        toastWindow?.isHidden = true
        toastWindow = nil
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = false
        let view = AchievementToastView(toasts: toasts, menuPositionIsTop: menuPositionIsTop, isRaskmapPro: isRaskmapPro)
        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        toastWindow = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            self?.toastWindow?.isHidden = true
            self?.toastWindow = nil
        }
    }
}

private struct AchievementToastView: View {
    let toasts: [AchievementKind]
    let menuPositionIsTop: Bool
    let isRaskmapPro: Bool

    var body: some View {
        VStack {
            if menuPositionIsTop { Spacer() }
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(toasts, id: \.title) { kind in
                        HStack(spacing: 8) {
                            Text(kind.title)
                                .font(.palatino(.body, weight: .bold))
                                .foregroundStyle(.white)
                            Text(kind.medal).font(.title3)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            if !isRaskmapPro {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        Image(systemName: "lock.fill")
                                            .foregroundStyle(.purple)
                                            .font(.title3)
                                    }
                            }
                        }
                    }
                }
                .padding(.trailing, 16)
                .padding(.top, menuPositionIsTop ? 0 : 55)
                .padding(.bottom, menuPositionIsTop ? 110 : 0)
            }
            if !menuPositionIsTop { Spacer() }
        }
    }
}

// MARK: - Añadir viaje
struct AddTripSheet: View {
    let isoCode: String
    let displayName: String
    let flagEmoji: String
    let features: [CountryFeature]
    var isForFuture: Bool = false
    let onSave: (Trip, [String]) -> Void  // trip + newly visited country names
    var onCancel: (() -> Void)? = nil

    @State private var didSave = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var tripTitle: String = ""
    @State private var selectedTransport: String? = nil
    @State private var tripSegments: [TripSegment] = []
    @State private var showAddSegment = false
    @State private var showSaveConfirmation = false
    @State private var confirmVisits: [VisitEntry] = []
    @State private var confirmAirports: [AirportConfirmEntry] = []
    @State private var confirmAirlines: [AirlineConfirmEntry] = []
    @State private var sheetDetent: PresentationDetent = .medium

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.locale = Locale(identifier: "es_ES"); return f
    }()

    // Calculated date range from all segments
    private var calculatedDateFrom: Date {
        tripSegments.map(\.dateFrom).min() ?? Calendar.current.startOfDay(for: Date())
    }
    private var calculatedDateTo: Date? {
        // Fecha explícita si existe; si no, la dateFrom más tardía que supere la de inicio
        let explicit = tripSegments.compactMap(\.dateTo).max()
        if let e = explicit { return e }
        let latestFrom = tripSegments.map(\.dateFrom).max()
        guard let latest = latestFrom, latest > calculatedDateFrom else { return nil }
        return latest
    }

    private func segmentCountryNames(_ seg: TripSegment) -> String {
        if seg.transport == "✈️", let aps = seg.airports, !aps.isEmpty {
            var route = aps.map { $0.iata }.joined(separator: " → ")
            if let retAps = seg.returnAirports, !retAps.isEmpty {
                route += "  /  " + retAps.map { $0.iata }.joined(separator: " → ")
            }
            return route
        }
        return seg.isoCodes.compactMap { iso in features.first { $0.isoCode == iso }?.localizedName }.joined(separator: ", ")
    }

    private func prepareSaveConfirmation() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        guard !tripSegments.isEmpty else { saveTrip(); return }
        var visitCounts: [String: Int] = [:]
        for seg in tripSegments {
            for iso in seg.isoCodes { visitCounts[iso, default: 0] += 1 }
        }
        visitCounts[isoCode] = max(visitCounts[isoCode, default: 0], 1)
        confirmVisits = visitCounts.map { (iso, count) in
            let feat = features.first { $0.isoCode == iso }
            return VisitEntry(isoCode: iso, flagEmoji: feat?.flagEmoji ?? "", name: feat?.localizedName ?? iso, count: count)
        }.sorted { a, b in
            if a.isoCode == isoCode { return true }
            if b.isoCode == isoCode { return false }
            return a.name < b.name
        }
        let apSegs = tripSegments.filter { $0.transport == "✈️" && $0.airports?.isEmpty == false }
        var apC: [String: Int] = [:]
        var alC: [String: Int] = [:]
        var alOrder: [String] = []
        for seg in apSegs {
            let vlISOs = Set(seg.visitedLayoverISOs ?? [])
            // Toques naturales por leg: cada aparición del IATA cuenta una vez.
            for ap in (seg.airports ?? [])       { apC[ap.iata, default: 0] += ap.count }
            for ap in (seg.returnAirports ?? []) { apC[ap.iata, default: 0] += ap.count }
            // Bonus +1 por cada IATA de escala cuyo país esté marcado como
            // visitado. Un solo bonus por IATA (no doblamos si aparece en ida
            // y vuelta — ya tiene 2 toques + 1 bonus = 3, que es lo que pidió
            // el usuario para MAD-SAW-KWI / KWI-SAW-MAD con SAW visitado).
            let outIntermediate = (seg.airports ?? []).dropFirst().dropLast().map { $0.iata }
            let retIntermediate = (seg.returnAirports ?? []).dropFirst().dropLast().map { $0.iata }
            var bonusedIATAs: Set<String> = []
            for iata in outIntermediate + retIntermediate where bonusedIATAs.insert(iata).inserted {
                let a2 = RoutePickerSheet.allAirports.first { $0.iata == iata }?.country ?? ""
                guard let iso = features.first(where: { $0.isoA2 == a2 })?.isoCode,
                      vlISOs.contains(iso) else { continue }
                apC[iata, default: 0] += 1
            }
            for al in (seg.airlines ?? []) {
                if alC[al.name] == nil { alOrder.append(al.name) }
                alC[al.name, default: 0] += al.count
            }
        }
        confirmAirports = apC.map { AirportConfirmEntry(iata: $0.key, count: $0.value) }.sorted { $0.iata < $1.iata }
        confirmAirlines = alOrder.map { AirlineConfirmEntry(name: $0, count: alC[$0] ?? 0) }
        withAnimation { sheetDetent = .large }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation { showSaveConfirmation = true }
        }
    }

    private func saveTrip() {
        let trimmed = tripTitle.trimmingCharacters(in: .whitespaces)
        let transport = tripSegments.first?.transport ?? "🌍"
        let airplaneSeg = tripSegments.first(where: { $0.transport == "✈️" && ($0.airports?.isEmpty == false) })
        let finalAirports: [TripAirport]
        let finalAirlines: [TripAirline]
        // Orden cronológico: iteramos segmentos por dateFrom y dentro de cada
        // uno respetamos el orden ida → vuelta. El primer aeropuerto visto
        // gana — así `trip.tripAirports` queda en el orden real del viaje
        // (MAD → KWI → DXB) y NO en orden alfabético del Dictionary o de
        // `confirmAirports.sorted`. Es lo que rendea `legacyAirportRoute`
        // y otros paths que leen `trip.tripAirports`.
        var apOrder: [String] = []
        var seenIatas: Set<String> = []
        for seg in tripSegments.sorted(by: { $0.dateFrom < $1.dateFrom }) where seg.transport == "✈️" {
            for ap in seg.airports ?? [] where seenIatas.insert(ap.iata).inserted { apOrder.append(ap.iata) }
            for ap in seg.returnAirports ?? [] where seenIatas.insert(ap.iata).inserted { apOrder.append(ap.iata) }
        }
        if !confirmAirports.isEmpty || !confirmAirlines.isEmpty {
            // Counts vienen del confirm-dialog; orden cronológico de apOrder.
            let countsByIata = Dictionary(confirmAirports.map { ($0.iata, $0.count) }, uniquingKeysWith: +)
            var ordered: [TripAirport] = apOrder.compactMap { iata in
                guard let count = countsByIata[iata], count > 0 else { return nil }
                return TripAirport(iata: iata, count: count)
            }
            // Defensiva: incluye iatas que el user añadiera en el dialog.
            for entry in confirmAirports where !seenIatas.contains(entry.iata) && entry.count > 0 {
                ordered.append(TripAirport(iata: entry.iata, count: entry.count))
            }
            finalAirports = ordered
            finalAirlines = confirmAirlines.map { TripAirline(name: $0.name, count: $0.count) }
        } else {
            // No hubo confirm-dialog → counts naturales del segmento, mismo orden.
            var apC: [String: Int] = [:]
            for ap in airplaneSeg?.airports ?? [] { apC[ap.iata, default: 0] += 1 }
            for ap in airplaneSeg?.returnAirports ?? [] { apC[ap.iata, default: 0] += 1 }
            finalAirports = apOrder.compactMap { iata in
                guard let count = apC[iata], count > 0 else { return nil }
                return TripAirport(iata: iata, count: count)
            }
            finalAirlines = airplaneSeg?.airlines ?? []
        }
        let trip = Trip(isoCode: isoCode, title: trimmed.isEmpty ? nil : trimmed,
                        dateFrom: calculatedDateFrom, dateTo: calculatedDateTo, transport: transport,
                        tripAirports: finalAirports, tripAirlines: finalAirlines)
        trip.hasLayover = airplaneSeg?.hasLayover ?? false
        trip.tripSegments = tripSegments
        var newlyVisitedNames: [String] = []
        if !tripSegments.isEmpty {
            let groupID = UUID().uuidString
            trip.segmentGroupID = groupID
            let today = Calendar.current.startOfDay(for: Date())
            var countForIso: [String: Int] = [:]
            if !confirmVisits.isEmpty {
                for entry in confirmVisits { countForIso[entry.isoCode] = entry.count }
            } else {
                for seg in tripSegments { for iso in seg.isoCodes { countForIso[iso, default: 0] += 1 } }
                countForIso[isoCode] = max(countForIso[isoCode, default: 0], 1)
            }
            // Extra visits for main country (main trip = 1, extras = count-1)
            let segsForMain = tripSegments.filter { $0.isoCodes.contains(isoCode) }
            let mainCount = countForIso[isoCode] ?? 1
            for i in 0..<(mainCount - 1) {
                let extraSeg = (i + 1) < segsForMain.count ? segsForMain[i + 1] : segsForMain.last
                let extraTransport = extraSeg?.transport ?? transport
                var extraAps: [TripAirport] = []
                var extraAls: [TripAirline] = []
                if extraSeg?.transport == "✈️" {
                    var apC3: [String: Int] = [:]
                    for ap in extraSeg?.airports ?? [] { apC3[ap.iata, default: 0] += 1 }
                    for ap in extraSeg?.returnAirports ?? [] { apC3[ap.iata, default: 0] += 1 }
                    extraAps = apC3.map { TripAirport(iata: $0.key, count: $0.value) }
                    extraAls = extraSeg?.airlines ?? []
                }
                let extra = Trip(isoCode: isoCode, title: trimmed.isEmpty ? nil : trimmed,
                                dateFrom: extraSeg?.dateFrom ?? calculatedDateFrom,
                                dateTo: extraSeg?.dateTo ?? calculatedDateTo,
                                transport: extraTransport, tripAirports: extraAps, tripAirlines: extraAls)
                extra.hasLayover = extraSeg?.hasLayover ?? false
                extra.segmentGroupID = groupID
                extra.isSegmentChild = true
                if let seg = extraSeg { extra.tripSegments = [seg] }
                modelContext.insert(extra)
            }
            // Children for other countries, one per confirmed visit using the matching segment
            for (iso, confirmedCount) in countForIso where iso != isoCode && confirmedCount > 0 {
                let segsWithIso = tripSegments.filter { $0.isoCodes.contains(iso) }
                let firstDate = segsWithIso.first?.dateFrom ?? calculatedDateFrom
                for i in 0..<confirmedCount {
                    let seg = i < segsWithIso.count ? segsWithIso[i] : segsWithIso.last
                    let d = seg?.dateFrom ?? calculatedDateFrom
                    let dTo = seg?.dateTo
                    let t = seg?.transport ?? transport
                    var apC2: [String: Int] = [:]
                    if seg?.transport == "✈️" {
                        for ap in seg?.airports ?? [] { apC2[ap.iata, default: 0] += 1 }
                        for ap in seg?.returnAirports ?? [] { apC2[ap.iata, default: 0] += 1 }
                    }
                    let sAps = seg?.transport == "✈️" ? apC2.map { TripAirport(iata: $0.key, count: $0.value) } : []
                    let sAls = seg?.transport == "✈️" ? (seg?.airlines ?? []) : []
                    let child = Trip(isoCode: iso, title: trimmed.isEmpty ? nil : trimmed,
                                    dateFrom: d, dateTo: dTo, transport: t,
                                    tripAirports: sAps, tripAirlines: sAls)
                    child.hasLayover = seg?.hasLayover ?? false
                    child.segmentGroupID = groupID
                    child.isSegmentChild = true
                    if let seg { child.tripSegments = [seg] }
                    modelContext.insert(child)
                }
                // Mark visited + toast (use first segment's date)
                if Calendar.current.startOfDay(for: firstDate) <= today {
                    let countryIso = iso
                    let desc = FetchDescriptor<Country>(predicate: #Predicate { $0.isoCode == countryIso })
                    if let countryRecord = modelContext.fetchFirstOrWarn(desc) {
                        if countryRecord.status != .visited {
                            countryRecord.status = .visited
                            countryRecord.plannedDate = nil
                            countryRecord.plannedDateTo = nil
                            countryRecord.transport = nil
                        }
                        let feat = features.first { $0.isoCode == iso }
                        let flag = feat?.flagEmoji ?? ""
                        let name = feat?.localizedName ?? iso
                        newlyVisitedNames.append("\(flag) \(name)".trimmingCharacters(in: .whitespaces))
                    }
                } else {
                    // Future trip: promociona child country a wantToVisit y registra plannedDate.
                    let countryIso = iso
                    let desc = FetchDescriptor<Country>(predicate: #Predicate { $0.isoCode == countryIso })
                    let segTransport = segsWithIso.first?.transport
                    let segDateTo = segsWithIso.first?.dateTo
                    if let countryRecord = modelContext.fetchFirstOrWarn(desc) {
                        if countryRecord.status != .visited && countryRecord.status != .lived {
                            countryRecord.status = .wantToVisit
                            if countryRecord.plannedDate == nil || firstDate < countryRecord.plannedDate! {
                                countryRecord.plannedDate = firstDate
                                countryRecord.plannedDateTo = segDateTo
                                countryRecord.transport = segTransport
                            }
                        }
                    } else {
                        let feat = features.first { $0.isoCode == iso }
                        let newCountry = Country(
                            name: feat?.localizedName ?? iso,
                            isoCode: iso,
                            status: .wantToVisit
                        )
                        newCountry.plannedDate = firstDate
                        newCountry.plannedDateTo = segDateTo
                        newCountry.transport = segTransport
                        modelContext.insert(newCountry)
                    }
                }
            }
        }
        didSave = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSave(trip, newlyVisitedNames)
        dismiss()
    }

    var body: some View {
        ZStack {
        NavigationStack {
            ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    FlagLabel(emoji: flagEmoji, size: 20)
                    Text(displayName)
                        .font(.palatino(.title3, weight: .bold))
                }
                .padding(.top, 12).padding(.bottom, 4)

                TextField("Título del viaje", text: $tripTitle)
                    .font(.palatino(.body))
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16).padding(.bottom, 8)

                Divider().padding(.horizontal, 16).padding(.vertical, 4)

                // MARK: Tramos adicionales
                VStack(alignment: .leading, spacing: 6) {
                    if !tripSegments.isEmpty {
                        Text("Tramos adicionales")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                        // Orden cronológico (ida → vuelta) independientemente del orden de inserción.
                        ForEach(tripSegments.sorted { $0.dateFrom < $1.dateFrom }) { seg in
                            HStack(spacing: 8) {
                                Text(seg.transport).font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(segmentCountryNames(seg))
                                        .font(.palatino(.caption)).lineLimit(1)
                                    Text(Self.fmt.string(from: seg.dateFrom))
                                        .font(.palatino(.caption)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { tripSegments.removeAll { $0.id == seg.id } } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red.opacity(0.7))
                                }.buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal, 16)
                        }
                    }
                    Button { showAddSegment = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill").foregroundStyle(.blue)
                            Text("Añadir transporte").font(.palatino(.body)).foregroundStyle(.blue)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)

                // Auto-calculated date range from segments
                if !tripSegments.isEmpty {
                    HStack(spacing: 16) {
                        VStack(spacing: 2) {
                            Text("DESDE").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            Text(Self.fmt.string(from: calculatedDateFrom))
                                .font(.palatino(.subheadline, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        if let to = calculatedDateTo {
                            VStack(spacing: 2) {
                                Text("HASTA").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                                Text(Self.fmt.string(from: to))
                                    .font(.palatino(.subheadline, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }

                Divider().padding(.horizontal, 16).padding(.top, 4)

                Button { prepareSaveConfirmation() } label: {
                    Text(isForFuture ? "Añadir a Próximos" : "Guardar viaje")
                        .font(.palatino(.body, weight: .bold)).frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24).padding(.vertical, 14)
            } // end VStack
            } // end ScrollView
            .navigationTitle(isForFuture ? "Añadir a Próximos" : "Añadir viaje")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        onCancel?()
                        dismiss()
                    }.font(.palatino(.body))
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $sheetDetent)
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(showSaveConfirmation)
        .onDisappear {
            if !didSave { onCancel?() }
        }
        .sheet(isPresented: $showAddSegment) {
            AddSegmentSheet(features: features, isForFuture: isForFuture, existingSegments: tripSegments) { seg in
                tripSegments.append(seg)
                // Mantener el array siempre ordenado por fecha de vuelo,
                // no por orden de inserción — el del 29 aparece antes del 30
                // aunque se añada después.
                tripSegments.sort { $0.dateFrom < $1.dateFrom }
            }
        }
        .appColorScheme()

        if showSaveConfirmation {
            visitConfirmCard(onSave: { showSaveConfirmation = false; saveTrip() },
                             onCancel: { showSaveConfirmation = false })
        }
        } // ZStack
    }

    @ViewBuilder
    private func visitConfirmCard(onSave: @escaping () -> Void, onCancel: @escaping () -> Void) -> some View {
        confirmCardContent(
            confirmVisits: $confirmVisits,
            confirmAirports: $confirmAirports,
            confirmAirlines: $confirmAirlines,
            accent: Color(red: 64/255, green: 114/255, blue: 212/255),
            onSave: onSave,
            onCancel: onCancel
        )
    }
}


// MARK: - Vista de años de viaje en perfil
struct YearTravelView: View {
    let countries: [Country]
    let features: [CountryFeature]
    let trips: [Trip]
    var onProximosTap: (() -> Void)? = nil
    var onFinalizadosTap: ((Int) -> Void)? = nil

    @EnvironmentObject private var colorTheme: ColorThemeManager
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    private var availableYears: [Int] {
        var years = Set<Int>()
        years.insert(currentYear)
        for trip in trips {
            let end = Calendar.current.startOfDay(for: trip.effectiveEndDate)
            if end <= today { years.insert(trip.year) }
        }
        for country in countries {
            let endDate = country.plannedDateTo ?? country.plannedDate
            guard let end = endDate else { continue }
            let endDay = Calendar.current.startOfDay(for: end)
            if endDay <= today { years.insert(Calendar.current.component(.year, from: end)) }
        }
        return years.sorted(by: >)
    }

    private var finalizados: [(isoCode: String, lastDate: Date)] {
        let today = Calendar.current.startOfDay(for: Date())
        var allEntries: [String: [Date]] = [:]
        for trip in trips {
            let endDay = Calendar.current.startOfDay(for: trip.effectiveEndDate)
            if endDay <= today && trip.year == selectedYear {
                allEntries[trip.isoCode, default: []].append(trip.dateFrom)
            }
        }
        for country in countries {
            let endDate = country.plannedDateTo ?? country.plannedDate
            guard let end = endDate else { continue }
            let endDay = Calendar.current.startOfDay(for: end)
            let year = Calendar.current.component(.year, from: end)
            if endDay <= today && year == selectedYear {
                let from = country.plannedDate ?? end
                allEntries[country.isoCode, default: []].append(from)
            }
        }
        var result: [(isoCode: String, lastDate: Date)] = []
        for (iso, dates) in allEntries {
            if let earliest = dates.min() {
                result.append((isoCode: iso, lastDate: earliest))
            }
        }
        // Orden fijo: fecha asc + isoCode asc como tiebreaker determinista.
        // Sin tiebreaker, países con la misma fecha pueden reordenarse entre
        // renders porque `allEntries` (Dictionary) itera en orden no-determinista.
        return result.sorted { a, b in
            if a.lastDate != b.lastDate { return a.lastDate < b.lastDate }
            return a.isoCode < b.isoCode
        }
    }

    private var proximos: [Country] {
        let today = Calendar.current.startOfDay(for: Date())
        let tripsByIso: [String: [Trip]] = Dictionary(grouping: trips, by: { $0.isoCode })
        let futureIsoCodes = Set(trips.compactMap { trip -> String? in
            guard Calendar.current.startOfDay(for: trip.dateFrom) >= today else { return nil }
            return trip.isoCode
        })
        let visitedWithFuture = countries.filter { $0.status == .visited && futureIsoCodes.contains($0.isoCode) }
        let wantToVisit = countries.filter { $0.status == .wantToVisit }
        let all = (wantToVisit + visitedWithFuture)
        // Próxima fecha REAL del país: la primera fecha futura de cualquier trip
        // (incluido children). Para países wantToVisit sin trips, fallback al
        // `plannedDate` legacy. Esto evita que países como "Chipre del Norte"
        // queden mal ordenados porque su plannedDate sea stale (heredado de
        // una iteración anterior) y no coincida con su trip futuro real.
        func nextDate(_ country: Country) -> Date? {
            let tripDates = (tripsByIso[country.isoCode] ?? [])
                .map { Calendar.current.startOfDay(for: $0.dateFrom) }
                .filter { $0 >= today }
            if let earliest = tripDates.min() { return earliest }
            return country.plannedDate
        }
        // Orden fijo: próxima fecha asc + isoCode asc como tiebreaker.
        return all.sorted { c0, c1 in
            switch (nextDate(c0), nextDate(c1)) {
            case let (a?, b?):
                if a != b { return a < b }
                return c0.isoCode < c1.isoCode
            case (_?, nil):   return true
            case (nil, _?):   return false
            case (nil, nil):  return c0.isoCode < c1.isoCode
            }
        }
    }

    private var flightCount: Int {
        let today = Calendar.current.startOfDay(for: Date())
        let yearTrips = trips.filter { trip in
            guard !trip.isSegmentChild else { return false }
            guard trip.year == selectedYear else { return false }
            let endDay = Calendar.current.startOfDay(for: trip.effectiveEndDate)
            if selectedYear == currentYear && endDay > today { return false }
            return true
        }
        var count = 0
        for trip in yearTrips {
            if let raw = trip.segmentsRaw,
               let segs = try? JSONDecoder().decode([TripSegment].self, from: Data(raw.utf8)) {
                // Dedup defensivo por (outAirports | returnAirports | dateFrom)
                var seenFlightKeys = Set<String>()
                for seg in segs where seg.transport == "✈️" {
                    let outK = (seg.airports ?? []).map { $0.iata }.joined(separator: "-")
                    let retK = (seg.returnAirports ?? []).map { $0.iata }.joined(separator: "-")
                    let dfK = String(Int(seg.dateFrom.timeIntervalSince1970))
                    guard seenFlightKeys.insert("\(outK)|\(retK)|\(dfK)").inserted else { continue }
                    let outbound = max(0, (seg.airports?.count ?? 0) - 1)
                    let ret      = max(0, (seg.returnAirports?.count ?? 0) - 1)
                    // Sin floor: si el segmento no tiene aeropuertos válidos no cuenta.
                    count += outbound + ret
                }
            } else if trip.transport == "✈️" {
                if let raw = trip.airportsRaw,
                   let airports = try? JSONDecoder().decode([TripAirport].self, from: Data(raw.utf8)),
                   airports.count > 1 {
                    // Usamos sum(count) / 2 (igual que el wrapped) en vez de airports.count − 1,
                    // que infla round-trips directos almacenados como [MAD(2), JFK(2)].
                    let totalTouches = airports.reduce(0) { $0 + $1.count }
                    count += totalTouches / 2
                } else {
                    // Sin aeropuertos guardados: no contamos ghost flights.
                    count += 0
                }
            }
        }
        return count
    }

    /// Para cada mes (1-12) del `selectedYear`, cuenta el número de viajes
    /// primarios cuya fecha de inicio cae en ese mes. Usado por el heatmap.
    private var tripsByMonth: [Int: Int] {
        let cal = Calendar.current
        var byMonth: [Int: Int] = [:]
        for trip in trips where !trip.isSegmentChild {
            let comps = cal.dateComponents([.year, .month], from: trip.dateFrom)
            guard comps.year == selectedYear, let m = comps.month else { continue }
            byMonth[m, default: 0] += 1
        }
        return byMonth
    }

    /// Mini heatmap: 12 cuadritos (uno por mes) coloreados según el número
    /// de viajes ese mes. Estilo GitHub contributions, escala 4 niveles.
    @ViewBuilder
    private var yearlyHeatmap: some View {
        let byMonth = tripsByMonth
        let maxCount = max(1, byMonth.values.max() ?? 0)
        let monthLabels = ["E", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]
        if !byMonth.isEmpty {
            VStack(spacing: 5) {
                HStack(spacing: 4) {
                    ForEach(0..<12, id: \.self) { i in
                        let m = i + 1
                        let count = byMonth[m] ?? 0
                        let intensity: Double = count == 0 ? 0 : (0.20 + 0.80 * Double(count) / Double(maxCount))
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color(red: 0x53/255, green: 0xA3/255, blue: 0xFE/255).opacity(intensity))
                            .frame(height: 18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .stroke(Color(.systemGray5), lineWidth: count == 0 ? 0.5 : 0)
                            )
                            .accessibilityLabel("\(monthLabels[i]): \(count) viajes")
                    }
                }
                HStack(spacing: 4) {
                    ForEach(0..<12, id: \.self) { i in
                        Text(monthLabels[i])
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    /// Devuelve la bandera emoji del país. Si el territorio no tiene bandera
    /// (Twemoji asset falta o ISO no estándar), devuelve "🌐" como fallback
    /// para que aparezca en los grids de Próximos/Finalizados con la posición
    /// cronológica correcta en vez de quedar invisible.
    private func flagEmoji(for country: Country) -> String? {
        features.first(where: { $0.isoCode == country.isoCode })?.flagEmoji ?? "🌐"
    }

    private func flagEmoji(for isoCode: String) -> String? {
        features.first(where: { $0.isoCode == isoCode })?.flagEmoji ?? "🌐"
    }

    var body: some View {
        VStack(spacing: 12) {
            if availableYears.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(availableYears, id: \.self) { year in
                            Button { selectedYear = year } label: {
                                Text(String(year))
                                    .font(.custom(selectedYear == year ? "Satoshi-Bold" : "Satoshi-Regular", size: 14))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        selectedYear == year
                                            ? Color(red: 0x53/255, green: 0xA3/255, blue: 0xFE/255)
                                            : Color(.systemGray5),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(selectedYear == year ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.05),
                            .init(color: .black, location: 0.95),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }

            if flightCount > 0 {
                Text("Total de vuelos: \(flightCount)")
                    .font(.palatino(.caption, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            // Heatmap anual estilo GitHub: 12 columnas (meses) × 1 fila visual
            // mostrando intensidad de viaje por mes en el año seleccionado.
            yearlyHeatmap
                .padding(.horizontal, 24)

            if selectedYear == currentYear {
                HStack(alignment: .top, spacing: 16) {
                    Button {
                        onFinalizadosTap?(selectedYear)
                    } label: {
                        VStack(alignment: .center, spacing: 6) {
                            Text("Finalizados").font(.palatino(.caption, weight: .bold)).foregroundStyle(.primary)
                            if finalizados.isEmpty {
                                Text("–").font(.palatino(.caption)).foregroundStyle(.secondary)
                            } else {
                                let flagged = finalizados.compactMap { flagEmoji(for: $0.isoCode) }
                                FlowLayoutCentered(emojis: flagged, year: selectedYear, isLeft: true, perRow: 5)
                            }
                        }.frame(maxWidth: .infinity, alignment: .top)
                    }
                    .buttonStyle(.plain)
                    .disabled(onFinalizadosTap == nil || finalizados.isEmpty)
                    Divider().frame(maxHeight: .infinity)
                    Button {
                        onProximosTap?()
                    } label: {
                        VStack(alignment: .center, spacing: 6) {
                            Text("Próximos").font(.palatino(.caption, weight: .bold)).foregroundStyle(.primary)
                            if proximos.isEmpty {
                                Text("–").font(.palatino(.caption)).foregroundStyle(.secondary)
                            } else {
                                let flagged = proximos.compactMap { flagEmoji(for: $0) }
                                FlowLayoutCentered(emojis: flagged, year: selectedYear, isLeft: false, perRow: 5)
                            }
                        }.frame(maxWidth: .infinity, alignment: .top)
                    }
                    .buttonStyle(.plain)
                    .disabled(onProximosTap == nil)
                }.padding(.horizontal, 24)
            } else {
                Button {
                    onFinalizadosTap?(selectedYear)
                } label: {
                    VStack(alignment: .center, spacing: 6) {
                        Text("Finalizados").font(.palatino(.caption, weight: .bold)).foregroundStyle(.primary)
                        if finalizados.isEmpty {
                            Text("–").font(.palatino(.caption)).foregroundStyle(.secondary)
                        } else {
                            let flagged = finalizados.compactMap { flagEmoji(for: $0.isoCode) }
                            FlowLayoutCentered(emojis: flagged, year: selectedYear, isLeft: true, perRow: 10)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                }
                .buttonStyle(.plain)
                .disabled(onFinalizadosTap == nil || finalizados.isEmpty)
            }
        }
    }
}

struct FlowLayoutCentered: View {
    let emojis: [String]
    let year: Int
    let isLeft: Bool
    /// Máximo de banderas por línea — el grid del año actual usa 5 para que las
    /// columnas Finalizados/Próximos quepan en mitad del ancho del perfil sin
    /// recortar emojis. Para años pasados se permite hasta 10 por línea (ancho
    /// completo).
    var perRow: Int = 5
    var body: some View {
        let rows = stride(from: 0, to: emojis.count, by: perRow).map {
            Array(emojis[$0..<min($0 + perRow, emojis.count)])
        }
        VStack(alignment: .center, spacing: 4) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    ForEach(Array(rows[i].enumerated()), id: \.offset) { _, e in
                        FlagLabel(emoji: e, size: 22)
                    }
                }
            }
        }
    }
}


// MARK: - Selector de visitas manuales
struct VisitCountPickerSheet: View {
    @Bindable var country: Country
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Text("Visitas manuales").font(.palatino(.title3, weight: .bold))
                HStack(spacing: 24) {
                    Button {
                        if country.visitCount > 0 { country.visitCount -= 1; try? modelContext.save() }
                    } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 44)).foregroundStyle(.red)
                    }
                    Text("\(country.visitCount)").font(.system(size: 64, weight: .bold, design: .rounded))
                    Button {
                        country.visitCount += 1; try? modelContext.save()
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 44)).foregroundStyle(.blue)
                    }
                }
                Spacer()
            }
            .navigationTitle("Contador")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}


// MARK: - Selector de rango de fechas (calendario nativo)
struct RangeDatePicker: UIViewRepresentable {
    @Binding var dateFrom: Date
    @Binding var dateTo: Date?
    @Binding var pickingFrom: Bool
    var minDate: Date? = nil
    var maxDate: Date? = nil

    func makeUIView(context: Context) -> UICalendarView {
        let v = UICalendarView()
        v.calendar = Calendar.current
        v.locale = Locale(identifier: "es_ES")
        v.fontDesign = .rounded
        let sel = UICalendarSelectionSingleDate(delegate: context.coordinator)
        v.selectionBehavior = sel
        context.coordinator.calendarView = v
        context.coordinator.singleSel = sel
        context.coordinator.parent = self
        return v
    }

    func updateUIView(_ v: UICalendarView, context: Context) {
        context.coordinator.parent = self
        let cal = Calendar.current
        let showDate = pickingFrom ? dateFrom : (dateTo ?? dateFrom)
        let targetComps = cal.dateComponents([.year, .month, .day], from: showDate)
        context.coordinator.singleSel?.selectedDate = targetComps
        // Navegar al mes correcto solo cuando cambia el tab activo (no en cada re-render)
        let coord = context.coordinator
        if coord.lastPickingFrom != pickingFrom {
            coord.lastPickingFrom = pickingFrom
            let visible = v.visibleDateComponents
            if visible.year != targetComps.year || visible.month != targetComps.month {
                v.setVisibleDateComponents(
                    DateComponents(year: targetComps.year, month: targetComps.month, day: 1),
                    animated: true
                )
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, UICalendarSelectionSingleDateDelegate {
        var parent: RangeDatePicker!
        weak var calendarView: UICalendarView?
        weak var singleSel: UICalendarSelectionSingleDate?
        var lastPickingFrom: Bool = true

        func dateSelection(_ selection: UICalendarSelectionSingleDate,
                           didSelectDate dateComponents: DateComponents?) {
            guard let comps = dateComponents,
                  let date = Calendar.current.date(from: comps) else { return }
            let cal = Calendar.current
            if parent.pickingFrom {
                parent.dateFrom = date
                // Default: vuelta al día siguiente (si no supera maxDate).
                // Fallback: si el cálculo falla (edge case de calendario), +86400s.
                let nextDay = cal.date(byAdding: .day, value: 1, to: date)
                            ?? date.addingTimeInterval(86_400)
                if let max = parent.maxDate {
                    parent.dateTo = nextDay <= max ? nextDay : nil
                } else {
                    parent.dateTo = nextDay
                }
                parent.pickingFrom = false
            } else {
                if date < parent.dateFrom {
                    parent.dateFrom = date
                    let nextDay = cal.date(byAdding: .day, value: 1, to: date)
                                ?? date.addingTimeInterval(86_400)
                    if let max = parent.maxDate {
                        parent.dateTo = nextDay <= max ? nextDay : nil
                    } else {
                        parent.dateTo = nextDay
                    }
                } else if date == parent.dateFrom {
                    parent.dateTo = nil
                } else {
                    parent.dateTo = date
                }
            }
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate,
                           canSelectDate dateComponents: DateComponents?) -> Bool {
            guard let comps = dateComponents,
                  let date = Calendar.current.date(from: comps) else { return false }
            let day = Calendar.current.startOfDay(for: date)
            if let min = parent.minDate, day < min { return false }
            if let max = parent.maxDate, day > max { return false }
            return true
        }
    }
}


// MARK: - Selector de fecha para Próximos
struct PlannedDatePickerSheet: View {
    let countryName: String
    let flagEmoji: String
    let existingDate: Date?
    let existingDateTo: Date?
    let existingTransport: String?
    let existingTitle: String?
    var isEditing: Bool = false
    let onSave: (Date, Date?, String?, String?, [TripAirport], [TripAirline], FlightInfo?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var dateFrom: Date
    @State private var dateTo: Date?
    @State private var pickingFrom: Bool = true
    @State private var selectedTransport: String?
    @State private var tripTitle: String
    @State private var selectedAirports: [TripAirport] = []
    @State private var selectedReturnAirports: [TripAirport] = []
    @State private var selectedAirlines: [TripAirline] = []
    @State private var hasLayover: Bool = false
    @State private var flightInfo = FlightInfo()
    @State private var showRoutePicker = false
    @State private var showConfirmation = false
    @State private var confirmVisits: [VisitEntry] = []
    @State private var confirmAirports: [AirportConfirmEntry] = []
    @State private var confirmAirlines: [AirlineConfirmEntry] = []

    static let transports: [(emoji: String, label: String)] = [
        ("✈️", "Avión"), ("🚗", "Coche"), ("🚂", "Tren"), ("🚌", "Bus"), ("🚢", "Barco"), ("🚶🏻", "Andando")
    ]
    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.locale = Locale(identifier: "es_ES"); return f
    }()
    private var tomorrow: Date {
        let cal = Calendar.current
        let nextDay = cal.date(byAdding: .day, value: 1, to: Date())
                    ?? Date().addingTimeInterval(86_400)
        return cal.startOfDay(for: nextDay)
    }

    init(countryName: String, flagEmoji: String,
         existingDate: Date?, existingDateTo: Date?, existingTransport: String?,
         existingTitle: String? = nil, isEditing: Bool = false,
         onSave: @escaping (Date, Date?, String?, String?, [TripAirport], [TripAirline], FlightInfo?) -> Void) {
        self.countryName = countryName
        self.flagEmoji = flagEmoji
        self.existingDate = existingDate
        self.existingDateTo = existingDateTo
        self.existingTransport = existingTransport
        self.existingTitle = existingTitle
        self.isEditing = isEditing
        self.onSave = onSave
        let cal = Calendar.current
        let tomorrowRaw = cal.date(byAdding: .day, value: 1, to: Date())
                        ?? Date().addingTimeInterval(86_400)
        let tomorrow = cal.startOfDay(for: tomorrowRaw)
        let initial = existingDate ?? tomorrow
        let from = max(initial, tomorrow)
        _dateFrom = State(initialValue: from)
        // Sin fecha de vuelta por defecto. Si ya existía una al editar, se respeta.
        _dateTo = State(initialValue: existingDateTo)
        _selectedTransport = State(initialValue: existingTransport)
        _tripTitle = State(initialValue: existingTitle ?? "")
    }

    private var rutaLabel: String {
        if selectedAirports.isEmpty { return "Aeropuertos y aerolíneas" }
        return selectedAirports.map { "\($0.iata) (\($0.count)x)" }.joined(separator: " → ")
    }
    private var airlinesLabel: String {
        selectedAirlines.map { "\($0.name) \($0.count)x" }.joined(separator: ", ")
    }

    private let accent = Color(red: 64/255, green: 114/255, blue: 212/255)

    @ViewBuilder
    private func transportRow() -> some View {
        HStack(spacing: 8) {
            ForEach(Self.transports, id: \.emoji) { t in
                let isSelected = selectedTransport == t.emoji
                Button { selectedTransport = isSelected ? nil : t.emoji } label: {
                    VStack(spacing: 4) {
                        Text(t.emoji).font(.system(size: 20))
                        Text(t.label).font(.system(size: 9, weight: .medium))
                            .foregroundStyle(isSelected ? accent : .secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(isSelected ? accent.opacity(0.1) : Color(.systemGray6),
                                in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? accent.opacity(0.35) : Color.clear, lineWidth: 1.5))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 10)
    }

    @ViewBuilder
    private func dateTabsRow() -> some View {
        let fromLabel = Self.fmt.string(from: dateFrom)
        let toLabel = dateTo.map { Self.fmt.string(from: $0) } ?? "Sin vuelta"
        HStack(spacing: 12) {
            dateTab(isFrom: true, label: "DESDE", value: fromLabel)
            dateTab(isFrom: false, label: "HASTA", value: toLabel)
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func dateTab(isFrom: Bool, label: String, value: String) -> some View {
        let active = pickingFrom == isFrom
        let color: Color = active ? accent : (isFrom ? .primary : (dateTo == nil ? .secondary : .primary))
        Button { pickingFrom = isFrom } label: {
            VStack(spacing: 4) {
                Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).tracking(0.8)
                Text(value).font(.custom("Satoshi-Bold", size: 15)).foregroundStyle(color)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(active ? accent.opacity(0.08) : Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? accent.opacity(0.3) : Color.clear, lineWidth: 1.5))
        }.buttonStyle(.plain)
    }

    var body: some View {
        ZStack {
        NavigationStack {
            ScrollView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 6) {
                    FlagLabel(emoji: flagEmoji, size: 52)
                    Text(countryName)
                        .font(.custom("Satoshi-Bold", size: 24))
                    Text(isEditing ? "Editar fecha de viaje" : "Añadir a Próximos")
                        .font(.palatino(.subheadline))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 28).padding(.bottom, 24)

                VStack(alignment: .leading, spacing: 8) {
                    Text("TÍTULO DEL VIAJE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary).tracking(1.0)
                        .padding(.horizontal, 24)
                    TextField("Ej: Vacaciones de verano", text: $tripTitle)
                        .font(.palatino(.body))
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 20)

                VStack(alignment: .leading, spacing: 8) {
                    Text("TRANSPORTE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary).tracking(1.0)
                        .padding(.horizontal, 24)
                    transportRow()
                }
                .padding(.bottom, 8)

                if selectedTransport == "✈️" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("RUTA DE VUELO")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary).tracking(1.0)
                            .padding(.horizontal, 24)
                        Button { showRoutePicker = true } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(accent.opacity(0.1)).frame(width: 36, height: 36)
                                    Image(systemName: "airplane").font(.system(size: 15)).foregroundStyle(accent)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rutaLabel)
                                        .font(.palatino(.body))
                                        .foregroundStyle(selectedAirports.isEmpty ? .secondary : .primary)
                                    if !selectedAirlines.isEmpty {
                                        Text(airlinesLabel)
                                            .font(.palatino(.caption)).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 24)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 12)

                    FlightInfoSection(info: $flightInfo,
                                      outboundRoute: selectedAirports.map { $0.iata },
                                      returnRoute: selectedReturnAirports.map { $0.iata })
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("FECHAS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary).tracking(1.0)
                        .padding(.horizontal, 24)
                    dateTabsRow().padding(.bottom, 8)
                    RangeDatePicker(dateFrom: $dateFrom, dateTo: $dateTo, pickingFrom: $pickingFrom,
                                    minDate: tomorrow)
                        .padding(.horizontal, 8).frame(height: 340)
                }
                .padding(.bottom, 24)

                let canSave = selectedTransport != nil
                Button { prepareConfirmation() } label: {
                    Text(isEditing ? "Guardar cambios" : "Añadir a Próximos")
                        .font(.custom("Satoshi-Bold", size: 16))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(canSave ? accent : Color(.systemGray4), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                        .shadow(color: canSave ? accent.opacity(0.3) : .clear, radius: 12, y: 4)
                }
                .disabled(!canSave)
                .padding(.horizontal, 24).padding(.bottom, 36)
            }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .presentationDetents([.large])
        .sheet(isPresented: $showRoutePicker) {
            RouteWizardSheet(airports: $selectedAirports, returnAirports: $selectedReturnAirports,
                             airlines: $selectedAirlines, hasLayover: $hasLayover, onDone: {})
        }

        if showConfirmation {
            plannedConfirmCard(
                onSave: {
                    showConfirmation = false
                    let title: String? = tripTitle.trimmingCharacters(in: .whitespaces).isEmpty ? nil
                        : tripTitle.trimmingCharacters(in: .whitespaces)
                    let airports = confirmAirports.map { TripAirport(iata: $0.iata, count: $0.count) }
                    let airlines = confirmAirlines.map { TripAirline(name: $0.name, count: $0.count) }
                    onSave(dateFrom, dateTo, selectedTransport, title, airports, airlines, flightInfo.hasAnyData ? flightInfo : nil)
                    dismiss()
                },
                onCancel: { showConfirmation = false }
            )
        }
        }
    }

    private func prepareConfirmation() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        confirmVisits = [VisitEntry(isoCode: "", flagEmoji: flagEmoji, name: countryName, count: 1)]
        if selectedTransport == "✈️" {
            var apC: [String: Int] = [:]
            for ap in selectedAirports { apC[ap.iata, default: 0] += ap.count }
            for ap in selectedReturnAirports { apC[ap.iata, default: 0] += ap.count }
            confirmAirports = apC.map { AirportConfirmEntry(iata: $0.key, count: $0.value) }.sorted { $0.iata < $1.iata }
            confirmAirlines = selectedAirlines.map { AirlineConfirmEntry(name: $0.name, count: $0.count) }
        } else {
            confirmAirports = []
            confirmAirlines = []
        }
        showConfirmation = true
    }

    @ViewBuilder
    private func plannedConfirmCard(onSave: @escaping () -> Void, onCancel: @escaping () -> Void) -> some View {
        confirmCardContent(
            confirmVisits: $confirmVisits, confirmAirports: $confirmAirports, confirmAirlines: $confirmAirlines,
            accent: accent, onSave: onSave, onCancel: onCancel
        )
    }
}

private struct confirmCardContent: View {
    @Binding var confirmVisits: [VisitEntry]
    @Binding var confirmAirports: [AirportConfirmEntry]
    @Binding var confirmAirlines: [AirlineConfirmEntry]
    let accent: Color
    let onSave: () -> Void
    let onCancel: () -> Void
    @State private var isSaving: Bool = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    ZStack {
                        Circle().fill(accent.opacity(0.12)).frame(width: 44, height: 44)
                        Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundStyle(accent)
                    }
                    Text("Confirmar viaje")
                        .font(.custom("Satoshi-Bold", size: 18))
                    Text("Ajusta los conteos si es necesario")
                        .font(.palatino(.caption))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20).padding(.bottom, 16)

                Rectangle().fill(Color(.systemGray5)).frame(height: 0.5)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if !confirmVisits.isEmpty {
                            sectionHeader("PAÍSES")
                            ForEach($confirmVisits) { $entry in
                                counterRow(leading: {
                                    HStack(spacing: 10) {
                                        if !entry.flagEmoji.isEmpty { FlagLabel(emoji: entry.flagEmoji, size: 22) }
                                        Text(entry.name).font(.palatino(.body)).lineLimit(1)
                                    }
                                }, count: $entry.count, accent: accent)
                            }
                        }
                        if !confirmAirports.isEmpty {
                            sectionHeader("AEROPUERTOS")
                            ForEach($confirmAirports) { $ap in
                                counterRow(leading: {
                                    HStack(spacing: 8) {
                                        Text("✈️").font(.system(size: 18))
                                        Text(ap.iata).font(.custom("Satoshi-Bold", size: 15))
                                    }
                                }, count: $ap.count, accent: accent)
                            }
                        }
                        if !confirmAirlines.isEmpty {
                            sectionHeader("AEROLÍNEAS")
                            ForEach($confirmAirlines) { $al in
                                counterRow(leading: {
                                    Text(al.name).font(.palatino(.body)).lineLimit(1)
                                }, count: $al.count, accent: accent)
                            }
                        }
                    }
                }
                .frame(maxHeight: 280)

                Rectangle().fill(Color(.systemGray5)).frame(height: 0.5)

                HStack(spacing: 10) {
                    Button { if !isSaving { onCancel() } } label: {
                        Text("Cancelar")
                            .font(.custom("Satoshi-Medium", size: 15))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.primary)
                    }.buttonStyle(.plain).disabled(isSaving)
                    Button {
                        guard !isSaving else { return }
                        isSaving = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            onSave()
                        }
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Text("Guardar").font(.custom("Satoshi-Bold", size: 15))
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(accent, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                    }.buttonStyle(.plain).disabled(isSaving)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 18)
            .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
        }
        .presentationBackground(.clear)
        .interactiveDismissDisabled(true)
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary).tracking(0.8)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
    }

    @ViewBuilder
    private func counterRow<L: View>(leading: () -> L, count: Binding<Int>, accent: Color) -> some View {
        HStack(spacing: 10) {
            leading()
            Spacer()
            HStack(spacing: 14) {
                Button { if count.wrappedValue > 0 { count.wrappedValue -= 1 } } label: {
                    Text("−").font(.system(size: 18, weight: .medium))
                        .frame(width: 34, height: 34)
                        .background(Color(.systemGray5), in: Circle())
                        .foregroundStyle(.primary)
                }.buttonStyle(.plain)
                Text("\(count.wrappedValue)")
                    .font(.custom("Satoshi-Bold", size: 16))
                    .frame(minWidth: 28, alignment: .center)
                Button { count.wrappedValue += 1 } label: {
                    Text("+").font(.system(size: 18, weight: .medium))
                        .frame(width: 34, height: 34)
                        .background(accent, in: Circle())
                        .foregroundStyle(.white)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        Rectangle().fill(Color(.systemGray6)).frame(height: 1).padding(.leading, 16)
    }
}


// MARK: - Estadísticas de transporte
struct TransportStatsSheet: View {
    let visitedCountries: [Country]
    let trips: [Trip]
    let allFeatures: [CountryFeature]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTransportFilter: (String, String)? = nil
    @State private var showAirportStats = false
    @State private var showAirlineStats = false
    @State private var showSeatStats = false
    @State private var showSeatPositionStats = false
    @State private var showSubscription: Bool = false
    @AppStorage("isRaskmapPro") private var isRaskmapPro: Bool = false

    private let transports = PlannedDatePickerSheet.transports

    private var pastTrips: [Trip] {
        let today = Calendar.current.startOfDay(for: Date())
        return trips.filter { Calendar.current.startOfDay(for: $0.effectiveEndDate) <= today }
    }

    private var counts: [(emoji: String, label: String, count: Int)] {
        // Cuenta TRAMOS (legs), no viajes. Regla clave para el avión:
        //  - 1 vuelo = 1 tramo, es decir 1 despegue + 1 aterrizaje.
        //  - Ida directa MAD→NRT = 1 vuelo.
        //  - Ida con escala MAD→DXB→NRT = 2 vuelos.
        //  - Ida y vuelta directa = 2 vuelos.
        //  - Ida y vuelta ambas con escala = 4 vuelos.
        // Para otros transportes cada `TripSegment` cuenta como 1 uso.
        let today = Calendar.current.startOfDay(for: Date())
        var byKey: [String: Int] = [:]

        func bump(_ emoji: String, _ legs: Int) {
            guard legs > 0 else { return }
            // Normalizamos 🚶 a 🚶🏻 (skin-tone) para agrupar caminatas.
            let key = emoji == "🚶" ? "🚶🏻" : emoji
            byKey[key, default: 0] += legs
        }

        // Recorremos sólo los viajes PRIMARIOS — los `isSegmentChild` son
        // estancias por país, no tramos de transporte (ya cuentan en el
        // primario a través de `tripSegments`).
        for trip in pastTrips where !trip.isSegmentChild {
            let segs = trip.tripSegments
            if segs.isEmpty {
                // Legacy sin segments — nos apoyamos en trip.transport.
                let tr = trip.transport ?? ""
                if tr == "✈️" {
                    // tripAirports es deduplicado con `count` de touches por
                    // aeropuerto (despegue + aterrizaje). legs = sum/2.
                    // Ver comentario detallado en WrappedStats.compute().
                    let totalTouches = trip.tripAirports.reduce(0) { $0 + $1.count }
                    let legs = max(1, totalTouches / 2)
                    bump(tr, legs)
                } else if !tr.isEmpty {
                    bump(tr, 1)
                }
            } else {
                for seg in segs {
                    let tr = seg.transport
                    if tr == "✈️" {
                        let outLegs = max(0, (seg.airports?.count ?? 0) - 1)
                        let retLegs = max(0, (seg.returnAirports?.count ?? 0) - 1)
                        bump(tr, max(1, outLegs + retLegs))
                    } else if !tr.isEmpty {
                        bump(tr, 1)
                    }
                }
            }
        }

        // Países visitados marcados a mano SIN trip asociado (legacy).
        let isoCodesWithPastTrips = Set(pastTrips.map { $0.isoCode })
        for country in visitedCountries {
            guard !isoCodesWithPastTrips.contains(country.isoCode) else { continue }
            let endDate = country.plannedDateTo ?? country.plannedDate
            if let end = endDate, Calendar.current.startOfDay(for: end) > today { continue }
            if let tr = country.transport, !tr.isEmpty {
                bump(tr, 1)
            }
        }

        return transports.compactMap { t -> (emoji: String, label: String, count: Int)? in
            let key = t.emoji == "🚶🏻" ? "🚶🏻" : t.emoji
            let total = byKey[key] ?? 0
            guard total > 0 else { return nil }
            return (t.emoji, t.label, total)
        }.sorted { $0.count > $1.count }
    }

    // Total = suma de los `count` mostrados por transporte (es decir, suma
    // de tramos), para que el "total" cuadre con la lista de barras de la
    // pantalla y no devuelva el nº de Trips primarios.
    private var totalTrips: Int { counts.reduce(0) { $0 + $1.count } }

    // Top airports by count
    private var topAirports: [(iata: String, name: String, country: String, count: Int)] {
        var counts: [String: Int] = [:]
        var lastDate: [String: Date] = [:]

        func add(iata: String, cnt: Int, date: Date) {
            counts[iata, default: 0] += cnt
            if let prev = lastDate[iata] { if date > prev { lastDate[iata] = date } }
            else { lastDate[iata] = date }
        }

        for trip in pastTrips where !trip.isSegmentChild {
            let flightSegs = trip.tripSegments.filter { $0.transport == "✈️" }
            if !flightSegs.isEmpty {
                for seg in flightSegs {
                    var apC: [String: Int] = [:]
                    for ap in seg.airports ?? []       { apC[ap.iata, default: 0] += ap.count }
                    for ap in seg.returnAirports ?? [] { apC[ap.iata, default: 0] += ap.count }
                    for (iata, cnt) in apC { add(iata: iata, cnt: cnt, date: seg.dateFrom) }
                }
            } else if trip.transport == "✈️" {
                for (iata, cnt) in trip.airportCountForStats { add(iata: iata, cnt: cnt, date: trip.dateFrom) }
            }
        }

        return counts.map { iata, count -> (iata: String, name: String, country: String, count: Int) in
            let ap = RoutePickerSheet.allAirports.first { $0.iata == iata }
            return (iata, ap?.name ?? iata, ap?.country ?? "", count)
        }.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return (lastDate[$0.iata] ?? .distantPast) > (lastDate[$1.iata] ?? .distantPast)
        }
    }

    private var topAirlines: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        var lastDate: [String: Date] = [:]

        func add(name: String, cnt: Int, date: Date) {
            counts[name, default: 0] += cnt
            if let prev = lastDate[name] { if date > prev { lastDate[name] = date } }
            else { lastDate[name] = date }
        }

        for trip in pastTrips where !trip.isSegmentChild {
            let flightSegs = trip.tripSegments.filter { $0.transport == "✈️" }
            if !flightSegs.isEmpty {
                for seg in flightSegs {
                    for al in seg.airlines ?? [] { add(name: al.name, cnt: al.count, date: seg.dateFrom) }
                }
            } else if trip.transport == "✈️" {
                for al in trip.tripAirlines where !al.name.isEmpty { add(name: al.name, cnt: al.count, date: trip.dateFrom) }
            }
        }

        return counts.map { ($0.key, $0.value) }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return (lastDate[$0.0] ?? .distantPast) > (lastDate[$1.0] ?? .distantPast)
        }
    }

    private var topSeats: [(seat: String, count: Int)] {
        var counts: [String: Int] = [:]
        for trip in pastTrips where !trip.isSegmentChild {
            let segs = trip.tripSegments
            if segs.isEmpty {
                if trip.transport == "✈️", let info = trip.flightDetails {
                    for leg in info.allLegs where !leg.seatNumber.isEmpty {
                        counts[leg.seatNumber, default: 0] += 1
                    }
                }
            } else {
                for seg in segs where seg.transport == "✈️" {
                    if let info = seg.flightInfo {
                        for leg in info.allLegs where !leg.seatNumber.isEmpty {
                            counts[leg.seatNumber, default: 0] += 1
                        }
                    }
                }
            }
        }
        return counts.map { ($0.key, $0.value) }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0 < $1.0
        }
    }

    private var topSeatPositions: [(position: String, count: Int)] {
        var counts: [String: Int] = [:]
        for trip in pastTrips where !trip.isSegmentChild {
            let segs = trip.tripSegments
            if segs.isEmpty {
                if trip.transport == "✈️", let info = trip.flightDetails {
                    for leg in info.allLegs where !leg.seatPosition.isEmpty {
                        counts[leg.seatPosition, default: 0] += 1
                    }
                }
            } else {
                for seg in segs where seg.transport == "✈️" {
                    if let info = seg.flightInfo {
                        for leg in info.allLegs where !leg.seatPosition.isEmpty {
                            counts[leg.seatPosition, default: 0] += 1
                        }
                    }
                }
            }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    /// Suma de km gran-circular volados en TODOS los segmentos ✈️ (ida + vuelta)
    /// + trips legacy con `tripAirports` consecutivos. Usa `AirportCoordinates`
    /// para resolver IATAs a coordenadas; pares con coords desconocidas se
    /// saltan (no rompen el total).
    private var totalKilometersFlown: Int {
        var total: Double = 0
        func addPair(_ a: String, _ b: String) {
            guard a != b,
                  let ca = AirportCoordinates.coordinate(for: a),
                  let cb = AirportCoordinates.coordinate(for: b) else { return }
            // Haversine en km (R = 6371).
            let lat1 = ca.latitude * .pi / 180, lon1 = ca.longitude * .pi / 180
            let lat2 = cb.latitude * .pi / 180, lon2 = cb.longitude * .pi / 180
            let dLat = lat2 - lat1, dLon = lon2 - lon1
            let h = sin(dLat / 2) * sin(dLat / 2)
                  + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
            let c = 2 * atan2(sqrt(h), sqrt(1 - h))
            total += 6371 * c
        }
        for trip in pastTrips where !trip.isSegmentChild {
            for seg in trip.tripSegments where seg.transport == "✈️" {
                let outs = seg.airports?.map(\.iata) ?? []
                for i in 0..<max(0, outs.count - 1) { addPair(outs[i], outs[i + 1]) }
                let rets = seg.returnAirports?.map(\.iata) ?? []
                for i in 0..<max(0, rets.count - 1) { addPair(rets[i], rets[i + 1]) }
            }
            // Legacy: solo si exactamente 2 aeropuertos (round-trip directo).
            if trip.tripSegments.isEmpty, trip.transport == "✈️", trip.tripAirports.count == 2 {
                addPair(trip.tripAirports[0].iata, trip.tripAirports[1].iata)
                let touches = trip.tripAirports.reduce(0) { $0 + $1.count }
                if touches >= 4 {
                    // Round-trip: cuenta también la vuelta (mismo par).
                    addPair(trip.tripAirports[1].iata, trip.tripAirports[0].iata)
                }
            }
        }
        return Int(total.rounded())
    }

    private static let kmFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.groupingSeparator = "."
        nf.maximumFractionDigits = 0
        return nf
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // ── Gráfica centrada ──
                    VStack(spacing: 4) {
                        Text("\(totalTrips)")
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                        Text("total")
                            .font(.palatino(.subheadline)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    // Card de km volados — visible solo si hay vuelos con coordenadas.
                    let km = totalKilometersFlown
                    if km > 0 {
                        HStack(spacing: 12) {
                            Image(systemName: "airplane")
                                .font(.system(size: 22))
                                .foregroundStyle(Color(red: 64/255, green: 114/255, blue: 212/255))
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("KM VOLADOS").font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary).tracking(0.8)
                                Text("\(Self.kmFormatter.string(from: NSNumber(value: km)) ?? "\(km)") km")
                                    .font(.custom("Satoshi-Bold", size: 22))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 18).padding(.vertical, 14)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 24)
                    }

                    if counts.isEmpty {
                        Text("Añade el medio de transporte en tus viajes para ver estadísticas.")
                            .font(.palatino(.subheadline)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal, 32)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(counts, id: \.emoji) { item in
                                Button { selectedTransportFilter = (item.emoji, item.label) } label: {
                                    HStack(spacing: 16) {
                                        Text(item.emoji).font(.system(size: 36)).frame(width: 50)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.label).font(.palatino(.body, weight: .bold)).foregroundStyle(.primary)
                                            GeometryReader { geo in
                                                let maxCount = counts.first?.count ?? 1
                                                let width = geo.size.width * CGFloat(item.count) / CGFloat(maxCount)
                                                RoundedRectangle(cornerRadius: 4).fill(Color.blue.opacity(0.7))
                                                    .frame(width: max(width, 4), height: 8)
                                            }.frame(height: 8)
                                        }
                                        Text("\(item.count)").font(.palatino(.title3, weight: .bold)).foregroundStyle(.primary).frame(width: 36, alignment: .trailing)
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 32)
                    }

                    // ── Cuadrantes aeropuertos / aerolíneas ──
                    HStack(spacing: 12) {
                            // Aeropuertos
                            Button { showAirportStats = true } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("✈️ Aeropuertos").font(.palatino(.caption, weight: .bold)).foregroundStyle(.secondary)
                                    if topAirports.isEmpty {
                                        Text("Sin datos").font(.palatino(.caption)).foregroundStyle(.secondary)
                                    } else {
                                        ForEach(topAirports.prefix(3), id: \.iata) { ap in
                                            HStack(spacing: 6) {
                                                if let a2 = countryA2(ap.country) {
                                                    FlagLabel(emoji: flagEmoji(a2), size: 12)
                                                }
                                                Text(ap.iata).font(.palatino(.caption, weight: .bold))
                                                Spacer()
                                                Text("\(ap.count)x").font(.palatino(.caption)).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)

                            // Aerolíneas
                            Button { showAirlineStats = true } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("🛫 Aerolíneas").font(.palatino(.caption, weight: .bold)).foregroundStyle(.secondary)
                                    if topAirlines.isEmpty {
                                        Text("Sin datos").font(.palatino(.caption)).foregroundStyle(.secondary)
                                    } else {
                                        ForEach(topAirlines.prefix(3), id: \.name) { al in
                                            HStack {
                                                Text(al.name).font(.palatino(.caption)).lineLimit(1)
                                                Spacer()
                                                Text("\(al.count)x").font(.palatino(.caption)).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 24)

                    // ── Cuadrantes asientos / tipo asiento ──
                    HStack(spacing: 12) {
                        Button { showSeatStats = true } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("💺 Asientos").font(.palatino(.caption, weight: .bold)).foregroundStyle(.secondary)
                                if topSeats.isEmpty {
                                    Text("Sin datos").font(.palatino(.caption)).foregroundStyle(.secondary)
                                } else {
                                    ForEach(topSeats.prefix(3), id: \.seat) { s in
                                        HStack {
                                            Text(s.seat).font(.palatino(.caption, weight: .bold))
                                            Spacer()
                                            Text("\(s.count)x").font(.palatino(.caption)).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        Button { showSeatPositionStats = true } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("🪟 Tipo asiento").font(.palatino(.caption, weight: .bold)).foregroundStyle(.secondary)
                                if topSeatPositions.isEmpty {
                                    Text("Sin datos").font(.palatino(.caption)).foregroundStyle(.secondary)
                                } else {
                                    ForEach(topSeatPositions.prefix(3), id: \.position) { p in
                                        HStack {
                                            Text(p.position.capitalized).font(.palatino(.caption)).lineLimit(1)
                                            Spacer()
                                            Text("\(p.count)x").font(.palatino(.caption)).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 24)
                }
                .blur(radius: isRaskmapPro ? 0 : 10)
                .allowsHitTesting(isRaskmapPro)
                .overlay {
                    if !isRaskmapPro {
                        Button { showSubscription = true } label: {
                            VStack(spacing: 10) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.purple)
                                Text("Función Pro")
                                    .font(.palatino(.body, weight: .bold))
                                    .foregroundStyle(.purple)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Transporte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
            .sheet(item: Binding(
                get: { selectedTransportFilter.map { TransportFilter(emoji: $0.0, label: $0.1) } },
                set: { _ in selectedTransportFilter = nil }
            )) { filter in
                // Avión → lista de VUELOS (tramos), no trayectos. El resto de
                // transportes siguen mostrando la lista de viajes (1 viaje =
                // 1 fila), que es coherente con cómo `counts` cuenta para
                // esos medios (1 segmento = 1 uso).
                if filter.emoji == "✈️" {
                    FlightLegsListSheet(trips: trips, allFeatures: allFeatures)
                } else {
                    TransportTripsListSheet(transportEmoji: filter.emoji, transportLabel: filter.label, trips: trips, allFeatures: allFeatures)
                }
            }
            .sheet(isPresented: $showAirportStats) {
                AirportStatsSheet(airports: topAirports, allFeatures: allFeatures)
            }
            .sheet(isPresented: $showAirlineStats) {
                AirlineStatsSheet(airlines: topAirlines)
            }
            .sheet(isPresented: $showSeatStats) {
                SeatStatsSheet(seats: topSeats)
            }
            .sheet(isPresented: $showSeatPositionStats) {
                SeatPositionStatsSheet(positions: topSeatPositions)
            }
            .sheet(isPresented: $showSubscription) { SubscriptionSheet() }
        }
        .presentationDetents([.large])
        .appColorScheme()
    }

    private func countryA2(_ iso2: String) -> String? { iso2.count == 2 ? iso2 : nil }
    private func flagEmoji(_ a2: String) -> String {
        a2.uppercased().unicodeScalars.compactMap {
            Unicode.Scalar(127397 + $0.value).map { String($0) }
        }.joined()
    }
}

struct TransportFilter: Identifiable {
    var id: String { emoji + label }
    let emoji: String
    let label: String
}

// MARK: - Lista de VUELOS (tramos) — drill-down del ✈️ en "Tus medios"
/// Distinto a `TransportTripsListSheet`: aquí mostramos TRAMOS (legs) de
/// avión, no viajes. Un round-trip con escala = 4 filas (4 vuelos). El usuario
/// pidió expresamente que el drill-down del avión liste vuelos, no trayectos.
struct FlightLegsListSheet: View {
    let trips: [Trip]
    let allFeatures: [CountryFeature]
    @Environment(\.dismiss) private var dismiss

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.locale = Locale(identifier: "es_ES"); return f
    }()

    /// Un tramo de avión = despegue + aterrizaje.
    private struct FlightLeg: Identifiable {
        let id = UUID()
        let originIATA: String
        let destIATA: String
        let date: Date
        let tripTitle: String?
        let tripIsoCode: String
        let airline: String?
        let direction: Direction
        enum Direction { case outbound, returning }
    }

    private var legs: [FlightLeg] {
        let today = Calendar.current.startOfDay(for: Date())
        var result: [FlightLeg] = []
        for trip in trips where !trip.isSegmentChild {
            guard Calendar.current.startOfDay(for: trip.dateFrom) <= today else { continue }
            let segs = trip.tripSegments.filter { $0.transport == "✈️" }
            if !segs.isEmpty {
                for seg in segs {
                    let airline = seg.airlines?.first?.name
                    // Outbound
                    if let aps = seg.airports, aps.count >= 2 {
                        let outDate = seg.dateFrom
                        for i in 0..<(aps.count - 1) {
                            result.append(FlightLeg(
                                originIATA: aps[i].iata,
                                destIATA: aps[i+1].iata,
                                date: outDate,
                                tripTitle: trip.title,
                                tripIsoCode: trip.isoCode,
                                airline: airline,
                                direction: .outbound
                            ))
                        }
                    }
                    // Return
                    if let raps = seg.returnAirports, raps.count >= 2 {
                        let retDate = seg.dateTo ?? seg.dateFrom
                        for i in 0..<(raps.count - 1) {
                            result.append(FlightLeg(
                                originIATA: raps[i].iata,
                                destIATA: raps[i+1].iata,
                                date: retDate,
                                tripTitle: trip.title,
                                tripIsoCode: trip.isoCode,
                                airline: airline,
                                direction: .returning
                            ))
                        }
                    }
                }
            } else if trip.transport == "✈️", trip.tripAirports.count >= 2 {
                // Legacy sin segments — no tenemos orden real de la ruta,
                // así que representamos los pares deducibles como una sola
                // fila "A ↔ B" con la fecha del trip.
                let iatas = trip.tripAirports.map { $0.iata }
                if iatas.count == 2 {
                    let totalTouches = trip.tripAirports.reduce(0) { $0 + $1.count }
                    let numLegs = max(1, totalTouches / 2)
                    for i in 0..<numLegs {
                        result.append(FlightLeg(
                            originIATA: i % 2 == 0 ? iatas[0] : iatas[1],
                            destIATA:   i % 2 == 0 ? iatas[1] : iatas[0],
                            date: trip.dateFrom,
                            tripTitle: trip.title,
                            tripIsoCode: trip.isoCode,
                            airline: trip.tripAirlines.first?.name,
                            direction: i % 2 == 0 ? .outbound : .returning
                        ))
                    }
                } else {
                    // >2 aeropuertos deduplicados: como no hay orden fiable,
                    // mostramos un único "resumen" con los extremos.
                    result.append(FlightLeg(
                        originIATA: iatas.first ?? "",
                        destIATA: iatas.last ?? "",
                        date: trip.dateFrom,
                        tripTitle: trip.title,
                        tripIsoCode: trip.isoCode,
                        airline: trip.tripAirlines.first?.name,
                        direction: .outbound
                    ))
                }
            }
        }
        return result.sorted { $0.date > $1.date }
    }

    private func flagEmoji(forIATA iata: String) -> String {
        let a2 = RoutePickerSheet.allAirports.first { $0.iata == iata }?.country ?? ""
        guard a2.count == 2 else { return "🌐" }
        return a2.uppercased().unicodeScalars.compactMap {
            Unicode.Scalar(127397 + $0.value).map { String($0) }
        }.joined()
    }

    var body: some View {
        NavigationStack {
            List {
                if legs.isEmpty {
                    Text("Aún no has registrado vuelos.")
                        .font(.palatino(.body))
                        .foregroundStyle(.secondary)
                        .padding()
                }
                ForEach(legs) { leg in
                    HStack(spacing: 12) {
                        // Banderas origen → destino
                        HStack(spacing: 4) {
                            FlagLabel(emoji: flagEmoji(forIATA: leg.originIATA), size: 20)
                            Text("→").font(.caption).foregroundStyle(.secondary)
                            FlagLabel(emoji: flagEmoji(forIATA: leg.destIATA), size: 20)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(leg.originIATA)
                                    .font(.palatino(.body, weight: .bold))
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(leg.destIATA)
                                    .font(.palatino(.body, weight: .bold))
                            }
                            HStack(spacing: 6) {
                                Text(Self.fmt.string(from: leg.date))
                                    .font(.palatino(.caption))
                                    .foregroundStyle(.secondary)
                                if let airline = leg.airline, !airline.isEmpty {
                                    Text("·")
                                        .font(.palatino(.caption))
                                        .foregroundStyle(.secondary)
                                    Text(airline)
                                        .font(.palatino(.caption))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.plain)
            .navigationTitle("✈️ \(legs.count) \(legs.count == 1 ? "vuelo" : "vuelos")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .presentationDetents([.large])
    }
}


// MARK: - Historial de viajes de un país
struct CountryTripsSheet: View {
    @Bindable var country: Country
    let trips: [Trip]
    let displayName: String
    let flagEmoji: String
    var features: [CountryFeature] = []

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete: Trip? = nil
    @State private var showDeleteConfirm: Bool = false
    @State private var showCounterInfo: Bool = false
    @State private var showLivedHereInfo: Bool = false
    @State private var editingTrip: Trip? = nil
    @State private var sortNewestFirst: Bool = true
    @State private var showSortToast: Bool = false

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.locale = Locale(identifier: "es_ES"); return f
    }()

    private var sortedTrips: [Trip] {
        trips.sorted { a, b in
            sortNewestFirst ? a.dateFrom > b.dateFrom : a.dateFrom < b.dateFrom
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(
                        get: { country.hasLived },
                        set: { country.hasLived = $0; try? modelContext.save() }
                    )) {
                        HStack(spacing: 6) {
                            Text("He vivido aquí").font(.palatino(.body))
                            Button { showLivedHereInfo = true } label: {
                                Image(systemName: "info.circle")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section(header: Text("Visitas manuales").font(.palatino(.caption, weight: .bold))) {
                    HStack {
                        Text("Contador manual")
                            .font(.palatino(.body))
                        Button {
                            showCounterInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Stepper("\(country.visitCount)", value: Binding(
                            get: { country.visitCount },
                            set: { country.visitCount = $0; try? modelContext.save() }
                        ), in: 0...99)
                        .labelsHidden()
                        Text("\(country.visitCount)x")
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }

                // Registered trips
                if !sortedTrips.isEmpty {
                    Section(header: Text("Viajes registrados (\(sortedTrips.count))").font(.palatino(.caption, weight: .bold))) {
                        ForEach(sortedTrips) { trip in tripRow(trip) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("\(flagEmoji) \(displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        sortNewestFirst.toggle()
                        showSortToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showSortToast = false }
                    } label: {
                        Image(systemName: sortNewestFirst ? "arrow.down.circle" : "arrow.up.circle")
                            .font(.body)
                    }
                }
            }
            .alert("¿Eliminar este viaje?", isPresented: $showDeleteConfirm, presenting: confirmDelete) { trip in
                Button("Eliminar", role: .destructive) {
                    var toDelete: [Trip]
                    if let groupID = trip.segmentGroupID {
                        let desc = FetchDescriptor<Trip>(predicate: #Predicate { $0.segmentGroupID == groupID })
                        toDelete = modelContext.fetchOrWarn(desc, fallback: [trip])
                    } else {
                        toDelete = [trip]
                    }
                    let affectedIsos = Set(toDelete.map { $0.isoCode })
                    for t in toDelete { modelContext.delete(t) }
                    try? modelContext.save()
                    for iso in affectedIsos {
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
                    try? modelContext.save()
                }
                Button("Cancelar", role: .cancel) {}
            } message: { trip in
                Text("\(Self.fmt.string(from: trip.dateFrom))\(trip.dateTo.map { " → \(Self.fmt.string(from: $0))" } ?? "")")
            }
            .sheet(item: $editingTrip, onDismiss: {
                guard country.status == .wantToVisit else { return }
                let today = Calendar.current.startOfDay(for: Date())
                let iso = country.isoCode
                let desc = FetchDescriptor<Trip>(predicate: #Predicate { $0.isoCode == iso })
                let allTrips = modelContext.fetchOrWarn(desc)
                let futureTrips = allTrips
                    .filter { Calendar.current.startOfDay(for: $0.dateFrom) > today && !$0.isSegmentChild }
                    .sorted { $0.dateFrom < $1.dateFrom }
                if let earliest = futureTrips.first {
                    country.transport = earliest.transport
                    country.plannedDate = earliest.dateFrom
                    country.plannedDateTo = earliest.dateTo
                    country.plannedTitle = earliest.title
                    try? modelContext.save()
                }
            }) { trip in
                EditTripSheet(trip: trip, features: features)
            }
        }
        .overlay {
            if showCounterInfo {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                        .onTapGesture { showCounterInfo = false }
                    VStack(spacing: 16) {
                        Text("Contador manual")
                            .font(.palatino(.subheadline, weight: .bold))
                        Text("Este contador es para sumar viajes que sabes que has hecho en el pasado a este país o territorio pero no recuerdas los datos para rellenarlo.")
                            .font(.palatino(.body))
                            .multilineTextAlignment(.center)
                        Button {
                            showCounterInfo = false
                        } label: {
                            Text("Cerrar")
                                .font(.palatino(.body, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 32)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showCounterInfo)
        .overlay {
            if showLivedHereInfo {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                        .onTapGesture { showLivedHereInfo = false }
                    VStack(spacing: 16) {
                        Text("He vivido aquí")
                            .font(.palatino(.subheadline, weight: .bold))
                        Text("Marca este país como uno en el que has vivido. Aparecerá una 🏠 junto a su contador en la lista de visitados y se contabiliza como visitado en todas las stats.")
                            .font(.palatino(.body))
                            .multilineTextAlignment(.center)
                        Button {
                            showLivedHereInfo = false
                        } label: {
                            Text("Cerrar")
                                .font(.palatino(.body, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 32)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showLivedHereInfo)
        .overlay {
            if showSortToast {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.white)
                    Text(sortNewestFirst ? "Más recientes primero" : "Más antiguos primero")
                        .font(.palatino(.subheadline, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
                .transition(.opacity.combined(with: .scale))
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSortToast)
        .presentationDetents([.large])
    }

    // Devuelve el trip padre de un child, o nil si no aplica
    private func resolvedParent(for trip: Trip) -> Trip? {
        guard trip.isSegmentChild, let groupID = trip.segmentGroupID else { return nil }
        let desc = FetchDescriptor<Trip>(predicate: #Predicate { t in t.segmentGroupID == groupID && !t.isSegmentChild })
        return modelContext.fetchFirstOrWarn(desc)
    }

    @ViewBuilder
    private func tripRow(_ trip: Trip) -> some View {
        // Para trips hijo (isSegmentChild), mostrar y editar siempre desde el padre
        let display = resolvedParent(for: trip) ?? trip
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(display.transport ?? "🌐").font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    if let t = display.title, !t.isEmpty {
                        Text(t).font(.palatino(.body, weight: .bold))
                    }
                    HStack(spacing: 4) {
                        Text(Self.fmt.string(from: display.dateFrom))
                            .font(.palatino(.caption)).foregroundStyle(.secondary)
                        if let to = display.dateTo {
                            Text("→").font(.palatino(.caption)).foregroundStyle(.secondary)
                            Text(Self.fmt.string(from: to))
                                .font(.palatino(.caption)).foregroundStyle(.secondary)
                        }
                        let tripDay = Calendar.current.startOfDay(for: display.dateFrom)
                        let todayDay = Calendar.current.startOfDay(for: Date())
                        if tripDay > todayDay {
                            let days = Calendar.current.dateComponents([.day], from: todayDay, to: tripDay).day ?? 0
                            Text("\(days)d")
                                .font(.palatino(.caption, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.blue, in: Capsule())
                        }
                    }
                    if display.transport == "✈️" {
                        let flightSeg = display.tripSegments.first(where: { $0.transport == "✈️" && $0.airports?.isEmpty == false })
                        if let seg = flightSeg, let aps = seg.airports, !aps.isEmpty {
                            Text(aps.map(\.iata).joined(separator: " → "))
                                .font(.palatino(.caption, weight: .bold)).foregroundStyle(.blue)
                            if let retAps = seg.returnAirports, !retAps.isEmpty {
                                Text(retAps.map(\.iata).joined(separator: " → "))
                                    .font(.palatino(.caption, weight: .bold)).foregroundStyle(.blue.opacity(0.65))
                            }
                        } else {
                            let aps = display.airports
                            if !aps.isEmpty {
                                Text(aps.joined(separator: " · "))
                                    .font(.palatino(.caption, weight: .bold)).foregroundStyle(.blue)
                            }
                        }
                        let als = display.airlines
                        if !als.isEmpty {
                            Text(als.joined(separator: ", "))
                                .font(.palatino(.caption)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                Spacer()
                Button { confirmDelete = trip; showDeleteConfirm = true } label: {
                    Image(systemName: "trash").foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain).frame(width: 28)
            }
            Button { editingTrip = display } label: {
                Label("Editar viaje", systemImage: "pencil.circle")
                    .font(.palatino(.caption)).foregroundStyle(.blue)
            }
            .buttonStyle(.plain).padding(.top, 2)
        }
        .padding(.vertical, 2)
    }
}


// MARK: - Edición de título de viaje inline
struct TripTitleEditRow: View {
    @Bindable var trip: Trip
    @Environment(\.modelContext) private var modelContext
    @State private var draft: String = ""
    @State private var editing: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        if editing {
            HStack(spacing: 12) {
                TextField("Título del viaje", text: $draft)
                    .font(.palatino(.caption))
                    .focused($focused)
                    .onAppear { draft = trip.title ?? "" }
                Spacer()
                Button {
                    let trimmedDraft = draft.trimmingCharacters(in: .whitespaces)
                    trip.title = trimmedDraft.isEmpty ? nil : trimmedDraft
                    try? modelContext.save()
                    editing = false
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .frame(width: 28)
            }
            .padding(.top, 6)
        } else {
            Button {
                draft = trip.title ?? ""
                editing = true
                focused = true
            } label: {
                Label(trip.title.map { "\"\($0)\"" } ?? "Añadir título…",
                      systemImage: "pencil")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Lista de viajes por transporte
struct TransportTripsListSheet: View {
    let transportEmoji: String
    let transportLabel: String
    let trips: [Trip]
    let allFeatures: [CountryFeature]
    @Environment(\.dismiss) private var dismiss

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.locale = Locale(identifier: "es_ES"); return f
    }()

    private var sorted: [Trip] {
        let today = Calendar.current.startOfDay(for: Date())
        let matchEmojis: Set<String> = transportEmoji == "🚶🏻" ? ["🚶🏻", "🚶"] : [transportEmoji]
        return trips.filter { trip in
            guard Calendar.current.startOfDay(for: trip.dateFrom) <= today else { return false }
            if trip.isSegmentChild { return matchEmojis.contains(trip.transport ?? "") }
            let segs = trip.tripSegments
            if segs.isEmpty { return matchEmojis.contains(trip.transport ?? "") }
            return segs.contains { seg in matchEmojis.contains(seg.transport) && seg.isoCodes.contains(trip.isoCode) }
        }.sorted { $0.dateFrom > $1.dateFrom }
    }

    private func countryName(for isoCode: String) -> String {
        allFeatures.first(where: { $0.isoCode == isoCode })?.localizedName ?? isoCode
    }
    private func flagEmoji(for isoCode: String) -> String {
        allFeatures.first(where: { $0.isoCode == isoCode })?.flagEmoji ?? "🌐"
    }

    var body: some View {
        NavigationStack {
            List(sorted) { trip in
                HStack(spacing: 10) {
                    FlagLabel(emoji: flagEmoji(for: trip.isoCode), size: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        if let t = trip.title, !t.isEmpty {
                            HStack(spacing: 6) {
                                Text(t).font(.palatino(.body, weight: .bold))
                                Text("|").foregroundStyle(.secondary)
                                Text(countryName(for: trip.isoCode)).font(.palatino(.body))
                            }
                        } else {
                            Text(countryName(for: trip.isoCode)).font(.palatino(.body))
                        }
                        HStack(spacing: 4) {
                            Text(Self.fmt.string(from: trip.dateFrom))
                                .font(.palatino(.caption)).foregroundStyle(.secondary)
                            if let to = trip.dateTo {
                                Text("→ \(Self.fmt.string(from: to))")
                                    .font(.palatino(.caption)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .listStyle(.plain)
            .navigationTitle("\(transportEmoji) \(transportLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .presentationDetents([.large])
    }
}


// MARK: - Editar viaje existente (desde lista Próximos)
struct EditTripSheet: View {
    @Bindable var trip: Trip
    let isForFuture: Bool
    let features: [CountryFeature]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTransport: String?
    @State private var tripTitle: String
    @State private var localDateFrom: Date
    @State private var localDateTo: Date?
    @State private var tripSegments: [TripSegment] = []
    @State private var showAddSegment = false
    @State private var editingSegment: TripSegment? = nil
    @State private var showSaveConfirmation = false
    @State private var confirmVisits: [VisitEntry] = []
    @State private var confirmAirports: [AirportConfirmEntry] = []
    @State private var confirmAirlines: [AirlineConfirmEntry] = []
    @State private var localAirports: [TripAirport] = []
    @State private var localReturnAirports: [TripAirport] = []
    @State private var localAirlines: [TripAirline] = []
    @State private var localHasLayover: Bool = false
    @State private var showRoutePicker: Bool = false
    @State private var localFlightInfo: FlightInfo = FlightInfo()
    /// IDs de segmentos cuyo panel "Detalles del vuelo" (asiento, posición, clase) está
    /// desplegado inline dentro de TRAMOS. Sólo aplica a segmentos ✈️.
    @State private var expandedSegmentIDs: Set<UUID> = []
    /// Toggles de escalas IDA/VUELTA para trips ✈️ legacy SIN segmentos. Se
    /// reconstruyen tras cada paso por `RouteWizardSheet` y se persisten en
    /// `trip.visitedLayoverISOs` al guardar. Para trips segment-based esto
    /// queda vacío — la edición pasa por AddSegmentSheet.
    @State private var legacyOutboundLayovers: [LayoverChoice] = []
    @State private var legacyReturnLayovers: [LayoverChoice] = []
    @State private var legacyVisitedLayoverISOs: Set<String> = []

    /// Binding que apunta al `flightInfo` del segmento con el id dado, materializando
    /// `nil` como `FlightInfo()` para edición y volviendo a `nil` cuando queda vacío.
    /// Usado por los `FlightInfoSection` inline en TRAMOS.
    private func segmentFlightInfoBinding(for segmentID: UUID) -> Binding<FlightInfo> {
        Binding(
            get: {
                tripSegments.first(where: { $0.id == segmentID })?.flightInfo ?? FlightInfo()
            },
            set: { newValue in
                guard let idx = tripSegments.firstIndex(where: { $0.id == segmentID }) else { return }
                tripSegments[idx].flightInfo = newValue.hasAnyData ? newValue : nil
            }
        )
    }

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.locale = Locale(identifier: "es_ES"); return f
    }()

    private static let segFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.locale = Locale(identifier: "es_ES"); return f
    }()

    /// Sección visual de toggles de escalas en el flujo legacy. Replica la
    /// estética de `AddSegmentSheet.layoverSection` pero usa
    /// `legacyVisitedLayoverISOs` como single source of truth. Title opcional
    /// (ya no separamos por dirección — un solo toggle por país).
    @ViewBuilder
    private func legacyLayoverSection(title: String?, choices: [LayoverChoice]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.85))
                    .tracking(0.8)
            }
            ForEach(choices) { choice in
                let checked = legacyVisitedLayoverISOs.contains(choice.isoA3)
                Button {
                    if checked { legacyVisitedLayoverISOs.remove(choice.isoA3) }
                    else       { legacyVisitedLayoverISOs.insert(choice.isoA3) }
                } label: {
                    HStack(spacing: 12) {
                        FlagLabel(emoji: choice.flag ?? "🌐", size: 22)
                        Text(choice.name).font(.palatino(.body)).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(checked ? accent : Color(.systemGray3))
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Reconstruye los toggles de escalas a partir de `localAirports` /
    /// `localReturnAirports`. Excluye país de salida y destino — solo aparecen
    /// los aeropuertos intermedios. Llamada al onAppear y tras cada wizard.
    private func deriveLegacyFlightCountries() {
        let allAps = RoutePickerSheet.allAirports

        func featureByA2(_ a2: String?) -> CountryFeature? {
            guard let a2 else { return nil }
            return features.first { $0.isoA2 == a2 }
        }

        let outRoute = effectiveFlightRoutes.outbound
        let retRoute = effectiveFlightRoutes.returnRt
        let departureA2 = allAps.first(where: { $0.iata == outRoute.first })?.country
        let destinationA2 = allAps.first(where: { $0.iata == outRoute.last })?.country
        let departureFeature = featureByA2(departureA2)
        let destinationFeature = featureByA2(destinationA2)

        let excludedISOs: Set<String> = Set(
            [departureFeature?.isoCode, destinationFeature?.isoCode].compactMap { $0 }
        )

        // Lista única deduplicada — un país aparece una sola vez aunque sea
        // escala en ida y vuelta (visitar es por país, no por dirección).
        // Preserva orden de primera aparición (ida primero, luego vuelta).
        var seen = excludedISOs
        var combined: [LayoverChoice] = []
        func addRoute(_ route: [String]) {
            guard route.count > 2 else { return }
            for iata in route.dropFirst().dropLast() {
                guard let a2 = allAps.first(where: { $0.iata == iata })?.country,
                      let f = featureByA2(a2),
                      seen.insert(f.isoCode).inserted else { continue }
                combined.append(LayoverChoice(
                    id: "lay_\(f.isoCode)", isoA3: f.isoCode,
                    flag: f.flagEmoji, name: f.localizedName))
            }
        }
        addRoute(outRoute)
        addRoute(retRoute)

        legacyOutboundLayovers = combined
        legacyReturnLayovers = []

        // Filtra el set persistido contra las escalas que realmente existen
        // en la ruta actual — evita ISOs huérfanas si el usuario reroutea.
        let realISOs = Set(combined.map(\.isoA3))
        legacyVisitedLayoverISOs = legacyVisitedLayoverISOs.intersection(realISOs)
    }

    /// Rutas efectivas de IDA y VUELTA para los trips ✈️ legacy sin segmentos.
    /// Si `localReturnAirports` viene poblado (segment-based o user añadió la
    /// vuelta vía wizard) lo usamos tal cual. Si está vacío pero `localAirports`
    /// luce como round-trip directo legacy ([MAD(c=2), ARN(c=2)]) sintetizamos
    /// la vuelta como ida invertida — solo para UI: el `FlightInfoSection`
    /// genera entonces N editores ida + N editores vuelta. La sintetización NO
    /// toca el @State, así que el save sigue persistiendo `localAirports` como
    /// estaba (counts=2 each) y no doblamos el conteo de aeropuertos.
    private var effectiveFlightRoutes: (outbound: [String], returnRt: [String]) {
        let outIatas = localAirports.map { $0.iata }
        if !localReturnAirports.isEmpty {
            return (outIatas, localReturnAirports.map { $0.iata })
        }
        // Heurística round-trip legacy: ≥2 aeropuertos y todos con count ≥ 2.
        let isLikelyRoundTrip = localAirports.count >= 2 &&
                                localAirports.allSatisfy { $0.count >= 2 }
        return isLikelyRoundTrip ? (outIatas, Array(outIatas.reversed())) : (outIatas, [])
    }

    // Calculated date range: from segments when present, else from local pickers
    private var calculatedDateFrom: Date {
        tripSegments.map(\.dateFrom).min() ?? localDateFrom
    }
    private var calculatedDateTo: Date? {
        if !tripSegments.isEmpty {
            let explicit = tripSegments.compactMap(\.dateTo).max()
            if let e = explicit { return e }
            let latestFrom = tripSegments.map(\.dateFrom).max()
            guard let latest = latestFrom, latest > calculatedDateFrom else { return nil }
            return latest
        }
        return localDateTo
    }

    private func segmentCountryNames(_ seg: TripSegment) -> String {
        if seg.transport == "✈️", let aps = seg.airports, !aps.isEmpty {
            var route = aps.map { $0.iata }.joined(separator: " → ")
            if let retAps = seg.returnAirports, !retAps.isEmpty {
                route += "  /  " + retAps.map { $0.iata }.joined(separator: " → ")
            }
            return route
        }
        return seg.isoCodes.compactMap { iso in features.first { $0.isoCode == iso }?.localizedName }.joined(separator: ", ")
    }

    init(trip: Trip, isForFuture: Bool = false, features: [CountryFeature] = []) {
        self.trip = trip
        self.isForFuture = isForFuture
        self.features = features
        // Estado en memoria siempre ordenado cronológicamente (el getter del
        // modelo ya ordena, pero lo dejamos explícito por claridad).
        _tripSegments = State(initialValue: trip.tripSegments.sorted { $0.dateFrom < $1.dateFrom })
        _selectedTransport = State(initialValue: trip.transport)
        _tripTitle = State(initialValue: trip.title ?? "")
        _localDateFrom = State(initialValue: trip.dateFrom)
        _localDateTo = State(initialValue: trip.dateTo)
        _localAirports = State(initialValue: trip.tripAirports)
        _localAirlines = State(initialValue: trip.tripAirlines)
        _localHasLayover = State(initialValue: trip.hasLayover)
        _localFlightInfo = State(initialValue: trip.flightDetails ?? FlightInfo())
        _legacyVisitedLayoverISOs = State(initialValue: Set(trip.visitedLayoverISOs ?? []))
    }

    private func prepareEditSaveConfirmation() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        guard !tripSegments.isEmpty else {
            // País de destino (siempre se cuenta como visitado).
            var visits: [VisitEntry] = []
            let mainFeat = features.first { $0.isoCode == trip.isoCode }
            visits.append(VisitEntry(
                isoCode: trip.isoCode,
                flagEmoji: mainFeat?.flagEmoji ?? "",
                name: mainFeat?.localizedName ?? trip.isoCode,
                count: 1))
            // Escalas marcadas como visitadas en el flujo legacy. Se filtran
            // contra las escalas reales para excluir ISOs huérfanas.
            let realISOs = Set(legacyOutboundLayovers.map(\.isoA3))
            for iso in legacyVisitedLayoverISOs.intersection(realISOs) where iso != trip.isoCode {
                let feat = features.first { $0.isoCode == iso }
                visits.append(VisitEntry(
                    isoCode: iso,
                    flagEmoji: feat?.flagEmoji ?? "",
                    name: feat?.localizedName ?? iso,
                    count: 1))
            }
            confirmVisits = visits
            var apCombined: [String: Int] = [:]
            for ap in localAirports { apCombined[ap.iata, default: 0] += ap.count }
            for ap in localReturnAirports { apCombined[ap.iata, default: 0] += ap.count }
            confirmAirports = apCombined.map { AirportConfirmEntry(iata: $0.key, count: $0.value) }.sorted { $0.iata < $1.iata }
            confirmAirlines = localAirlines.map { AirlineConfirmEntry(name: $0.name, count: $0.count) }
            if confirmAirports.isEmpty && confirmAirlines.isEmpty { performEditSave(); return }
            showSaveConfirmation = true
            return
        }
        var visitCounts: [String: Int] = [:]
        for seg in tripSegments {
            for iso in seg.isoCodes { visitCounts[iso, default: 0] += 1 }
        }
        visitCounts[trip.isoCode] = max(visitCounts[trip.isoCode, default: 0], 1)
        confirmVisits = visitCounts.map { (iso, count) in
            let feat = features.first { $0.isoCode == iso }
            return VisitEntry(isoCode: iso, flagEmoji: feat?.flagEmoji ?? "", name: feat?.localizedName ?? iso, count: count)
        }.sorted { a, b in
            if a.isoCode == trip.isoCode { return true }
            if b.isoCode == trip.isoCode { return false }
            return a.name < b.name
        }
        let apSegs = tripSegments.filter { $0.transport == "✈️" && $0.airports?.isEmpty == false }
        var apC: [String: Int] = [:]
        var alC: [String: Int] = [:]
        var alOrder: [String] = []
        for seg in apSegs {
            let vlISOs2 = Set(seg.visitedLayoverISOs ?? [])
            // Toques naturales (idéntico a `prepareConfirmation` de AddTrip).
            for ap in (seg.airports ?? [])       { apC[ap.iata, default: 0] += ap.count }
            for ap in (seg.returnAirports ?? []) { apC[ap.iata, default: 0] += ap.count }
            // Bonus +1 por cada IATA de escala cuyo país esté visitado (un
            // solo bonus por IATA aunque aparezca en ida y vuelta).
            let outIntermediate2 = (seg.airports ?? []).dropFirst().dropLast().map { $0.iata }
            let retIntermediate2 = (seg.returnAirports ?? []).dropFirst().dropLast().map { $0.iata }
            var bonusedIATAs: Set<String> = []
            for iata in outIntermediate2 + retIntermediate2 where bonusedIATAs.insert(iata).inserted {
                let a2 = RoutePickerSheet.allAirports.first { $0.iata == iata }?.country ?? ""
                guard let iso = features.first(where: { $0.isoA2 == a2 })?.isoCode,
                      vlISOs2.contains(iso) else { continue }
                apC[iata, default: 0] += 1
            }
            for al in (seg.airlines ?? []) {
                if alC[al.name] == nil { alOrder.append(al.name) }
                alC[al.name, default: 0] += al.count
            }
        }
        confirmAirports = apC.map { AirportConfirmEntry(iata: $0.key, count: $0.value) }.sorted { $0.iata < $1.iata }
        confirmAirlines = alOrder.map { AirlineConfirmEntry(name: $0, count: alC[$0] ?? 0) }
        // fallback: viajes guardados antes del sistema de segmentos
        if confirmAirports.isEmpty {
            confirmAirports = trip.tripAirports.map { AirportConfirmEntry(iata: $0.iata, count: $0.count) }
        }
        if confirmAirlines.isEmpty {
            confirmAirlines = trip.tripAirlines.map { AirlineConfirmEntry(name: $0.name, count: $0.count) }
        }
        showSaveConfirmation = true
    }

    private func performEditSave() {
        let trimmedTitle = tripTitle.trimmingCharacters(in: .whitespaces)
        trip.title = trimmedTitle.isEmpty ? nil : trimmedTitle
        if !trip.isSegmentChild {
            trip.dateFrom = calculatedDateFrom
            trip.dateTo = calculatedDateTo
            trip.transport = tripSegments.isEmpty ? selectedTransport : (tripSegments.first?.transport ?? selectedTransport ?? "🌍")
            let airplaneSeg = tripSegments.first(where: { $0.transport == "✈️" && ($0.airports?.isEmpty == false) })
            // Orden cronológico de aeropuertos. Para segment-based: iteramos
            // segmentos por dateFrom, y dentro de cada segmento ida → vuelta.
            // Para legacy: usamos `localAirports` (lo que tipeó el user en el
            // wizard, ya cronológico). El primer iata visto gana — esto evita
            // que el orden alfabético del confirm-dialog (ordenado para la UI)
            // o el orden hash del Dictionary contaminen `trip.tripAirports`,
            // que es lo que rendea `legacyAirportRoute` y otros consumidores.
            var apOrder: [String] = []
            var seenIatas: Set<String> = []
            if tripSegments.isEmpty {
                for ap in localAirports where seenIatas.insert(ap.iata).inserted { apOrder.append(ap.iata) }
                for ap in localReturnAirports where seenIatas.insert(ap.iata).inserted { apOrder.append(ap.iata) }
            } else {
                for seg in tripSegments.sorted(by: { $0.dateFrom < $1.dateFrom }) where seg.transport == "✈️" {
                    for ap in seg.airports ?? [] where seenIatas.insert(ap.iata).inserted { apOrder.append(ap.iata) }
                    for ap in seg.returnAirports ?? [] where seenIatas.insert(ap.iata).inserted { apOrder.append(ap.iata) }
                }
            }
            if !confirmAirports.isEmpty || !confirmAirlines.isEmpty {
                let countsByIata = Dictionary(confirmAirports.map { ($0.iata, $0.count) }, uniquingKeysWith: +)
                var ordered: [TripAirport] = apOrder.compactMap { iata in
                    guard let count = countsByIata[iata], count > 0 else { return nil }
                    return TripAirport(iata: iata, count: count)
                }
                // Defensivo: si el user añadió un iata en el dialog que no
                // estaba en segments/localAirports, lo añadimos al final.
                for entry in confirmAirports where !seenIatas.contains(entry.iata) && entry.count > 0 {
                    ordered.append(TripAirport(iata: entry.iata, count: entry.count))
                }
                trip.tripAirports = ordered
                trip.tripAirlines = confirmAirlines.map { TripAirline(name: $0.name, count: $0.count) }
            } else if tripSegments.isEmpty {
                trip.tripAirports = localAirports
                trip.tripAirlines = localAirlines
                trip.hasLayover = localHasLayover
            } else {
                trip.tripAirports = airplaneSeg?.airports ?? trip.tripAirports
                trip.tripAirlines = airplaneSeg?.airlines ?? trip.tripAirlines
            }
            if !tripSegments.isEmpty { trip.hasLayover = airplaneSeg?.hasLayover ?? trip.hasLayover }
            trip.tripSegments = tripSegments
            // Persistir escalas visitadas a nivel trip y limpiar el legacy
            // cuando el trip se convierte en segment-based.
            let legacyVisitedLayovers: [String]
            if tripSegments.isEmpty {
                trip.flightDetails = localFlightInfo.hasAnyData ? localFlightInfo : nil
                // Filtramos contra las escalas que realmente existen en la
                // ruta actual para no guardar ISOs huérfanas si el usuario
                // re-routea.
                let realISOs = Set(legacyOutboundLayovers.map(\.isoA3))
                legacyVisitedLayovers = Array(legacyVisitedLayoverISOs.intersection(realISOs))
                trip.visitedLayoverISOs = legacyVisitedLayovers.isEmpty ? nil : legacyVisitedLayovers
            } else {
                // Segment-based → escalas viven en seg.visitedLayoverISOs.
                trip.visitedLayoverISOs = nil
                legacyVisitedLayovers = []
            }
            // Delete old children — antes de re-crear arriba/abajo.
            if let groupID = trip.segmentGroupID {
                let desc = FetchDescriptor<Trip>(predicate: #Predicate { $0.segmentGroupID == groupID })
                for t in modelContext.fetchOrWarn(desc) where t.isSegmentChild { modelContext.delete(t) }
            }
            // Children para escalas visitadas en el path legacy non-segment.
            // Cada escala = 1 child trip de 1 día → aparece en lista del país,
            // marca `Country.status = .visited` (si el viaje es pasado) y se
            // refleja en el contador de días vía el stake de prio 50 que hace
            // `daysPerCountry` para `t.visitedLayoverISOs`.
            if tripSegments.isEmpty && !legacyVisitedLayovers.isEmpty {
                let groupID = trip.segmentGroupID ?? UUID().uuidString
                trip.segmentGroupID = groupID
                let today = Calendar.current.startOfDay(for: Date())
                let dayStart = Calendar.current.startOfDay(for: trip.dateFrom)
                let trimmedTitleStr = trip.title?.trimmingCharacters(in: .whitespaces) ?? ""
                for iso in legacyVisitedLayovers where iso != trip.isoCode {
                    let child = Trip(
                        isoCode: iso,
                        title: trimmedTitleStr.isEmpty ? nil : trimmedTitleStr,
                        dateFrom: trip.dateFrom,
                        dateTo: trip.dateFrom,   // 1 día (la escala dura el día del vuelo)
                        transport: "✈️",
                        tripAirports: [], tripAirlines: []
                    )
                    child.segmentGroupID = groupID
                    child.isSegmentChild = true
                    modelContext.insert(child)
                    if dayStart <= today {
                        let isoCopy = iso
                        let dd = FetchDescriptor<Country>(predicate: #Predicate { $0.isoCode == isoCopy })
                        if let country = modelContext.fetchFirstOrWarn(dd), country.status != .visited {
                            country.status = .visited
                            country.plannedDate = nil
                            country.plannedDateTo = nil
                            country.transport = nil
                        }
                    }
                }
            }
            if !tripSegments.isEmpty {
                let groupID = trip.segmentGroupID ?? UUID().uuidString
                trip.segmentGroupID = groupID
                let today = Calendar.current.startOfDay(for: Date())
                var countForIso: [String: Int] = [:]
                if !confirmVisits.isEmpty {
                    for entry in confirmVisits { countForIso[entry.isoCode] = entry.count }
                } else {
                    for seg in tripSegments { for iso in seg.isoCodes { countForIso[iso, default: 0] += 1 } }
                    countForIso[trip.isoCode] = max(countForIso[trip.isoCode, default: 0], 1)
                }
                // Extra visits for main country
                let segsForMain = tripSegments.filter { $0.isoCodes.contains(trip.isoCode) }
                let mainCount = countForIso[trip.isoCode] ?? 1
                for i in 0..<(mainCount - 1) {
                    let extraSeg = (i + 1) < segsForMain.count ? segsForMain[i + 1] : segsForMain.last
                    let extraTransport = extraSeg?.transport ?? trip.transport
                    var extraAps: [TripAirport] = []
                    var extraAls: [TripAirline] = []
                    if extraSeg?.transport == "✈️" {
                        var apC3: [String: Int] = [:]
                        for ap in extraSeg?.airports ?? [] { apC3[ap.iata, default: 0] += 1 }
                        for ap in extraSeg?.returnAirports ?? [] { apC3[ap.iata, default: 0] += 1 }
                        extraAps = apC3.map { TripAirport(iata: $0.key, count: $0.value) }
                        extraAls = extraSeg?.airlines ?? []
                    }
                    let extra = Trip(isoCode: trip.isoCode, title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                                    dateFrom: extraSeg?.dateFrom ?? calculatedDateFrom,
                                    dateTo: extraSeg?.dateTo ?? calculatedDateTo,
                                    transport: extraTransport, tripAirports: extraAps, tripAirlines: extraAls)
                    extra.hasLayover = extraSeg?.hasLayover ?? false
                    extra.segmentGroupID = groupID
                    extra.isSegmentChild = true
                    if let seg = extraSeg { extra.tripSegments = [seg] }
                    modelContext.insert(extra)
                }
                // Children for other countries
                for (iso, confirmedCount) in countForIso where iso != trip.isoCode && confirmedCount > 0 {
                    let segsWithIso = tripSegments.filter { $0.isoCodes.contains(iso) }
                    for i in 0..<confirmedCount {
                        let seg = i < segsWithIso.count ? segsWithIso[i] : segsWithIso.last
                        let d = seg?.dateFrom ?? calculatedDateFrom
                        let dTo = seg?.dateTo
                        let t = seg?.transport ?? "🌍"
                        var apC2: [String: Int] = [:]
                        if seg?.transport == "✈️" {
                            for ap in seg?.airports ?? [] { apC2[ap.iata, default: 0] += 1 }
                            for ap in seg?.returnAirports ?? [] { apC2[ap.iata, default: 0] += 1 }
                        }
                        let sAps = seg?.transport == "✈️" ? apC2.map { TripAirport(iata: $0.key, count: $0.value) } : []
                        let sAls = seg?.transport == "✈️" ? (seg?.airlines ?? []) : []
                        let child = Trip(isoCode: iso, title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                                        dateFrom: d, dateTo: dTo, transport: t,
                                        tripAirports: sAps, tripAirlines: sAls)
                        child.hasLayover = seg?.hasLayover ?? false
                        child.segmentGroupID = groupID
                        child.isSegmentChild = true
                        if let seg { child.tripSegments = [seg] }
                        modelContext.insert(child)
                        if Calendar.current.startOfDay(for: d) <= today {
                            let countryIso = iso
                            let dd = FetchDescriptor<Country>(predicate: #Predicate { $0.isoCode == countryIso })
                            if let country = modelContext.fetchFirstOrWarn(dd), country.status != .visited {
                                country.status = .visited
                                country.plannedDate = nil; country.plannedDateTo = nil; country.transport = nil
                            }
                        } else {
                            let countryIso = iso
                            let dd = FetchDescriptor<Country>(predicate: #Predicate { $0.isoCode == countryIso })
                            if let country = modelContext.fetchFirstOrWarn(dd) {
                                if country.status != .visited && country.status != .lived {
                                    country.status = .wantToVisit
                                    if country.plannedDate == nil || d < country.plannedDate! {
                                        country.plannedDate = d
                                        country.plannedDateTo = dTo
                                        country.transport = t
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        // Propagate title to siblings
        if let groupID = trip.segmentGroupID {
            let desc = FetchDescriptor<Trip>(predicate: #Predicate { $0.segmentGroupID == groupID })
            if let siblings = try? modelContext.fetch(desc) {
                for sibling in siblings { sibling.title = trimmedTitle.isEmpty ? nil : trimmedTitle }
            }
        }
        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private let accent = Color(red: 64/255, green: 114/255, blue: 212/255)

    var body: some View {
        ZStack {
        NavigationStack {
            ScrollView {
            VStack(spacing: 0) {
                // Título
                VStack(alignment: .leading, spacing: 8) {
                    Text("TÍTULO DEL VIAJE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary).tracking(1.0)
                        .padding(.horizontal, 24)
                    TextField("Ej: Vacaciones de verano", text: $tripTitle)
                        .font(.palatino(.body))
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 24)
                }
                .padding(.top, 24).padding(.bottom, 20)

                // MARK: Transporte + Fechas (solo viajes simples)
                if tripSegments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TRANSPORTE")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary).tracking(1.0)
                            .padding(.horizontal, 24)
                        HStack(spacing: 8) {
                            ForEach(PlannedDatePickerSheet.transports, id: \.emoji) { t in
                                let isSelected = selectedTransport == t.emoji
                                Button { selectedTransport = isSelected ? nil : t.emoji } label: {
                                    VStack(spacing: 4) {
                                        Text(t.emoji).font(.system(size: 20))
                                        Text(t.label).font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(isSelected ? accent : .secondary)
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(isSelected ? accent.opacity(0.1) : Color(.systemGray6),
                                                in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12)
                                        .stroke(isSelected ? accent.opacity(0.35) : Color.clear, lineWidth: 1.5))
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 20)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("FECHAS")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary).tracking(1.0)
                            .padding(.horizontal, 24)
                        VStack(spacing: 0) {
                            HStack {
                                Text("Desde").font(.palatino(.body))
                                Spacer()
                                DatePicker("", selection: $localDateFrom, displayedComponents: .date)
                                    .labelsHidden()
                                    .onChange(of: localDateFrom) { _, newVal in
                                        if let to = localDateTo, newVal > to { localDateTo = nil }
                                    }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            Rectangle().fill(Color(.systemGray5)).frame(height: 0.5).padding(.leading, 16)
                            HStack {
                                Text("Hasta (opcional)").font(.palatino(.body))
                                Spacer()
                                if localDateTo != nil {
                                    Button { localDateTo = nil } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                    }.buttonStyle(.plain).padding(.trailing, 4)
                                    DatePicker("", selection: Binding(
                                        get: { localDateTo ?? localDateFrom },
                                        set: { localDateTo = $0 }
                                    ), in: localDateFrom..., displayedComponents: .date).labelsHidden()
                                } else {
                                    Button {
                                        localDateTo = Calendar.current.date(byAdding: .day, value: 1, to: localDateFrom)
                                    } label: {
                                        Text("Añadir").foregroundStyle(accent).font(.palatino(.body))
                                    }.buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                        }
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 20)
                }

                // MARK: Ruta de vuelo
                if (selectedTransport == "✈️" || !localAirports.isEmpty) && tripSegments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("RUTA DE VUELO")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary).tracking(1.0)
                            .padding(.horizontal, 24)
                        Button { showRoutePicker = true } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(accent.opacity(0.1)).frame(width: 36, height: 36)
                                    Image(systemName: "airplane").font(.system(size: 15)).foregroundStyle(accent)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    if localAirports.isEmpty {
                                        Text("Añadir ruta de vuelo").font(.palatino(.body)).foregroundStyle(accent)
                                    } else {
                                        let routes = effectiveFlightRoutes
                                        Text(routes.outbound.joined(separator: " → "))
                                            .font(.palatino(.body)).foregroundStyle(.primary).lineLimit(1)
                                        if !routes.returnRt.isEmpty {
                                            Text(routes.returnRt.joined(separator: " → "))
                                                .font(.palatino(.caption)).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 24)
                        }.buttonStyle(.plain)
                    }
                    .padding(.bottom, 12)

                    // Para legacy round-trip directo guardado como [MAD(c=2), ARN(c=2)]
                    // sin `returnAirports` separado, sintetizamos la vuelta para que
                    // `FlightInfoSection` genere editores IDA + VUELTA en vez de uno solo.
                    let routes = effectiveFlightRoutes
                    FlightInfoSection(info: $localFlightInfo,
                                      outboundRoute: routes.outbound,
                                      returnRoute: routes.returnRt)
                        .padding(.bottom, 8)

                    // Toggles de "¿Visitaste alguna escala?" para trips legacy
                    // sin segmentos. Solo aparece cuando hay aeropuertos
                    // intermedios en alguna dirección. Misma UX que en
                    // AddSegmentSheet (IDA / VUELTA con set binario por país).
                    // UN solo toggle por país (binario). `legacyOutboundLayovers`
                    // viene ya deduplicada de `deriveLegacyFlightCountries()`.
                    if !legacyOutboundLayovers.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(isForFuture ? "¿HARÁS PARADA EN...?" : "¿VISITASTE ALGUNA ESCALA?")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary).tracking(0.8)
                            legacyLayoverSection(title: nil, choices: legacyOutboundLayovers)
                        }
                        .padding(16)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 24).padding(.bottom, 12)
                    }
                }

                // MARK: Tramos
                VStack(alignment: .leading, spacing: 10) {
                    Text("TRAMOS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary).tracking(1.0)
                        .padding(.horizontal, 24)

                    if !tripSegments.isEmpty {
                        VStack(spacing: 8) {
                            // Orden cronológico (ida → vuelta) independientemente del orden de inserción.
                            ForEach(tripSegments.sorted { $0.dateFrom < $1.dateFrom }) { seg in
                                let isFlight = seg.transport == "✈️"
                                let isExpanded = expandedSegmentIDs.contains(seg.id)
                                VStack(spacing: 10) {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle().fill(Color(.systemGray5)).frame(width: 40, height: 40)
                                            Text(seg.transport).font(.system(size: 18))
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(segmentCountryNames(seg))
                                                .font(.palatino(.body)).lineLimit(1)
                                            Text(Self.segFmt.string(from: seg.dateFrom))
                                                .font(.custom("Satoshi-Regular", size: 12)).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        // Sólo segmentos ✈️ tienen detalles de vuelo (asiento/clase) por tramo.
                                        if isFlight {
                                            Button {
                                                if isExpanded { expandedSegmentIDs.remove(seg.id) }
                                                else { expandedSegmentIDs.insert(seg.id) }
                                            } label: {
                                                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                                    .font(.system(size: 22)).foregroundStyle(accent.opacity(0.8))
                                            }.buttonStyle(.plain)
                                        }
                                        Button {
                                            // Editar: NO eliminar upfront — si el usuario cancela en
                                            // AddSegmentSheet el segmento se preserva. AddSegmentSheet
                                            // reusa el mismo `id` al guardar, y abajo lo reemplazamos por id.
                                            editingSegment = seg
                                            showAddSegment = true
                                        } label: {
                                            Image(systemName: "pencil.circle.fill")
                                                .font(.system(size: 22)).foregroundStyle(accent.opacity(0.8))
                                        }.buttonStyle(.plain)
                                        Button { tripSegments.removeAll { $0.id == seg.id } } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 22)).foregroundStyle(Color(.systemGray3))
                                        }.buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 10)
                                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
                                    .padding(.horizontal, 24)

                                    // Asiento / clase / reserva por leg (ida + vuelta separados).
                                    // Inline edit por segmento ✈️ — evita tener que abrir AddSegmentSheet
                                    // sólo para cambiar asientos. El binding escribe en seg.flightInfo.
                                    if isFlight && isExpanded {
                                        FlightInfoSection(
                                            info: segmentFlightInfoBinding(for: seg.id),
                                            outboundRoute: (seg.airports ?? []).map { $0.iata },
                                            returnRoute: (seg.returnAirports ?? []).map { $0.iata }
                                        )
                                    }
                                }
                            }
                        }
                    }

                    Button { showAddSegment = true } label: {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle().fill(accent.opacity(0.1)).frame(width: 32, height: 32)
                                Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(accent)
                            }
                            Text("Añadir transporte").font(.palatino(.body)).foregroundStyle(accent)
                        }
                        .padding(.horizontal, 24).padding(.vertical, 4)
                    }.buttonStyle(.plain)
                }
                .padding(.bottom, 16)

                // Rango de fechas calculado desde segmentos
                if !tripSegments.isEmpty {
                    HStack(spacing: 12) {
                        VStack(spacing: 4) {
                            Text("DESDE").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).tracking(0.8)
                            Text(Self.fmt.string(from: calculatedDateFrom))
                                .font(.custom("Satoshi-Bold", size: 15))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                        if let to = calculatedDateTo {
                            VStack(spacing: 4) {
                                Text("HASTA").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).tracking(0.8)
                                Text(Self.fmt.string(from: to))
                                    .font(.custom("Satoshi-Bold", size: 15))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 24).padding(.bottom, 16)
                }

                Button { prepareEditSaveConfirmation() } label: {
                    Text("Guardar cambios")
                        .font(.custom("Satoshi-Bold", size: 16))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(accent, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                        .shadow(color: accent.opacity(0.3), radius: 12, y: 4)
                }
                .padding(.horizontal, 24).padding(.bottom, 36)
            }
            }
            .navigationTitle("Editar viaje")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(showSaveConfirmation)
        .sheet(isPresented: $showAddSegment, onDismiss: { editingSegment = nil }) {
            AddSegmentSheet(features: features, isForFuture: isForFuture, initialSegment: editingSegment, existingSegments: tripSegments) { seg in
                // Reemplaza por id si ya existe (edición), o añade (creación).
                if let idx = tripSegments.firstIndex(where: { $0.id == seg.id }) {
                    tripSegments[idx] = seg
                } else {
                    tripSegments.append(seg)
                }
                // Reordenar por fecha tras cualquier cambio — si el usuario
                // cambia la fecha de un segment desde edición, su posición
                // visual debe reflejar la nueva fecha, no el orden anterior.
                tripSegments.sort { $0.dateFrom < $1.dateFrom }
            }
        }
        .sheet(isPresented: $showRoutePicker) {
            RouteWizardSheet(airports: $localAirports, returnAirports: $localReturnAirports,
                             airlines: $localAirlines, hasLayover: $localHasLayover) {
                // Tras añadir/editar la ruta o cualquier escala, recomputa los
                // toggles IDA/VUELTA (`legacyOutboundLayovers` / `legacyReturnLayovers`)
                // para que aparezca el bloque "¿Visitaste alguna escala?".
                deriveLegacyFlightCountries()
            }
        }
        // Recompute legacy layover toggles cuando aparece la sheet — cubre el
        // caso de un trip ya guardado con escalas + ISOs visitadas que el user
        // re-abre solo para revisar/cambiar.
        .onAppear { deriveLegacyFlightCountries() }
        .appColorScheme()

        if showSaveConfirmation {
            editVisitConfirmCard(onSave: { showSaveConfirmation = false; performEditSave() },
                                 onCancel: { showSaveConfirmation = false })
        }
        } // ZStack
    }

    @ViewBuilder
    private func editVisitConfirmCard(onSave: @escaping () -> Void, onCancel: @escaping () -> Void) -> some View {
        confirmCardContent(
            confirmVisits: $confirmVisits, confirmAirports: $confirmAirports, confirmAirlines: $confirmAirlines,
            accent: accent, onSave: onSave, onCancel: onCancel
        )
    }
}

// MARK: - Cuadrante de mapa
struct MapQuadrant: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var candidateIsoCodes: [String]
    var position: Int

    init(id: UUID = UUID(), title: String, candidateIsoCodes: [String], position: Int = 0) {
        self.id = id; self.title = title; self.candidateIsoCodes = candidateIsoCodes; self.position = position
    }

    enum CodingKeys: String, CodingKey { case id, title, candidateIsoCodes, position }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        candidateIsoCodes = try c.decode([String].self, forKey: .candidateIsoCodes)
        position = (try? c.decodeIfPresent(Int.self, forKey: .position)) ?? -1
    }
}

// MARK: - Exportar mapa como imagen
struct MapExportSheet: View {
    let visitedCountries: [Country]
    let features: [CountryFeature]
    let countingModeRaw: String
    let visitedColor: Color
    let trips: [Trip]

    private var countingMode: CountingMode { CountingMode(rawValue: countingModeRaw) ?? .all }

    @AppStorage("multiContinentRaw") private var multiContinentRaw: String = "{}"
    private var multiContinentAssignments: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(multiContinentRaw.utf8))) ?? [:]
    }

    private var zoneCounter: String {
        let mode = countingMode
        if selectedZone.isWorld {
            let visited = visitedCountries.filter { mode.counts($0.isoCode) }.count
            return "\(visited)/\(mode.denominator)"
        }
        let codes = AchievementKind.adjustSet(selectedZone.isoCodes, forZone: selectedZone.zoneName, assignments: multiContinentAssignments)
        let visited = visitedCountries.filter { codes.contains($0.isoCode) && mode.counts($0.isoCode) }.count
        let total = codes.filter { mode.counts($0) }.count
        return "\(visited)/\(total)"
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @AppStorage("isRaskmapPro") private var isRaskmapPro: Bool = false
    @State private var showSubscriptionFromMap: Bool = false
    @State private var renderedImage: UIImage? = nil
    @State private var isRendering: Bool = true
    @State private var isSaving: Bool = false
    @State private var savedToast: Bool = false
    @State private var showFormatDialog: Bool = false
    @State private var selectedZone: ExportZone = .europa
    @State private var showAddQuadrant: Bool = false
    @State private var selectedQuadrant: MapQuadrant? = nil
    @State private var quadrantToEdit: MapQuadrant? = nil
    @State private var isEditingQuadrants: Bool = false
    @State private var quadrantToDelete: MapQuadrant? = nil
    @State private var showResetConfirm: Bool = false
    @AppStorage("mapQuadrantsData") private var mapQuadrantsData: String = "{}"
    @AppStorage("didInsertDefaultQuadrants") private var didInsertDefaultQuadrants: Bool = false

    private var allQuadrants: [String: [MapQuadrant]] {
        guard let data = mapQuadrantsData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: [MapQuadrant]].self, from: data)
        else { return [:] }
        return decoded
    }
    private var currentQuadrantSlots: [MapQuadrant?] {
        var list = allQuadrants[selectedZone.rawValue] ?? []
        if list.contains(where: { $0.position < 0 || $0.position >= 4 }) {
            for i in list.indices { list[i].position = i }
        }
        var slots: [MapQuadrant?] = [nil, nil, nil, nil]
        for q in list where q.position >= 0 && q.position < 4 {
            if slots[q.position] == nil { slots[q.position] = q }
        }
        return slots
    }
    private func saveQuadrant(_ q: MapQuadrant) {
        var all = allQuadrants
        let slots = currentQuadrantSlots
        let nextPos = slots.firstIndex(where: { $0 == nil }) ?? 0
        var newQ = q; newQ.position = nextPos
        var list = all[selectedZone.rawValue] ?? []
        list.append(newQ)
        all[selectedZone.rawValue] = list
        if let data = try? JSONEncoder().encode(all), let str = String(data: data, encoding: .utf8) {
            mapQuadrantsData = str
        }
    }
    private func saveAllQuadrants(_ list: [MapQuadrant]) {
        var all = allQuadrants
        all[selectedZone.rawValue] = list
        if let data = try? JSONEncoder().encode(all), let str = String(data: data, encoding: .utf8) {
            mapQuadrantsData = str
        }
    }
    private func updateQuadrant(_ q: MapQuadrant) {
        var all = allQuadrants
        var list = all[selectedZone.rawValue] ?? []
        if let idx = list.firstIndex(where: { $0.id == q.id }) {
            list[idx] = q
        }
        all[selectedZone.rawValue] = list
        if let data = try? JSONEncoder().encode(all), let str = String(data: data, encoding: .utf8) {
            mapQuadrantsData = str
        }
    }
    private func deleteQuadrant(_ q: MapQuadrant) {
        var all = allQuadrants
        var list = all[selectedZone.rawValue] ?? []
        list.removeAll { $0.id == q.id }
        all[selectedZone.rawValue] = list
        if let data = try? JSONEncoder().encode(all), let str = String(data: data, encoding: .utf8) {
            mapQuadrantsData = str
        }
    }
    private func insertDefaultsIfNeeded(zone: ExportZone, defaults: [(pos: Int, title: String, codes: [String])]) {
        var all = allQuadrants
        var list = all[zone.rawValue] ?? []
        // Normalize legacy positions (position == -1) before checking
        if list.contains(where: { $0.position < 0 || $0.position >= 4 }) {
            for i in list.indices { list[i].position = i }
        }
        let occupied = Set(list.filter { $0.position >= 0 && $0.position < 4 }.map { $0.position })
        var changed = false
        for d in defaults where !occupied.contains(d.pos) {
            list.append(MapQuadrant(title: d.title, candidateIsoCodes: d.codes, position: d.pos))
            changed = true
        }
        if changed {
            all[zone.rawValue] = list
            if let data = try? JSONEncoder().encode(all), let str = String(data: data, encoding: .utf8) {
                mapQuadrantsData = str
            }
        }
    }
    private func insertZoneDefaultsIfNeeded() {
        guard !didInsertDefaultQuadrants else { return }
        insertDefaultsIfNeeded(zone: .europa, defaults: [
            (0, "Unión Europea 🇪🇺", ["AUT","BEL","BGR","HRV","CYP","CZE","DNK","EST","FIN","FRA",
                                       "DEU","GRC","HUN","IRL","ITA","LVA","LTU","LUX","MLT","NLD",
                                       "POL","PRT","ROU","SVK","SVN","ESP","SWE"]),
            (1, "Microestados 🌐",   ["AND","LIE","MCO","SMR","VAT","MLT"]),
            (2, "Países nórdicos ❄️", ["NOR","SWE","DNK","FIN","ISL","FRO","ALD"])
        ])
        insertDefaultsIfNeeded(zone: .asia, defaults: [
            (0, "Asia Central 🏔️",  ["KAZ","KGZ","TJK","TKM","UZB","AFG"]),
            (1, "Asia Este 🏯",      ["CHN","JPN","PRK","KOR","MNG","TWN","HKG","MAC"]),
            (2, "Asia Sur 🌺",       ["IND","PAK","BGD","LKA","NPL","BTN","MDV","IOT"])
        ])
        insertDefaultsIfNeeded(zone: .africa, defaults: [
            (0, "Insulares 🏝️",  ["CPV","COM","MDG","MUS","STP","SYC","SHN"]),
            (1, "Safari 🦁",     ["KEN","TZA","ZAF","BWA","NAM","ZWE","UGA","RWA",
                                   "ETH","MOZ","ZMB","MWI","TCD","GAB","CMR"]),
            (2, "Sahel ☀️",      ["MRT","SEN","GMB","MLI","BFA","NER","NGA","TCD",
                                   "SDN","SSD","ERI","SAH"])
        ])
        insertDefaultsIfNeeded(zone: .america, defaults: [
            (0, "Norteamérica 🦅",    ["MEX","CAN","USA","GRL","SPM"]),
            (1, "Centroamérica 🌴",   ["BLZ","GTM","SLV","HND","NIC","CRI","PAN",
                                        "ATG","BHS","BRB","CUB","DMA","DOM","GRD",
                                        "HTI","JAM","KNA","LCA","VCT","TTO",
                                        "ABW","AIA","BMU","VGB","CYM","CUW",
                                        "MSR","PRI","BLM","MAF","SXM","TCA","VIR"]),
            (2, "Sudamérica 🌎",      ["ARG","BOL","BRA","CHL","COL","ECU","GUY",
                                        "PRY","PER","SUR","URY","VEN","FLK"])
        ])
        insertDefaultsIfNeeded(zone: .medioOriente, defaults: [
            (0, "Petroleros 🛢️",    ["SAU","ARE","IRQ","IRN","KWT","QAT","BHR","OMN"]),
            (1, "Históricos 🏛️",   ["IRQ","ISR","JOR","LBN","SYR","IRN","TUR",
                                      "PSE","YEM","OMN","SAU"]),
            (2, "F1 GP 🏎️",        ["BHR","SAU","ARE","QAT"])
        ])
        insertDefaultsIfNeeded(zone: .oceania, defaults: [
            (0, "Una isla 🏝️",        ["NRU","NIU","GUM","NFK"]),
            (1, "Commonwealth 👑",     ["AUS","NZL","PNG","FJI","SLB","VUT","TON",
                                         "WSM","KIR","NRU","TUV","COK","NIU","NFK","PCN"]),
            (2, "Comparten isla 🌊",   ["PNG","IDN"])
        ])
        didInsertDefaultQuadrants = true
    }
    private func resetToDefaults() {
        mapQuadrantsData = "{}"
        didInsertDefaultQuadrants = false
        insertZoneDefaultsIfNeeded()
    }
    @discardableResult
    private func swapQuadrant(idStr: String?, toIndex: Int) -> Bool {
        var list = allQuadrants[selectedZone.rawValue] ?? []
        if list.contains(where: { $0.position < 0 }) {
            for i in list.indices { list[i].position = i }
        }
        guard let idStr, let fromIdx = list.firstIndex(where: { $0.id.uuidString == idStr }) else { return false }
        let fromPos = list[fromIdx].position
        guard fromPos != toIndex else { return false }
        if let toIdx = list.firstIndex(where: { $0.position == toIndex }) {
            list[toIdx].position = fromPos
        }
        list[fromIdx].position = toIndex
        saveAllQuadrants(list)
        return true
    }

    enum ExportZone: String, CaseIterable, Identifiable {
        case europa = "Europa"; case asia = "Asia"
        case medioOriente = "M. Oriente"; case africa = "África"
        case america = "América"; case oceania = "Oceanía"
        case mundo = "Mundo"
        var id: String { rawValue }
        var isWorld: Bool { self == .mundo }

        var zoneName: String {
            switch self {
            case .europa: return "europa"
            case .asia: return "asia"
            case .medioOriente: return "medioOriente"
            case .africa: return "africa"
            case .america: return "america"
            case .oceania: return "oceania"
            case .mundo: return "mundo"
            }
        }

        var region: MKCoordinateRegion {
            switch self {
            case .europa:      return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 53,  longitude: 12),  span: MKCoordinateSpan(latitudeDelta: 52,  longitudeDelta: 90))
            case .asia:        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 32,  longitude: 95),  span: MKCoordinateSpan(latitudeDelta: 80,  longitudeDelta: 130))
            case .medioOriente:return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 27,  longitude: 43),  span: MKCoordinateSpan(latitudeDelta: 42,  longitudeDelta: 56))
            case .africa:      return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 1,   longitude: 17),  span: MKCoordinateSpan(latitudeDelta: 82,  longitudeDelta: 82))
            case .america:     return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 8,   longitude: -95), span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 148))
            case .oceania:     return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: -22, longitude: 148), span: MKCoordinateSpan(latitudeDelta: 72,  longitudeDelta: 100))
            case .mundo:       return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 20,  longitude: 10),  span: MKCoordinateSpan(latitudeDelta: 160, longitudeDelta: 360))
            }
        }

        var isoCodes: Set<String> {
            switch self {
            case .europa:
                return ["ALB","AND","AUT","BLR","BEL","BIH","BGR","HRV","CYP","CZE",
                        "DNK","EST","FIN","FRA","DEU","GRC","HUN","ISL","IRL","ITA",
                        "LVA","LIE","LTU","LUX","MLT","MDA","MCO","MNE","NLD","MKD",
                        "NOR","POL","PRT","ROU","RUS","SMR","SRB","SVK","SVN","ESP",
                        "SWE","CHE","UKR","GBR","VAT","KOS","ALD","FRO","GIB","GGY","IMN","JEY"]
            case .asia:
                return ["AFG","ARM","AZE","BGD","BTN","BRN","KHM","CHN","GEO","IND",
                        "IDN","JPN","KAZ","PRK","KOR","KGZ","LAO","MYS","MDV","MNG",
                        "MMR","NPL","PAK","PHL","SGP","LKA","TWN","TJK","THA","TLS",
                        "TKM","UZB","VNM","HKG","MAC","IOT"]
            case .medioOriente:
                return ["BHR","IRN","IRQ","ISR","JOR","KWT","LBN","OMN","PSE","PSX",
                        "QAT","SAU","SYR","TUR","ARE","YEM"]
            case .africa:
                return ["DZA","AGO","BEN","BWA","BFA","BDI","CPV","CMR","CAF","TCD",
                        "COM","COD","COG","CIV","DJI","EGY","GNQ","ERI","ETH","GAB",
                        "GMB","GHA","GIN","GNB","KEN","LSO","LBR","LBY","MDG","MWI",
                        "MLI","MRT","MUS","MAR","MOZ","NAM","NER","NGA","RWA","STP",
                        "SEN","SYC","SLE","SOM","ZAF","SSD","SDS","SDN","SWZ","TZA",
                        "TGO","TUN","UGA","ZMB","ZWE","SAH","SHN"]
            case .america:
                return ["ATG","ARG","BHS","BRB","BLZ","BOL","BRA","CAN","CHL","COL",
                        "CRI","CUB","DMA","DOM","ECU","SLV","GRD","GTM","GUY","HTI",
                        "HND","JAM","MEX","NIC","PAN","PRY","PER","KNA","LCA","VCT",
                        "SUR","TTO","USA","URY","VEN","ABW","AIA","BMU","VGB","CYM",
                        "CUW","FLK","GRL","MSR","PRI","BLM","MAF","SPM","SXM","TCA","VIR"]
            case .oceania:
                return ["AUS","FJI","KIR","MHL","FSM","NRU","NZL","PLW","PNG","WSM",
                        "SLB","TON","TUV","VUT","ASM","COK","PYF","GUM","NCL","NIU",
                        "NFK","MNP","PCN","WLF"]
            case .mundo:
                return []   // handled specially: all visited features
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
              VStack(spacing: 12) {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach([ExportZone.europa, .asia, .medioOriente]) { zone in
                            Button {
                                selectedZone = zone; renderedImage = nil; isRendering = true
                            } label: {
                                Text(zone.rawValue)
                                    .font(.palatino(.footnote, weight: selectedZone == zone ? .bold : .regular))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(selectedZone == zone ? Color.blue : Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(selectedZone == zone ? .white : .primary)
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        ForEach([ExportZone.africa, .america, .oceania]) { zone in
                            Button {
                                selectedZone = zone; renderedImage = nil; isRendering = true
                            } label: {
                                Text(zone.rawValue)
                                    .font(.palatino(.footnote, weight: selectedZone == zone ? .bold : .regular))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(selectedZone == zone ? Color.blue : Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(selectedZone == zone ? .white : .primary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)

                ZStack {
                    if let img = renderedImage {
                        Image(uiImage: img).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12)).shadow(radius: 6)
                    } else {
                        RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6))
                            .aspectRatio(selectedZone.isWorld ? CGFloat(780)/640 : 1, contentMode: .fit)
                            .overlay { VStack(spacing: 12) { ProgressView(); Text("Generando mapa…").font(.palatino(.caption)).foregroundStyle(.secondary) } }
                    }
                }
                .padding(.horizontal, 16)
                .onAppear { renderMap() }
                .onChange(of: selectedZone) { _, _ in renderMap() }

                Spacer()

                // ── Cuadrantes (grid fijo 2×2) — oculto para mundo ──
                if !selectedZone.isWorld {
                    quadrantGrid()
                        .padding(.horizontal, 16)
                }

                Spacer()

                Button {
                    guard renderedImage != nil else { return }
                    if selectedZone.isWorld {
                        saveImage(size: CGSize(width: 1560, height: 1280))
                    } else {
                        showFormatDialog = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isSaving { ProgressView().tint(.white) } else { Image(systemName: "square.and.arrow.down") }
                        Text(savedToast ? "¡Guardada!" : "Guardar en galería")
                    }
                    .font(.palatino(.body, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(savedToast ? Color.green : Color.blue, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
                .padding(.horizontal, 24).padding(.bottom, 24).disabled(renderedImage == nil || isSaving)
                .animation(.easeInOut(duration: 0.2), value: savedToast)
                .confirmationDialog("Formato de imagen", isPresented: $showFormatDialog) {
                    Button("1:1 (cuadrado)") { saveImage(size: CGSize(width: 900, height: 900)) }
                    Button("9:16 (vertical)") { saveImage(size: CGSize(width: 900, height: 1600)) }
                    Button("Cancelar", role: .cancel) {}
                }
              }
              .blur(radius: isRaskmapPro ? 0 : 12)
              .allowsHitTesting(isRaskmapPro)
              if !isRaskmapPro {
                  VStack(spacing: 16) {
                      Image(systemName: "lock.fill")
                          .font(.system(size: 44))
                          .foregroundStyle(.purple)
                      Text("Función Pro")
                          .font(.palatino(.title3, weight: .bold))
                          .foregroundStyle(.purple)
                      Button { showSubscriptionFromMap = true } label: {
                          Text("Desbloquear Pro")
                              .font(.palatino(.body, weight: .bold))
                              .foregroundStyle(.white)
                              .padding(.horizontal, 28)
                              .padding(.vertical, 12)
                              .background(Color.purple, in: Capsule())
                      }
                      .buttonStyle(.plain)
                  }
              }
            }
            .padding(.top, 8)
            .navigationTitle("Mi mapa").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button { showResetConfirm = true } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        Button { isEditingQuadrants.toggle() } label: {
                            Image(systemName: isEditingQuadrants ? "checkmark" : "pencil")
                        }
                    }
                }
            }
            .sheet(isPresented: $showSubscriptionFromMap) { SubscriptionSheet() }
            .sheet(isPresented: $showAddQuadrant) {
                AddQuadrantSheet(features: features, zone: selectedZone, countingModeRaw: countingModeRaw) { q in saveQuadrant(q) }
            }
            .sheet(item: $quadrantToEdit) { q in
                AddQuadrantSheet(features: features, zone: selectedZone, countingModeRaw: countingModeRaw, initialQuadrant: q) { updated in
                    updateQuadrant(updated)
                }
            }
            .sheet(item: $selectedQuadrant) { q in
                let visitedSet = Set(visitedCountries.map { $0.isoCode })
                QuadrantDetailSheet(quadrant: q, features: features, visitedIsoCodes: visitedSet, countingModeRaw: countingModeRaw, zoneName: selectedZone.zoneName, multiContinentAssignments: multiContinentAssignments)
            }
            .alert("¿Eliminar lista?", isPresented: Binding(
                get: { quadrantToDelete != nil },
                set: { if !$0 { quadrantToDelete = nil } }
            )) {
                Button("Eliminar", role: .destructive) {
                    if let q = quadrantToDelete { deleteQuadrant(q) }
                    quadrantToDelete = nil
                    isEditingQuadrants = false
                }
                Button("Cancelar", role: .cancel) { quadrantToDelete = nil }
            } message: {
                if let q = quadrantToDelete { Text("Se eliminará «\(q.title)».") }
            }
            .alert("Restablecer cuadrantes", isPresented: $showResetConfirm) {
                Button("Restablecer", role: .destructive) { resetToDefaults() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se borrarán todos los cuadrantes actuales y se restaurarán los predeterminados.")
            }
        }
        .appColorScheme()
        .onAppear { insertZoneDefaultsIfNeeded() }
    }

    @ViewBuilder
    private func quadrantSlot(index: Int) -> some View {
        let slots = currentQuadrantSlots
        let visitedSet = Set(visitedCountries.map { $0.isoCode })
        let currentMode = CountingMode(rawValue: countingModeRaw) ?? .all
        if let q = slots[index] {
            let zoneFiltered = AchievementKind.filterCandidatesForZone(
                q.candidateIsoCodes,
                zoneName: selectedZone.zoneName,
                assignments: multiContinentAssignments,
                quadrantTitle: q.title
            )
            let zoneFilteredSet = Set(zoneFiltered)
            let activeCodes = q.candidateIsoCodes.filter { zoneFilteredSet.contains($0) && currentMode.counts($0) }
            let cnt = activeCodes.filter { visitedSet.contains($0) }.count
            ZStack(alignment: .topTrailing) {
                Button { if !isEditingQuadrants { selectedQuadrant = q } } label: {
                    VStack(spacing: 4) {
                        FlagAwareText(text: q.title,
                                      font: .palatino(.caption, weight: .bold),
                                      size: 14)
                            .lineLimit(1)
                        Text("\(cnt)/\(activeCodes.count)")
                            .font(.palatino(.title3, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(.primary)
                    .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                if isEditingQuadrants {
                    HStack(spacing: 4) {
                        Button { quadrantToEdit = q } label: {
                            Image(systemName: "pencil.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.title3)
                                .background(Circle().fill(Color(.systemBackground)))
                        }
                        Button { quadrantToDelete = q } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                                .font(.title3)
                                .background(Circle().fill(Color(.systemBackground)))
                        }
                    }
                    .offset(x: 6, y: -6)
                }
            }
            .draggable(q.id.uuidString)
            .dropDestination(for: String.self) { items, _ in swapQuadrant(idStr: items.first, toIndex: index) }
        } else {
            Button { showAddQuadrant = true } label: {
                Image(systemName: "plus")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .dropDestination(for: String.self) { items, _ in swapQuadrant(idStr: items.first, toIndex: index) }
        }
    }

    @ViewBuilder
    private func quadrantGrid() -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                quadrantSlot(index: 0)
                quadrantSlot(index: 1)
            }
            HStack(spacing: 8) {
                quadrantSlot(index: 2)
                quadrantSlot(index: 3)
            }
        }
    }

    private func saveImage(size: CGSize) {
        isSaving = true
        let isWorld = selectedZone.isWorld
        let snapSize = isWorld ? CGSize(width: 624, height: 512) : size
        let options = MKMapSnapshotter.Options()
        if isWorld {
            options.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 15, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)
            )
        } else {
            options.region = selectedZone.region
        }
        options.size = snapSize
        options.scale = isWorld ? 1 : displayScale
        options.mapType = .mutedStandard
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false
        let style: UIUserInterfaceStyle = ColorThemeManager.shared.isDarkMode ? .dark : .light
        options.traitCollection = UITraitCollection(userInterfaceStyle: style)

        let visitedIsoCodes = Set(visitedCountries.map { $0.isoCode })
        let visitedFeatures: [CountryFeature]
        if isWorld {
            visitedFeatures = features.filter { visitedIsoCodes.contains($0.isoCode) }
        } else {
            let assignments = multiContinentAssignments
            let zoneIsoCodes = Set(AchievementKind.adjustSet(selectedZone.isoCodes, forZone: selectedZone.zoneName, assignments: assignments))
            visitedFeatures = features.filter { visitedIsoCodes.contains($0.isoCode) && zoneIsoCodes.contains($0.isoCode) }
        }
        let fillUIColor = UIColor(visitedColor)
        let counterStr = zoneCounter

        MKMapSnapshotter(options: options).start { snapshot, _ in
            guard let snapshot else { DispatchQueue.main.async { isSaving = false }; return }
            let ws: CGFloat = isWorld ? size.width / snapSize.width : 1.0
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { _ in
                snapshot.image.draw(in: CGRect(origin: .zero, size: size))
                for feature in visitedFeatures {
                    for polygon in feature.polygons {
                        guard polygon.pointCount >= 3 else { continue }
                        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: polygon.pointCount)
                        polygon.getCoordinates(&coords, range: NSRange(location: 0, length: polygon.pointCount))
                        let pts = coords.map { CGPoint(x: snapshot.point(for: $0).x * ws, y: snapshot.point(for: $0).y * ws) }
                        let m: CGFloat = 50
                        guard pts.contains(where: { $0.x > -m && $0.x < size.width + m && $0.y > -m && $0.y < size.height + m }) else { continue }
                        let path = UIBezierPath()
                        path.move(to: pts[0]); pts.dropFirst().forEach { path.addLine(to: $0) }; path.close()
                        path.usesEvenOddFillRule = true
                        polygon.interiorPolygons?.forEach { hole in
                            guard hole.pointCount >= 3 else { return }
                            var hc = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: hole.pointCount)
                            hole.getCoordinates(&hc, range: NSRange(location: 0, length: hole.pointCount))
                            let hp = UIBezierPath()
                            let hpts = hc.map { CGPoint(x: snapshot.point(for: $0).x * ws, y: snapshot.point(for: $0).y * ws) }
                            hp.move(to: hpts[0]); hpts.dropFirst().forEach { hp.addLine(to: $0) }; hp.close()
                            path.append(hp)
                        }
                        fillUIColor.setFill(); path.fill()
                    }
                }
                let brandText = "Raskmap" as NSString
                let brandAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 13), .foregroundColor: UIColor.white.withAlphaComponent(0.85)]
                let brandSize = brandText.size(withAttributes: brandAttrs)
                let text = counterStr as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 20), .foregroundColor: UIColor.white]
                let ts = text.size(withAttributes: attrs)
                let pad: CGFloat = 10
                let bgW = max(ts.width, brandSize.width) + pad * 2
                let bgH = brandSize.height + 2 + ts.height + pad * 2
                let bgRect = CGRect(x: (size.width - bgW) / 2, y: size.height - bgH - 14, width: bgW, height: bgH)
                UIColor.black.withAlphaComponent(0.55).setFill()
                UIBezierPath(roundedRect: bgRect, cornerRadius: 8).fill()
                brandText.draw(at: CGPoint(x: (size.width - brandSize.width) / 2, y: bgRect.minY + pad), withAttributes: brandAttrs)
                text.draw(at: CGPoint(x: (size.width - ts.width) / 2, y: bgRect.minY + pad + brandSize.height + 2), withAttributes: attrs)
            }
            DispatchQueue.main.async {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                isSaving = false; savedToast = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { savedToast = false }
            }
        }
    }

    private func renderMap() {
        isRendering = true
        // Para mundo: snapshot pequeño (512×512, scale=1) fuerza zoom-1 = 4 tiles = mundo completo.
        // Luego escalamos manualmente al displaySize deseado.
        let isWorld = selectedZone.isWorld
        // snapSize coincide con el ratio Mercator natural de la región mundo (-75°..+85° lat, 360° lon)
        // ratio = 2π / (y(85°)-y(-75°)) = 6.283/5.159 ≈ 1.218  →  624×512
        let snapSize    = isWorld ? CGSize(width: 624, height: 512) : CGSize(width: 800, height: 800)
        let displaySize = isWorld ? CGSize(width: 780, height: 640) : CGSize(width: 800, height: 800)

        let options = MKMapSnapshotter.Options()
        if isWorld {
            options.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 15, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)
            )
        } else {
            options.region = selectedZone.region
        }
        options.size  = snapSize
        options.scale = isWorld ? 1 : displayScale
        options.mapType = .mutedStandard
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false
        let style: UIUserInterfaceStyle = ColorThemeManager.shared.isDarkMode ? .dark : .light
        options.traitCollection = UITraitCollection(userInterfaceStyle: style)

        let visitedIsoCodes = Set(visitedCountries.map { $0.isoCode })
        let visitedFeatures: [CountryFeature]
        if isWorld {
            visitedFeatures = features.filter { visitedIsoCodes.contains($0.isoCode) }
        } else {
            let assignments = multiContinentAssignments
            let zoneIsoCodes = Set(AchievementKind.adjustSet(selectedZone.isoCodes, forZone: selectedZone.zoneName, assignments: assignments))
            visitedFeatures = features.filter { visitedIsoCodes.contains($0.isoCode) && zoneIsoCodes.contains($0.isoCode) }
        }
        let fillUIColor = UIColor(visitedColor)
        let counterStr = zoneCounter

        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { snapshot, _ in
            guard let snapshot else { return }
            // Factor de escala del espacio snapshot → espacio displaySize
            let ws: CGFloat = isWorld ? displaySize.width / snapSize.width : 1.0
            let renderer = UIGraphicsImageRenderer(size: displaySize)
            let image = renderer.image { _ in
                // 1. Mapa base escalado al displaySize
                snapshot.image.draw(in: CGRect(origin: .zero, size: displaySize))

                // 2. Polígonos escalados
                for feature in visitedFeatures {
                    for polygon in feature.polygons {
                        guard polygon.pointCount >= 3 else { continue }
                        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: polygon.pointCount)
                        polygon.getCoordinates(&coords, range: NSRange(location: 0, length: polygon.pointCount))
                        let pts = coords.map { CGPoint(x: snapshot.point(for: $0).x * ws, y: snapshot.point(for: $0).y * ws) }
                        let m: CGFloat = 50
                        guard pts.contains(where: { $0.x > -m && $0.x < displaySize.width + m && $0.y > -m && $0.y < displaySize.height + m }) else { continue }

                        let path = UIBezierPath()
                        path.move(to: pts[0])
                        pts.dropFirst().forEach { path.addLine(to: $0) }
                        path.close()
                        path.usesEvenOddFillRule = true

                        polygon.interiorPolygons?.forEach { hole in
                            guard hole.pointCount >= 3 else { return }
                            var hc = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: hole.pointCount)
                            hole.getCoordinates(&hc, range: NSRange(location: 0, length: hole.pointCount))
                            let hp = UIBezierPath()
                            let hpts = hc.map { CGPoint(x: snapshot.point(for: $0).x * ws, y: snapshot.point(for: $0).y * ws) }
                            hp.move(to: hpts[0]); hpts.dropFirst().forEach { hp.addLine(to: $0) }; hp.close()
                            path.append(hp)
                        }

                        fillUIColor.setFill()
                        path.fill()
                    }
                }

                // 3. Marca de agua
                let brandText = "Raskmap" as NSString
                let brandAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 13),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.85)
                ]
                let brandSize = brandText.size(withAttributes: brandAttrs)
                let text = counterStr as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 20),
                    .foregroundColor: UIColor.white
                ]
                let ts = text.size(withAttributes: attrs)
                let pad: CGFloat = 10
                let bgW = max(ts.width, brandSize.width) + pad * 2
                let bgH = brandSize.height + 2 + ts.height + pad * 2
                let bgRect = CGRect(x: (displaySize.width - bgW) / 2, y: displaySize.height - bgH - 14, width: bgW, height: bgH)
                UIColor.black.withAlphaComponent(0.55).setFill()
                UIBezierPath(roundedRect: bgRect, cornerRadius: 8).fill()
                brandText.draw(at: CGPoint(x: (displaySize.width - brandSize.width) / 2, y: bgRect.minY + pad), withAttributes: brandAttrs)
                text.draw(at: CGPoint(x: (displaySize.width - ts.width) / 2, y: bgRect.minY + pad + brandSize.height + 2), withAttributes: attrs)
            }
            DispatchQueue.main.async { renderedImage = image; isRendering = false }
        }
    }
}

// MARK: - Añadir / editar cuadrante
struct AddQuadrantSheet: View {
    let features: [CountryFeature]
    let zone: MapExportSheet.ExportZone
    let countingModeRaw: String
    var initialQuadrant: MapQuadrant? = nil
    let onSave: (MapQuadrant) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var selectedIsoCodes: Set<String> = []
    @State private var searchText: String = ""

    private var countingMode: CountingMode { CountingMode(rawValue: countingModeRaw) ?? .all }

    private func saveAndDismiss() {
        guard !title.isEmpty, !selectedIsoCodes.isEmpty else { return }
        if let existing = initialQuadrant {
            onSave(MapQuadrant(id: existing.id, title: title, candidateIsoCodes: Array(selectedIsoCodes), position: existing.position))
        } else {
            onSave(MapQuadrant(title: title, candidateIsoCodes: Array(selectedIsoCodes)))
        }
        dismiss()
    }

    /// ISOs de países pluricontinentales — siempre seleccionables en cualquier
    /// zona (Europa/Asia/MedioOriente/etc.) independientemente de la asignación
    /// en Ajustes, para que un país como Chipre pueda meterse en cuadrantes
    /// tanto europeos como asiáticos sin restricciones.
    private static let pluriIsoCodes: Set<String> = ["RUS", "TUR", "CYP", "AZE", "GEO", "KAZ", "EGY"]

    private var flaggedFeatures: [CountryFeature] {
        features.filter {
            // En modo `all` (todos los territorios) mostramos también los que no
            // tienen bandera para que sean elegibles. En el resto de modos
            // (un/unPlus) seguimos exigiendo bandera.
            (countingMode == .all || $0.flagEmoji != nil) &&
            (zone.isoCodes.contains($0.isoCode) || Self.pluriIsoCodes.contains($0.isoCode)) &&
            countingMode.counts($0.isoCode)
        }.sorted { $0.localizedName.localizedCompare($1.localizedName) == .orderedAscending }
    }
    private var filtered: [CountryFeature] {
        guard !searchText.isEmpty else { return flaggedFeatures }
        let q = searchText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return flaggedFeatures.filter {
            $0.localizedName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Título de la lista", text: $title)
                        .font(.palatino(.body))
                }
                Section("Candidatos (\(selectedIsoCodes.count))") {
                    ForEach(filtered, id: \.isoCode) { feature in
                        Button {
                            if selectedIsoCodes.contains(feature.isoCode) {
                                selectedIsoCodes.remove(feature.isoCode)
                            } else {
                                selectedIsoCodes.insert(feature.isoCode)
                            }
                        } label: {
                            HStack {
                                FlagLabel(emoji: feature.flagEmoji ?? "🌐", size: 17)
                                Text(feature.localizedName)
                                    .font(.palatino(.body))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedIsoCodes.contains(feature.isoCode) {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .onAppear {
                if let q = initialQuadrant {
                    title = q.title
                    selectedIsoCodes = Set(q.candidateIsoCodes)
                }
            }
            .searchable(text: $searchText, prompt: "Buscar territorio…")
            .navigationTitle(initialQuadrant == nil ? "Nueva lista" : "Editar lista")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }.font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Guardar") { saveAndDismiss() }
                        .disabled(title.isEmpty || selectedIsoCodes.isEmpty)
                        .font(.palatino(.body, weight: .bold))
                }
            }
        }
    }
}

// MARK: - Detalle de cuadrante
struct QuadrantDetailSheet: View {
    let quadrant: MapQuadrant
    let features: [CountryFeature]
    let visitedIsoCodes: Set<String>
    let countingModeRaw: String
    var zoneName: String? = nil
    var multiContinentAssignments: [String: String] = [:]

    @Environment(\.dismiss) private var dismiss

    private var countingMode: CountingMode { CountingMode(rawValue: countingModeRaw) ?? .all }

    /// Candidatos filtrados por modo de conteo Y por asignaciones pluricontinentales:
    /// si un país pluri (ej. Chipre) está asignado a otra zona en Ajustes, no aparece
    /// en cuadrantes de zonas distintas. Excepción: cuadrantes UE no se filtran.
    private var activeCandidates: [String] {
        let zoneFiltered: [String]
        if let zoneName {
            zoneFiltered = AchievementKind.filterCandidatesForZone(
                quadrant.candidateIsoCodes,
                zoneName: zoneName,
                assignments: multiContinentAssignments,
                quadrantTitle: quadrant.title
            )
        } else {
            zoneFiltered = quadrant.candidateIsoCodes
        }
        let allowed = Set(zoneFiltered)
        return quadrant.candidateIsoCodes.filter { allowed.contains($0) && countingMode.counts($0) }
    }

    private var visited: [CountryFeature] {
        activeCandidates
            .filter { visitedIsoCodes.contains($0) }
            .compactMap { iso in features.first(where: { $0.isoCode == iso }) }
            .sorted { $0.localizedName.localizedCompare($1.localizedName) == .orderedAscending }
    }
    private var notVisited: [CountryFeature] {
        activeCandidates
            .filter { !visitedIsoCodes.contains($0) }
            .compactMap { iso in features.first(where: { $0.isoCode == iso }) }
            .sorted { $0.localizedName.localizedCompare($1.localizedName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if !visited.isEmpty {
                    Section {
                        ForEach(visited, id: \.isoCode) { feature in
                            HStack(spacing: 12) {
                                FlagLabel(emoji: feature.flagEmoji ?? "", size: 22)
                                Text(feature.localizedName).font(.palatino(.body))
                            }
                        }
                    }
                }
                if !notVisited.isEmpty {
                    Section {
                        ForEach(notVisited, id: \.isoCode) { feature in
                            HStack(spacing: 12) {
                                FlagLabel(emoji: feature.flagEmoji ?? "", size: 22).opacity(0.4)
                                Text(feature.localizedName)
                                    .font(.palatino(.body))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            // Título: `navigationTitle("...")` solo acepta String → cualquier
            // bandera emoji embebida saldría como emoji nativo del sistema, NO
            // como Twemoji. Para que el twemoji se renderice también en el
            // header del sheet, usamos `.principal` con `FlagAwareText`.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    FlagAwareText(
                        text: "\(quadrant.title) · \(visited.count)/\(activeCandidates.count)",
                        font: .custom("Satoshi-Bold", size: 17),
                        size: 16
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
    }
}

// MARK: - Medallero sheet
@Model
class PersonalAwardModel {
    var id: UUID = UUID()
    var sortOrder: Int = 0
    var title: String = ""
    var gold: String = ""
    var silver: String = ""
    var bronze: String = ""
    var extrasRaw: String = "[]"
    var createdAt: Date = Date()

    init(sortOrder: Int = 0) { self.sortOrder = sortOrder }

    var extras: [String] {
        get { (try? JSONDecoder().decode([String].self, from: Data(extrasRaw.utf8))) ?? [] }
        set { extrasRaw = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]" }
    }
}

struct MedalleroSheet: View {
    @Binding var topTable: String
    let allFeatures: [CountryFeature]
    let visitedIsoCodes: Set<String>

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PersonalAwardModel.sortOrder) private var personalAwards: [PersonalAwardModel]
    @State private var editingSpot: ProfileSheet.TopSpot? = nil
    @State private var editingAward: PersonalAwardModel? = nil
    @State private var showAlphabet: Bool = false
    @State private var showSubscription: Bool = false
    @AppStorage("countingMode") private var countingModeRaw: String = CountingMode.all.rawValue
    @AppStorage("isRaskmapPro") private var isRaskmapPro: Bool = false
    @AppStorage("personalList1Title") private var list1Title: String = ""
    @AppStorage("personalList1Content") private var list1Content: String = ""
    @State private var showList1: Bool = false
    @State private var showSubjectiveCategories: Bool = false

    private func tableDict() -> [String: String] {
        guard let data = topTable.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }
    private func tableFlag(region: ProfileSheet.TopRegion, medal: ProfileSheet.MedalSlot) -> String? {
        tableDict()[region.rawValue + "_" + medal.rawValue]
    }
    private func setTableFlag(_ emoji: String?, region: ProfileSheet.TopRegion, medal: ProfileSheet.MedalSlot) {
        var dict = tableDict()
        let key = region.rawValue + "_" + medal.rawValue
        if let emoji { dict[key] = emoji } else { dict.removeValue(forKey: key) }
        let data = (try? JSONEncoder().encode(dict)) ?? Data()
        topTable = String(data: data, encoding: .utf8) ?? "{}"
    }
    private func allUsedTableFlags() -> Set<String> { Set(tableDict().values) }
    private func visitedFeaturesForRegion(_ region: ProfileSheet.TopRegion) -> [CountryFeature] {
        allFeatures
            .filter { visitedIsoCodes.contains($0.isoCode) && region.isoCodes.contains($0.isoCode) }
            .sorted { $0.localizedName.localizedCompare($1.localizedName) == .orderedAscending }
    }

    @ViewBuilder
    private func awardSlot(_ award: PersonalAwardModel?) -> some View {
        if let award {
            Button { editingAward = award } label: {
                VStack(alignment: .leading, spacing: 3) {
                    FlagAwareText(text: award.title.isEmpty ? "Premio" : award.title,
                                  font: .palatino(.caption, weight: .bold),
                                  size: 14)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text("🥇").font(.system(size: 10))
                        FlagAwareText(text: award.gold.isEmpty ? "—" : award.gold,
                                      font: .palatino(.caption2),
                                      size: 11,
                                      foreground: .secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 4) {
                        Text("🥈").font(.system(size: 10))
                        FlagAwareText(text: award.silver.isEmpty ? "—" : award.silver,
                                      font: .palatino(.caption2),
                                      size: 11,
                                      foreground: .secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 4) {
                        Text("🥉").font(.system(size: 10))
                        FlagAwareText(text: award.bronze.isEmpty ? "—" : award.bronze,
                                      font: .palatino(.caption2),
                                      size: 11,
                                      foreground: .secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        } else {
            Button {
                let newAward = PersonalAwardModel(sortOrder: personalAwards.count)
                modelContext.insert(newAward)
                editingAward = newAward
            } label: {
                Image(systemName: "plus")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Text("").frame(width: 88)
                            ForEach([ProfileSheet.MedalSlot.gold, .silver, .bronze], id: \.id) { medal in
                                Text(medal.emoji).font(.title2).frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 8)
                        Divider()
                        ForEach(ProfileSheet.TopRegion.allCases) { region in
                            VStack(spacing: 0) {
                                HStack(spacing: 0) {
                                    Text(region.rawValue)
                                        .font(.palatino(.caption, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 88, alignment: .leading)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                    ForEach([ProfileSheet.MedalSlot.gold, .silver, .bronze], id: \.id) { medal in
                                        let emoji = tableFlag(region: region, medal: medal)
                                        Button {
                                            editingSpot = ProfileSheet.TopSpot(region: region, medal: medal)
                                        } label: {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(Color(.systemGray5))
                                                    .frame(width: 52, height: 52)
                                                if let emoji {
                                                    FlagLabel(emoji: emoji, size: 34)
                                                } else {
                                                    Image(systemName: "plus")
                                                        .font(.system(size: 16, weight: .light))
                                                        .foregroundStyle(Color(.systemGray3))
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                                .padding(.vertical, 6)
                                if region != ProfileSheet.TopRegion.allCases.last {
                                    Divider().padding(.leading, 88)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 12)
                // ── Premios personales (2 slots) ──
                let awardSlots: [PersonalAwardModel?] = (0..<2).map { i in i < personalAwards.count ? personalAwards[i] : nil }
                HStack(spacing: 8) {
                    awardSlot(awardSlots[0])
                    awardSlot(awardSlots[1])
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
                .padding(.top, 4)
                }
                .padding(.top, 16)
                // ── Categorías personales + Lista personal 1 (mismo card, con separador) ──
                VStack(spacing: 0) {
                    Button { showSubjectiveCategories = true } label: {
                        HStack {
                            Label("Categorías personales", systemImage: "trophy")
                                .font(.palatino(.body))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 16)
                    Button { showList1 = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "list.bullet")
                                .font(.palatino(.body))
                                .foregroundStyle(.primary)
                            FlagAwareText(text: list1Title.isEmpty ? "Lista personal" : list1Title,
                                          font: .palatino(.body),
                                          size: 18)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }
            .navigationTitle("Premios personales")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAlphabet = true } label: {
                        Image(systemName: "abc").font(.body)
                    }
                }
            }
        }
        .sheet(isPresented: $showAlphabet) {
            FlagAlphabetSheet(
                allFeatures: allFeatures,
                visitedIsoCodes: visitedIsoCodes,
                countingModeRaw: countingModeRaw
            )
        }
        .sheet(isPresented: $showSubscription) {
            SubscriptionSheet()
        }
        .sheet(item: $editingSpot) { spot in
            TableFlagPickerSheet(
                spot: spot,
                features: visitedFeaturesForRegion(spot.region),
                currentEmoji: tableFlag(region: spot.region, medal: spot.medal),
                usedEmojis: allUsedTableFlags(),
                onSelect: { emoji in setTableFlag(emoji, region: spot.region, medal: spot.medal) },
                onClear: { setTableFlag(nil, region: spot.region, medal: spot.medal) }
            )
        }
        .sheet(item: $editingAward) { award in
            PersonalAwardSheet(
                award: award,
                onDelete: {
                    modelContext.delete(award)
                    editingAward = nil
                }
            )
        }
        .sheet(isPresented: $showList1) {
            PersonalListSheet(title: $list1Title, content: $list1Content)
        }
        .sheet(isPresented: $showSubjectiveCategories) {
            SubjectiveCategoriesSheet(
                allFeatures: allFeatures,
                visitedIsoCodes: visitedIsoCodes
            )
        }
        .appColorScheme()
    }
}

// MARK: - Personal List Sheet
struct PersonalListSheet: View {
    @Binding var title: String
    @Binding var content: String
    @Environment(\.dismiss) private var dismiss
    @State private var titleDraft: String = ""
    @State private var contentDraft: String = ""
    @FocusState private var contentFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Título de la lista", text: $titleDraft)
                    .font(.palatino(.title3, weight: .bold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                Divider()
                TextEditor(text: $contentDraft)
                    .font(.palatino(.body))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .focused($contentFocused)
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Guardar") {
                        title = titleDraft
                        content = contentDraft
                        dismiss()
                    }
                    .font(.palatino(.body, weight: .bold))
                }
            }
        }
        .onAppear {
            titleDraft = title
            contentDraft = content
        }
        .presentationDetents([.large])
    }
}

// MARK: - Personal Award Sheet
struct PersonalAwardSheet: View {
    let award: PersonalAwardModel
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var gold: String
    @State private var silver: String
    @State private var bronze: String
    @State private var extras: [String]
    @State private var showDeleteConfirm = false

    private let maxExtras = 5

    init(award: PersonalAwardModel, onDelete: @escaping () -> Void) {
        self.award = award
        self.onDelete = onDelete
        _title = State(initialValue: award.title)
        _gold = State(initialValue: award.gold)
        _silver = State(initialValue: award.silver)
        _bronze = State(initialValue: award.bronze)
        _extras = State(initialValue: award.extras)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Título")
                            .font(.palatino(.body))
                            .foregroundStyle(.secondary)
                        TextField("Nombre del premio", text: $title)
                            .font(.palatino(.body))
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section(header: Text("Medallas").font(.palatino(.caption))) {
                    HStack {
                        Text("🥇")
                        TextField("Oro", text: $gold)
                            .font(.palatino(.body))
                    }
                    HStack {
                        Text("🥈")
                        TextField("Plata", text: $silver)
                            .font(.palatino(.body))
                    }
                    HStack {
                        Text("🥉")
                        TextField("Bronce", text: $bronze)
                            .font(.palatino(.body))
                    }
                }
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Eliminar premio")
                                .font(.palatino(.body))
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(title.isEmpty ? "Premio personal" : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }.font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Guardar") {
                        award.title = title
                        award.gold = gold
                        award.silver = silver
                        award.bronze = bronze
                        award.extras = extras.filter { !$0.isEmpty }
                        dismiss()
                    }
                    .font(.palatino(.body, weight: .bold))
                }
            }
            .alert("¿Eliminar este premio?", isPresented: $showDeleteConfirm) {
                Button("Eliminar", role: .destructive) { onDelete() }
                Button("Cancelar", role: .cancel) {}
            }
        }
        .appColorScheme()
    }
}

// MARK: - Categorías subjetivas (medallero)

enum SubjectiveCategory: String, CaseIterable, Identifiable {
    case overrated, underrated, cleanest, dirtiest, safestNight, mostDangerous,
         friendliestLocals, rudestTourists, bestStreetFood, cultureShock,
         hardestLanguage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overrated:          return "Sobrevalorados"
        case .underrated:         return "Infravalorados"
        case .dirtiest:           return "Más sucios"
        case .safestNight:        return "Más seguros de noche"
        case .mostDangerous:      return "Más peligrosos"
        case .friendliestLocals:  return "Locales más amables"
        case .rudestTourists:     return "Locales más maleducados"
        case .bestStreetFood:     return "Mejor comida callejera"
        case .cultureShock:       return "Mayor choque cultural"
        case .hardestLanguage:    return "Idioma más difícil"
        case .cleanest:           return "Más limpios"
        }
    }

    /// Emoji decorativo para la fila — aporta color sin depender de SF Symbols.
    var emoji: String {
        switch self {
        case .overrated:          return "📣"
        case .underrated:         return "💎"
        case .dirtiest:           return "🗑️"
        case .safestNight:        return "🌙"
        case .mostDangerous:      return "⚠️"
        case .friendliestLocals:  return "🤗"
        case .rudestTourists:     return "🙄"
        case .bestStreetFood:     return "🌮"
        case .cultureShock:       return "🌀"
        case .hardestLanguage:    return "🗣️"
        case .cleanest:           return "✨"
        }
    }
}

struct SubjectiveCategoriesSheet: View {
    let allFeatures: [CountryFeature]
    let visitedIsoCodes: Set<String>

    @Environment(\.dismiss) private var dismiss
    @AppStorage("subjectiveCategoriesTable") private var tableRaw: String = "{}"
    @AppStorage("subjectiveCategoriesOrder") private var orderRaw: String = "[]"
    @State private var editing: EditTarget? = nil
    @State private var isReordering: Bool = false

    struct EditTarget: Identifiable {
        let category: SubjectiveCategory
        let medal: ProfileSheet.MedalSlot
        var id: String { category.rawValue + "_" + medal.rawValue }
    }

    private func decodeOrder() -> [SubjectiveCategory] {
        let stored: [String]
        if let data = orderRaw.data(using: .utf8),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            stored = arr
        } else {
            stored = []
        }
        var seen = Set<String>()
        var ordered: [SubjectiveCategory] = []
        for raw in stored {
            if let cat = SubjectiveCategory(rawValue: raw), seen.insert(raw).inserted {
                ordered.append(cat)
            }
        }
        for cat in SubjectiveCategory.allCases where seen.insert(cat.rawValue).inserted {
            ordered.append(cat)
        }
        return ordered
    }
    private func saveOrder(_ cats: [SubjectiveCategory]) {
        let arr = cats.map(\.rawValue)
        let data = (try? JSONEncoder().encode(arr)) ?? Data()
        orderRaw = String(data: data, encoding: .utf8) ?? "[]"
    }

    // MARK: - Persistencia en AppStorage
    private func tableDict() -> [String: String] {
        guard let data = tableRaw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }
    private func key(_ cat: SubjectiveCategory, _ medal: ProfileSheet.MedalSlot) -> String {
        cat.rawValue + "_" + medal.rawValue
    }
    private func flag(_ cat: SubjectiveCategory, _ medal: ProfileSheet.MedalSlot) -> String? {
        tableDict()[key(cat, medal)]
    }
    private func setFlag(_ emoji: String?, cat: SubjectiveCategory, medal: ProfileSheet.MedalSlot) {
        var dict = tableDict()
        let k = key(cat, medal)
        if let emoji { dict[k] = emoji } else { dict.removeValue(forKey: k) }
        let data = (try? JSONEncoder().encode(dict)) ?? Data()
        tableRaw = String(data: data, encoding: .utf8) ?? "{}"
    }
    /// Banderas ya usadas en esta categoría (para evitar duplicados dentro
    /// de la misma fila). Entre categorías sí se permiten repetidas.
    private func usedEmojisInCategory(_ cat: SubjectiveCategory) -> Set<String> {
        let dict = tableDict()
        var used: Set<String> = []
        for m in [ProfileSheet.MedalSlot.gold, .silver, .bronze] {
            if let v = dict[key(cat, m)] { used.insert(v) }
        }
        return used
    }

    /// Features visitadas, ordenadas alfabéticamente.
    private var visitedFeatures: [CountryFeature] {
        allFeatures
            .filter { visitedIsoCodes.contains($0.isoCode) }
            .sorted { $0.localizedName.localizedCompare($1.localizedName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isReordering {
                    List {
                        ForEach(decodeOrder()) { cat in
                            HStack(spacing: 10) {
                                Text(cat.emoji).font(.system(size: 18))
                                Text(cat.title).font(.palatino(.body, weight: .bold))
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .onMove { indices, newOffset in
                            var current = decodeOrder()
                            current.move(fromOffsets: indices, toOffset: newOffset)
                            saveOrder(current)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .environment(\.editMode, .constant(.active))
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(decodeOrder()) { cat in
                                categoryRow(cat)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle("Categorías personales")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isReordering ? "Listo" : "Editar") {
                        withAnimation { isReordering.toggle() }
                    }
                    .font(.palatino(.body, weight: isReordering ? .bold : .regular))
                }
            }
        }
        .sheet(item: $editing) { target in
            SubjectiveFlagPickerSheet(
                category: target.category,
                medal: target.medal,
                features: visitedFeatures,
                currentEmoji: flag(target.category, target.medal),
                usedEmojis: usedEmojisInCategory(target.category),
                onSelect: { emoji in setFlag(emoji, cat: target.category, medal: target.medal) },
                onClear: { setFlag(nil, cat: target.category, medal: target.medal) }
            )
        }
        .appColorScheme()
    }

    @ViewBuilder
    private func categoryRow(_ cat: SubjectiveCategory) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(cat.emoji).font(.system(size: 18))
                Text(cat.title)
                    .font(.palatino(.body, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
            }
            HStack(spacing: 10) {
                ForEach([ProfileSheet.MedalSlot.gold, .silver, .bronze], id: \.id) { medal in
                    let emoji = flag(cat, medal)
                    Button {
                        editing = EditTarget(category: cat, medal: medal)
                    } label: {
                        VStack(spacing: 4) {
                            Text(medal.emoji).font(.system(size: 14))
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray5))
                                    .frame(height: 62)
                                if let emoji {
                                    FlagLabel(emoji: emoji, size: 40)
                                } else {
                                    Image(systemName: "plus")
                                        .font(.system(size: 18, weight: .light))
                                        .foregroundStyle(Color(.systemGray3))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SubjectiveFlagPickerSheet: View {
    let category: SubjectiveCategory
    let medal: ProfileSheet.MedalSlot
    let features: [CountryFeature]
    let currentEmoji: String?
    let usedEmojis: Set<String>
    let onSelect: (String) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    private var filtered: [CountryFeature] {
        guard !searchText.isEmpty else { return features }
        let q = searchText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return features.filter {
            $0.localizedName
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .contains(q)
        }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Buscar país…", text: $searchText).autocorrectionDisabled()
                }
                .padding(10)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                ScrollView {
                    if filtered.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "flag.slash")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("No tienes países visitados que coincidan.")
                                .font(.palatino(.subheadline))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 60)
                        .padding(.horizontal, 32)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(filtered, id: \.isoCode) { feature in
                                let emoji    = feature.flagEmoji ?? "🌐"
                                let isChosen = emoji == currentEmoji
                                // Usado = está en otra medalla de ESTA categoría.
                                // Entre categorías se permite repetir.
                                let isUsed   = usedEmojis.contains(emoji) && !isChosen
                                Button {
                                    guard !isUsed else { return }
                                    onSelect(emoji)
                                    dismiss()
                                } label: {
                                    VStack(spacing: 4) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(isChosen
                                                      ? Color.blue.opacity(0.18)
                                                      : isUsed ? Color(.systemGray6).opacity(0.4)
                                                               : Color(.systemGray6))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .strokeBorder(isChosen ? Color.blue : Color.clear,
                                                                      lineWidth: 2)
                                                )
                                                .frame(width: 60, height: 60)
                                            FlagLabel(emoji: emoji, size: 36)
                                                .opacity(isUsed ? 0.3 : 1.0)
                                        }
                                        Text(feature.localizedName)
                                            .font(.palatino(.caption2))
                                            .foregroundStyle(isUsed ? .tertiary : .secondary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(isUsed)
                            }
                        }
                        .padding(16)
                    }
                }

                if currentEmoji != nil {
                    Divider()
                    Button(role: .destructive) {
                        onClear()
                        dismiss()
                    } label: {
                        Text("Eliminar selección")
                            .font(.palatino(.body))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("\(medal.emoji) \(category.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .appColorScheme()
    }
}

// MARK: - Banderas por letra
struct FlagAlphabetSheet: View {
    let allFeatures: [CountryFeature]
    let visitedIsoCodes: Set<String>
    let countingModeRaw: String

    @Environment(\.dismiss) private var dismiss
    @AppStorage("isRaskmapPro") private var isRaskmapPro: Bool = false
    @State private var showSubscription: Bool = false

    private var countingMode: CountingMode { CountingMode(rawValue: countingModeRaw) ?? .all }

    private struct AlphaGroup: Identifiable {
        let id: String          // the letter
        let items: [(iso: String, flag: String, name: String)]
        let hasAnyCountry: Bool
    }

    private var groups: [AlphaGroup] {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { String($0) }
        let allCountable = allFeatures.filter { countingMode.counts($0.isoCode) && $0.flagEmoji != nil }
        let visited = allCountable
            .filter { visitedIsoCodes.contains($0.isoCode) }
            .sorted { $0.localizedName.localizedCompare($1.localizedName) == .orderedAscending }

        var visitedDict: [String: [(String, String, String)]] = [:]
        for f in visited {
            let letter = String(f.localizedName.uppercased().first ?? "?")
            visitedDict[letter, default: []].append((f.isoCode, f.flagEmoji!, f.localizedName))
        }
        var existsSet: Set<String> = []
        for f in allCountable {
            let letter = String(f.localizedName.uppercased().first ?? "?")
            existsSet.insert(letter)
        }
        return letters.map { letter in
            AlphaGroup(id: letter, items: visitedDict[letter] ?? [], hasAnyCountry: existsSet.contains(letter))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.id)
                                .font(.palatino(.largeTitle, weight: .bold))
                                .padding(.horizontal, 20)
                            if group.items.isEmpty {
                                Text(group.hasAnyCountry ? "Sin visitar" : "No existen")
                                    .font(.palatino(.caption))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 20)
                            } else {
                                let rows = stride(from: 0, to: group.items.count, by: 8).map {
                                    Array(group.items[$0..<min($0 + 8, group.items.count)])
                                }
                                ForEach(rows.indices, id: \.self) { r in
                                    HStack(spacing: 4) {
                                        ForEach(rows[r], id: \.iso) { item in
                                            FlagLabel(emoji: item.flag, size: 22)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 16)
                .blur(radius: isRaskmapPro ? 0 : 10)
                .allowsHitTesting(isRaskmapPro)
                .overlay(alignment: .top) {
                    if !isRaskmapPro {
                        Button { showSubscription = true } label: {
                            VStack(spacing: 10) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.purple)
                                Text("Función Pro")
                                    .font(.palatino(.body, weight: .bold))
                                    .foregroundStyle(.purple)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(countingMode == .all ? "Territorios visitados" : "Países visitados")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .sheet(isPresented: $showSubscription) { SubscriptionSheet() }
        .presentationDetents([.large])
        .appColorScheme()
    }
}

// MARK: - Países pluricontinentales
struct MultiContinentEntry: Identifiable {
    let id: String  // ISO code
    let flag: String
    let name: String
    let options: [(label: String, value: String)]
    let defaultValue: String
}

private let multiContinentEntries: [MultiContinentEntry] = [
    .init(id: "RUS", flag: "🇷🇺", name: "Rusia",
          options: [("Europa","europa"),("Asia","asia"),("Ambos","ambos")],
          defaultValue: "europa"),
    .init(id: "TUR", flag: "🇹🇷", name: "Turquía",
          options: [("Europa","europa"),("Asia","medioOriente"),("Ambos","ambos")],
          defaultValue: "medioOriente"),
    .init(id: "CYP", flag: "🇨🇾", name: "Chipre",
          options: [("Europa","europa"),("Asia","medioOriente"),("Ambos","ambos")],
          defaultValue: "europa"),
    .init(id: "AZE", flag: "🇦🇿", name: "Azerbaiyán",
          options: [("Europa","europa"),("Asia","asia"),("Ambos","ambos")],
          defaultValue: "asia"),
    .init(id: "GEO", flag: "🇬🇪", name: "Georgia",
          options: [("Europa","europa"),("Asia","asia"),("Ambos","ambos")],
          defaultValue: "asia"),
    .init(id: "KAZ", flag: "🇰🇿", name: "Kazajistán",
          options: [("Europa","europa"),("Asia","asia"),("Ambos","ambos")],
          defaultValue: "asia"),
    .init(id: "EGY", flag: "🇪🇬", name: "Egipto",
          options: [("África","africa"),("Asia","asia"),("Ambos","ambos")],
          defaultValue: "africa"),
]

struct MultiContinentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("multiContinentRaw") private var rawAssignments: String = "{}"
    @State private var showInfoToast: Bool = false

    private var assignments: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(rawAssignments.utf8))) ?? [:]
    }

    private func setAssignment(_ iso: String, _ value: String) {
        var dict = assignments
        dict[iso] = value
        if let data = try? JSONEncoder().encode(dict) {
            rawAssignments = String(data: data, encoding: .utf8) ?? "{}"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(multiContinentEntries) { entry in
                        HStack(spacing: 12) {
                            FlagLabel(emoji: entry.flag, size: 22)
                            Text(entry.name).font(.palatino(.body))
                            Spacer()
                            Picker("", selection: Binding(
                                get: { assignments[entry.id] ?? entry.defaultValue },
                                set: { setAssignment(entry.id, $0) }
                            )) {
                                ForEach(entry.options, id: \.value) { opt in
                                    Text(opt.label).tag(opt.value)
                                }
                            }
                            .pickerStyle(.menu)
                            .font(.palatino(.body))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        if entry.id != multiContinentEntries.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Países pluricontinentales")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { withAnimation { showInfoToast = true } } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
        }
        .overlay {
            if showInfoToast {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 16) {
                        Image(systemName: "info.circle.fill")
                            .font(.title2).foregroundStyle(.blue)
                        Text("Algunos países se extienden por dos continentes (como Rusia, Turquía o Egipto). Aquí decides en qué continente contarlos —o en ambos— para tus estadísticas por regiones y los logros de continentes completos.")
                            .font(.palatino(.body))
                            .multilineTextAlignment(.center)
                        Button { withAnimation { showInfoToast = false } } label: {
                            Text("Entendido")
                                .font(.palatino(.body, weight: .bold))
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(.white)
                        }.buttonStyle(.plain)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 32)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                .animation(.spring(duration: 0.3), value: showInfoToast)
            }
        }
        .presentationDetents([.large])
        .appColorScheme()
    }
}

// MARK: - Países en más de un hemisferio
struct MultiHemisphereSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("multiHemisphereRaw") private var rawAssignments: String = "{}"
    @State private var showInfoToast: Bool = false

    private var assignments: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(rawAssignments.utf8))) ?? [:]
    }

    private func setAssignment(_ iso: String, _ value: String) {
        var dict = assignments
        dict[iso] = value
        if let data = try? JSONEncoder().encode(dict) {
            rawAssignments = String(data: data, encoding: .utf8) ?? "{}"
        }
    }

    private let entries = AchievementKind.multiHemisphereData

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(entries, id: \.iso) { entry in
                        HStack(spacing: 12) {
                            FlagLabel(emoji: entry.flag, size: 22)
                            Text(entry.name).font(.palatino(.body))
                            Spacer()
                            Picker("", selection: Binding(
                                get: { assignments[entry.iso] ?? entry.defaultH },
                                set: { setAssignment(entry.iso, $0) }
                            )) {
                                Text("Norte").tag("norte")
                                Text("Sur").tag("sur")
                                Text("Ambos").tag("ambos")
                            }
                            .pickerStyle(.menu)
                            .font(.palatino(.body))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        if entry.iso != entries.last?.iso {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Países plurihemisferiales")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { withAnimation { showInfoToast = true } } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
        }
        .overlay {
            if showInfoToast {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 16) {
                        Image(systemName: "info.circle.fill")
                            .font(.title2).foregroundStyle(.blue)
                        Text("Algunos países se extienden por ambos hemisferios (norte y sur). Aquí decides en cuál contarlos —o en ambos— para tus estadísticas y el logro «Ambos hemisferios». Afecta también a los porcentajes de hemisferio en la pantalla de logros.")
                            .font(.palatino(.body))
                            .multilineTextAlignment(.center)
                        Button { withAnimation { showInfoToast = false } } label: {
                            Text("Entendido")
                                .font(.palatino(.body, weight: .bold))
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(.white)
                        }.buttonStyle(.plain)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 32)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                .animation(.spring(duration: 0.3), value: showInfoToast)
            }
        }
        .presentationDetents([.large])
        .appColorScheme()
    }
}

// MARK: - Selector de aeropuerto favorito
struct FavoriteAirportPickerSheet: View {
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var query: String = ""

    init(selected: Binding<String>) {
        self._selected = selected
        self._draft = State(initialValue: selected.wrappedValue)
    }

    private static let allAirports = RoutePickerSheet.allAirports

    private var filtered: [AirportData] {
        if query.isEmpty { return Self.allAirports }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return Self.allAirports.filter {
            $0.iata.range(of: query, options: opts) != nil ||
            $0.name.range(of: query, options: opts) != nil ||
            $0.city.range(of: query, options: opts) != nil ||
            $0.countryName.range(of: query, options: opts) != nil
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List(filtered, id: \.iata) { ap in
                    Button {
                        draft = draft == ap.iata ? "" : ap.iata
                    } label: {
                        HStack(spacing: 10) {
                            FlagLabel(emoji: ap.flagEmoji, size: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(ap.iata).font(.palatino(.subheadline, weight: .bold))
                                    Text(ap.name).font(.palatino(.body)).foregroundStyle(.primary)
                                }
                                Text(ap.city).font(.palatino(.caption)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if draft == ap.iata {
                                Image(systemName: "star.fill").foregroundStyle(.yellow)
                            }
                        }
                    }.buttonStyle(.plain)
                }
                .listStyle(.plain)
                .searchable(text: $query, prompt: "Buscar aeropuerto o IATA")

                Button {
                    selected = draft
                    dismiss()
                } label: {
                    Text("Aceptar")
                        .font(.palatino(.body, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(Color(.systemBackground))
            }
            .navigationTitle("Aeropuerto favorito")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .presentationDetents([.large])
        .appColorScheme()
    }
}

// MARK: - Fila de selector de color
struct ColorPickerRow: View {
    let label: String
    @Binding var color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.palatino(.body))
            Spacer()
            ColorPicker("", selection: $color, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 32, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Country.self, inMemory: true)
}

// MARK: - Extensión de fuente (Satoshi)
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
        case .bold, .semibold: return .custom("Satoshi-Bold", size: size)
        case .medium:          return .custom("Satoshi-Medium", size: size)
        case .light:           return .custom("Satoshi-Light", size: size)
        default:               return .custom("Satoshi-Regular", size: size)
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

// MARK: - Route wizard (multi-step)
struct RouteWizardSheet: View {
    @Binding var airports: [TripAirport]        // outbound route (ordered)
    @Binding var returnAirports: [TripAirport]  // return route (ordered), empty = one-way
    @Binding var airlines: [TripAirline]
    @Binding var hasLayover: Bool
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    enum Step: Equatable {
        case departure, layoverChoice, layoverList
        case layoverAddAirport, layoverAddAirline
        case finalDest, finalAirline, returnChoice
        case returnAirlineChoice, returnAirline
        case returnDeparture, returnLayoverChoice, returnLayoverList
        case returnLayoverAddAirport, returnLayoverAddAirline
        case returnFinalDest, returnFinalAirline
        case returnSameRouteAirline  // aerolínea por tramo para misma ruta de vuelta con escalas
    }

    @State private var step: Step = .departure
    @State private var departureIata = ""
    @State private var layoverStops: [(iata: String, airline: String)] = []
    @State private var pendingLayoverIata = ""
    @State private var finalIata = ""
    @State private var finalAirline = ""
    @State private var returnAirlineDraft = ""
    @State private var returnDepartureIata = ""
    @State private var returnSameRouteAirlineIdx: Int = 0  // índice del tramo de vuelta en curso
    @State private var returnLayoverStops: [(iata: String, airline: String)] = []
    @State private var returnPendingLayoverIata = ""
    @State private var returnFinalIata = ""
    @State private var returnFinalAirline = ""
    @State private var query = ""
    @State private var didPrepopulate = false

    @AppStorage("favoriteAirport") private var favoriteAirport: String = ""

    private static let allAirports = RoutePickerSheet.allAirports
    private static var allAirlines: [AirlineData] { AirlinePickerSheet.airlines }

    // Back-navigation target for each step
    private var backStep: Step? {
        switch step {
        case .departure:              return nil
        case .layoverChoice:          return .departure
        case .layoverList:            return .layoverChoice
        case .layoverAddAirport:      return layoverStops.isEmpty ? .layoverChoice : .layoverList
        case .layoverAddAirline:      return .layoverAddAirport
        case .finalDest:              return layoverStops.isEmpty ? .layoverChoice : .layoverList
        case .finalAirline:           return .finalDest
        case .returnChoice:           return .finalAirline
        case .returnAirlineChoice:    return .returnChoice
        case .returnAirline:          return .returnAirlineChoice
        case .returnDeparture:        return .returnChoice
        case .returnLayoverChoice:    return .returnDeparture
        case .returnLayoverList:      return .returnLayoverChoice
        case .returnLayoverAddAirport: return returnLayoverStops.isEmpty ? .returnLayoverChoice : .returnLayoverList
        case .returnLayoverAddAirline: return .returnLayoverAddAirport
        case .returnFinalDest:        return returnLayoverStops.isEmpty ? .returnLayoverChoice : .returnLayoverList
        case .returnFinalAirline:     return .returnFinalDest
        case .returnSameRouteAirline: return .returnAirlineChoice  // se usa solo si idx==0; goBack() lo gestiona
        }
    }

    private func goBack() {
        if step == .returnSameRouteAirline {
            if returnSameRouteAirlineIdx > 0 {
                returnSameRouteAirlineIdx -= 1
                if returnSameRouteAirlineIdx < returnLayoverStops.count {
                    returnLayoverStops[returnSameRouteAirlineIdx].airline = ""
                } else {
                    returnFinalAirline = ""
                }
                query = ""; return
            } else {
                query = ""; step = .returnAirlineChoice; return
            }
        }
        guard let prev = backStep else { dismiss(); return }
        if step == .layoverAddAirline { pendingLayoverIata = "" }
        if step == .returnLayoverAddAirline { returnPendingLayoverIata = "" }
        query = ""
        step = prev
    }

    private var filteredAirports: [AirportData] {
        if query.isEmpty { return Self.allAirports }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return Self.allAirports.filter {
            $0.iata.range(of: query, options: opts) != nil ||
            $0.name.range(of: query, options: opts) != nil ||
            $0.city.range(of: query, options: opts) != nil ||
            $0.countryName.range(of: query, options: opts) != nil
        }
    }

    private func airportListForStep(showFavorite: Bool) -> [AirportData] {
        var list = filteredAirports
        guard showFavorite && query.isEmpty && !favoriteAirport.isEmpty else { return list }
        list.removeAll { $0.iata == favoriteAirport }
        if let fav = Self.allAirports.first(where: { $0.iata == favoriteAirport }) {
            list.insert(fav, at: 0)
        }
        return list
    }

    private var filteredAirlines: [AirlineData] {
        if query.isEmpty { return Self.allAirlines }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return Self.allAirlines.filter {
            $0.name.range(of: query, options: opts) != nil ||
            $0.iata.range(of: query, options: opts) != nil
        }
    }

    private var stepTitle: String {
        switch step {
        case .departure:          return "Aeropuerto de salida"
        case .layoverChoice:      return "Tipo de vuelo"
        case .layoverList:        return "Escalas"
        case .layoverAddAirport:  return "Aeropuerto de escala"
        case .layoverAddAirline:  return "Aerolínea del tramo"
        case .finalDest:          return "Destino final"
        case .finalAirline:       return "Aerolínea del vuelo"
        case .returnChoice:       return "¿Vuelta?"
        case .returnAirlineChoice: return "Aerolínea de vuelta"
        case .returnAirline:      return "Aerolínea de vuelta"
        case .returnDeparture:        return "Vuelta · Salida"
        case .returnLayoverChoice:    return "Vuelta · Tipo de vuelo"
        case .returnLayoverList:      return "Vuelta · Escalas"
        case .returnLayoverAddAirport: return "Vuelta · Aeropuerto de escala"
        case .returnLayoverAddAirline: return "Vuelta · Aerolínea del tramo"
        case .returnFinalDest:        return "Vuelta · Destino"
        case .returnFinalAirline:     return "Vuelta · Aerolínea"
        case .returnSameRouteAirline:
            let total = returnLayoverStops.count + 1
            return "Vuelta · Aerolínea \(returnSameRouteAirlineIdx + 1)/\(total)"
        }
    }

    private func buildAndSave(isReturn: Bool, differentReturnAirline: String? = nil) {
        let outbound = [departureIata] + layoverStops.map(\.iata) + [finalIata]
        // Outbound airports stored in order (count=1 each, stats computed later from both legs)
        airports = outbound.map { TripAirport(iata: $0, count: 1) }
        // Return route: outbound reversed (same path back)
        returnAirports = isReturn ? outbound.reversed().map { TripAirport(iata: $0, count: 1) } : []
        let mult = (isReturn && differentReturnAirline == nil) ? 2 : 1
        var alCounts: [String: Int] = [:]
        for stop in layoverStops where !stop.airline.isEmpty {
            alCounts[stop.airline, default: 0] += mult
        }
        if !finalAirline.isEmpty { alCounts[finalAirline, default: 0] += 1 }
        if isReturn {
            let rl = differentReturnAirline ?? finalAirline
            if !rl.isEmpty { alCounts[rl, default: 0] += 1 }
        }
        airlines = alCounts.map { TripAirline(name: $0.key, count: $0.value) }
        hasLayover = !layoverStops.isEmpty
        onDone(); dismiss()
    }

    private func buildAndSaveWithReturnRoute() {
        let outbound = [departureIata] + layoverStops.map(\.iata) + [finalIata]
        let returning = [returnDepartureIata] + returnLayoverStops.map(\.iata) + [returnFinalIata]
        // Store each leg separately in order — destination = outbound.last, layovers = intermediates of each leg
        airports = outbound.map { TripAirport(iata: $0, count: 1) }
        returnAirports = returning.map { TripAirport(iata: $0, count: 1) }
        var alCounts: [String: Int] = [:]
        for stop in layoverStops where !stop.airline.isEmpty { alCounts[stop.airline, default: 0] += 1 }
        if !finalAirline.isEmpty { alCounts[finalAirline, default: 0] += 1 }
        for stop in returnLayoverStops where !stop.airline.isEmpty { alCounts[stop.airline, default: 0] += 1 }
        if !returnFinalAirline.isEmpty { alCounts[returnFinalAirline, default: 0] += 1 }
        airlines = alCounts.map { TripAirline(name: $0.key, count: $0.value) }
        hasLayover = !layoverStops.isEmpty || !returnLayoverStops.isEmpty
        onDone(); dismiss()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) { stepView }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if backStep == nil {
                        Button("Cancelar") { dismiss() }.font(.palatino(.body))
                    } else {
                        Button("Atrás") { goBack() }.font(.palatino(.body))
                    }
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(true)
        .onAppear {
            guard !didPrepopulate else { return }
            didPrepopulate = true
            let aps = airports; let als = airlines
            guard aps.count >= 2 else { return }

            // Algunos trips legacy guardan los aeropuertos como ruta expandida
            // tipo [MAD, ARN, MAD] o [MAD, ARN, ARN] (vuelo directo round-trip
            // representado como path completo). Si detectamos que el último
            // aeropuerto duplica al primero o al penúltimo, lo recortamos:
            // tomamos como ruta de IDA la mitad que NO repite y dejamos el
            // resto a `returnAirports` (si lo hay) — la wizard reconstruye
            // la vuelta cuando el usuario lo confirma.
            var trimmed = aps.map { $0.iata }
            // Caso: ruta termina volviendo al origen (round-trip expandido).
            if trimmed.count >= 3, trimmed.first == trimmed.last {
                // Quédate con la mitad de IDA: hasta el "punto medio" (último
                // aeropuerto antes de empezar a volver). Para [MAD, ARN, MAD]
                // → [MAD, ARN]. Para [MAD, FRA, ARN, FRA, MAD] → [MAD, FRA, ARN].
                if trimmed.count % 2 == 1 {
                    let mid = trimmed.count / 2
                    trimmed = Array(trimmed.prefix(mid + 1))
                } else {
                    // Par: ambigüo, recortamos el último para no duplicar.
                    trimmed = Array(trimmed.dropLast())
                }
            }
            // Caso: el último iata aparece dos veces seguidas al final
            // ([MAD, ARN, ARN] — bug histórico). Dedupea consecutivos.
            var dedup: [String] = []
            for iata in trimmed {
                if dedup.last != iata { dedup.append(iata) }
            }
            trimmed = dedup
            guard trimmed.count >= 2 else { return }

            departureIata = trimmed[0]
            finalIata = trimmed[trimmed.count - 1]
            let middle = Array(trimmed[1..<max(1, trimmed.count - 1)])
            layoverStops = middle.enumerated().map { i, iata in
                (iata: iata, airline: i < als.count ? als[i].name : "")
            }
            let lastIdx = middle.count
            finalAirline = lastIdx < als.count ? als[lastIdx].name : (als.last?.name ?? "")
        }
        .appColorScheme()
    }

    @ViewBuilder private var stepView: some View {
        switch step {
        case .departure:
            airportSearch(hint: "Ciudad, aeropuerto o IATA", showFavorite: true) { iata in
                departureIata = iata; query = ""; step = .layoverChoice
            }
        case .layoverChoice:
            layoverChoiceView
        case .layoverList:
            layoverListView
        case .layoverAddAirport:
            airportSearch(hint: "Ciudad, aeropuerto o IATA") { iata in
                pendingLayoverIata = iata; query = ""; step = .layoverAddAirline
            }
        case .layoverAddAirline:
            airlineSearch(hint: "Aerolínea") { name in
                layoverStops.append((iata: pendingLayoverIata, airline: name))
                pendingLayoverIata = ""; query = ""; step = .layoverList
            }
        case .finalDest:
            airportSearch(hint: "Ciudad, aeropuerto o IATA") { iata in
                finalIata = iata; query = ""; step = .finalAirline
            }
        case .finalAirline:
            airlineSearch(hint: "Aerolínea") { name in
                finalAirline = name; query = ""; step = .returnChoice
            }
        case .returnChoice:
            returnView
        case .returnAirlineChoice:
            returnAirlineChoiceView
        case .returnAirline:
            airlineSearch(hint: "Aerolínea") { name in
                returnAirlineDraft = name; query = ""
                buildAndSave(isReturn: true, differentReturnAirline: name)
            }
        case .returnDeparture:
            airportSearch(hint: "Ciudad, aeropuerto o IATA") { iata in
                returnDepartureIata = iata; query = ""; step = .returnLayoverChoice
            }
        case .returnLayoverChoice:
            returnLayoverChoiceView
        case .returnLayoverList:
            returnLayoverListView
        case .returnLayoverAddAirport:
            airportSearch(hint: "Ciudad, aeropuerto o IATA") { iata in
                returnPendingLayoverIata = iata; query = ""; step = .returnLayoverAddAirline
            }
        case .returnLayoverAddAirline:
            airlineSearch(hint: "Aerolínea") { name in
                returnLayoverStops.append((iata: returnPendingLayoverIata, airline: name))
                returnPendingLayoverIata = ""; query = ""; step = .returnLayoverList
            }
        case .returnFinalDest:
            airportSearch(hint: "Ciudad, aeropuerto o IATA", showFavorite: true) { iata in
                returnFinalIata = iata; query = ""; step = .returnFinalAirline
            }
        case .returnFinalAirline:
            airlineSearch(hint: "Aerolínea") { name in
                returnFinalAirline = name; query = ""
                buildAndSaveWithReturnRoute()
            }
        case .returnSameRouteAirline:
            // Pide aerolínea para cada tramo de vuelta (misma ruta, aerolíneas distintas)
            airlineSearch(hint: "Aerolínea") { name in
                if returnSameRouteAirlineIdx < returnLayoverStops.count {
                    returnLayoverStops[returnSameRouteAirlineIdx].airline = name
                    returnSameRouteAirlineIdx += 1
                    query = ""
                    // El step no cambia — el índice actualizado re-renderiza el título
                } else {
                    returnFinalAirline = name
                    query = ""
                    buildAndSaveWithReturnRoute()
                }
            }
        }
    }

    // ── Return airline choice ──
    private var returnAirlineChoiceView: some View {
        VStack(spacing: 24) {
            Spacer()
            if layoverStops.isEmpty {
                // Vuelo directo: misma o diferente aerolínea
                Text("¿Misma aerolínea a la vuelta?")
                    .font(.palatino(.title3, weight: .bold)).multilineTextAlignment(.center)
                if !finalAirline.isEmpty {
                    Text(finalAirline).font(.palatino(.subheadline)).foregroundStyle(.secondary)
                }
            } else {
                // Vuelo con escalas: mostrar resumen de tramos de ida
                Text("¿Mismas aerolíneas en todos los tramos?")
                    .font(.palatino(.title3, weight: .bold)).multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(layoverStops.indices, id: \.self) { i in
                        let prev = i == 0 ? departureIata : layoverStops[i - 1].iata
                        let stop = layoverStops[i]
                        HStack(spacing: 4) {
                            Text("\(prev) → \(stop.iata)").font(.palatino(.caption, weight: .bold))
                            if !stop.airline.isEmpty {
                                Text("· \(stop.airline)").font(.palatino(.caption)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    let lastFrom = layoverStops.last?.iata ?? departureIata
                    HStack(spacing: 4) {
                        Text("\(lastFrom) → \(finalIata)").font(.palatino(.caption, weight: .bold))
                        if !finalAirline.isEmpty {
                            Text("· \(finalAirline)").font(.palatino(.caption)).foregroundStyle(.secondary)
                        }
                    }
                }.padding(.horizontal, 32)
            }
            VStack(spacing: 12) {
                Button { buildAndSave(isReturn: true) } label: {
                    Text("Sí, las mismas")
                        .font(.palatino(.body, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                Button {
                    if layoverStops.isEmpty {
                        query = ""; step = .returnAirline
                    } else {
                        // Flujo secuencial: pre-poblar la ruta de vuelta invertida y pedir aerolínea por tramo
                        returnDepartureIata = finalIata
                        returnFinalIata = departureIata
                        returnLayoverStops = layoverStops.reversed().map { (iata: $0.iata, airline: "") }
                        returnSameRouteAirlineIdx = 0
                        query = ""; step = .returnSameRouteAirline
                    }
                } label: {
                    Text(layoverStops.isEmpty ? "No, diferente aerolínea" : "No, introduzco tramo a tramo")
                        .font(.palatino(.body, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.primary)
                }
            }.padding(.horizontal, 24)
            Spacer()
        }
    }

    // ── Airport search inline ──
    @ViewBuilder
    private func airportSearch(hint: String, showFavorite: Bool = false, onSelect: @escaping (String) -> Void) -> some View {
        let airports = airportListForStep(showFavorite: showFavorite)
        let fav = favoriteAirport
        VStack(spacing: 0) {
            searchBar(placeholder: hint)
            Divider()
            List(airports, id: \.iata) { ap in
                Button { onSelect(ap.iata) } label: {
                    HStack(spacing: 10) {
                        FlagLabel(emoji: ap.flagEmoji, size: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                if showFavorite && ap.iata == fav && query.isEmpty {
                                    Text("⭐️").font(.caption2)
                                }
                                Text(ap.iata).font(.palatino(.subheadline, weight: .bold))
                                Text(ap.name).font(.palatino(.body)).foregroundStyle(.primary)
                            }
                            Text(ap.city).font(.palatino(.caption)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.listStyle(.plain)
        }
    }

    // ── Airline search inline ──
    @ViewBuilder
    private func airlineSearch(hint: String, onSelect: @escaping (String) -> Void) -> some View {
        VStack(spacing: 0) {
            searchBar(placeholder: hint)
            Divider()
            List(filteredAirlines, id: \.iata) { al in
                Button { onSelect(al.name) } label: {
                    HStack {
                        Text(al.name).font(.palatino(.body)).foregroundStyle(.primary)
                        Spacer()
                        Text(al.iata).font(.palatino(.caption)).foregroundStyle(.secondary)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.listStyle(.plain)
        }
    }

    // ── Search bar ──
    @ViewBuilder
    private func searchBar(placeholder: String) -> some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $query)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(.systemGray6))
    }

    // ── Layover choice ──
    private var layoverChoiceView: some View {
        VStack(spacing: 24) {
            Spacer()
            if let ap = Self.allAirports.first(where: { $0.iata == departureIata }) {
                Text("Salida: \(departureIata) · \(ap.city)")
                    .font(.palatino(.subheadline)).foregroundStyle(.secondary)
            }
            Text("¿El vuelo tiene escala?")
                .font(.palatino(.title3, weight: .bold)).multilineTextAlignment(.center)
            VStack(spacing: 12) {
                Button {
                    // Vuelo directo = sin escalas. Si veníamos del prepopulate
                    // o de un cambio de modo, limpiamos las escalas para que
                    // no se cuele un layover heredado dentro de la ruta directa
                    // (bug MAD→ARN→ARN cuando airports legacy = [MAD, ARN, MAD/ARN]).
                    layoverStops = []
                    query = ""; step = .finalDest
                } label: {
                    Text("✈️  Vuelo directo")
                        .font(.palatino(.body, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                Button { query = ""; step = .layoverAddAirport } label: {
                    Text("🔄  Con escala(s)")
                        .font(.palatino(.body, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.primary)
                }
            }.padding(.horizontal, 24)
            Spacer()
        }
    }

    // ── Layover list ──
    private var layoverListView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(layoverStops.indices, id: \.self) { i in
                        let stop = layoverStops[i]
                        let ap = Self.allAirports.first { $0.iata == stop.iata }
                        HStack(spacing: 10) {
                            FlagLabel(emoji: ap?.flagEmoji ?? "🌐", size: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(stop.iata) – \(ap?.name ?? stop.iata)")
                                    .font(.palatino(.caption, weight: .bold))
                                Text(stop.airline.isEmpty ? "Sin aerolínea" : stop.airline)
                                    .font(.palatino(.caption)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { layoverStops.remove(at: i) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.red.opacity(0.7))
                            }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        if i < layoverStops.count - 1 { Divider().padding(.leading, 16) }
                    }
                }
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16).padding(.top, 16)
            }
            VStack(spacing: 10) {
                Button { query = ""; step = .layoverAddAirport } label: {
                    Label("Añadir otra escala", systemImage: "plus.circle")
                        .font(.palatino(.body))
                }
                Button { query = ""; step = .finalDest } label: {
                    Text("Siguiente →")
                        .font(.palatino(.body, weight: .bold)).frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            .background(Color(.systemBackground))
        }
    }

    // ── Return choice ──
    private var returnView: some View {
        VStack(spacing: 24) {
            Spacer()
            let segments = [departureIata] + layoverStops.map(\.iata) + [finalIata]
            VStack(spacing: 6) {
                Text(segments.joined(separator: " → "))
                    .font(.palatino(.title3, weight: .bold)).multilineTextAlignment(.center)
                let cities = segments.compactMap { iata in Self.allAirports.first { $0.iata == iata }?.city }
                if !cities.isEmpty {
                    Text(cities.joined(separator: " → "))
                        .font(.palatino(.subheadline)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if !finalAirline.isEmpty {
                    Text(finalAirline).font(.palatino(.caption)).foregroundStyle(.tertiary)
                }
            }.padding(.horizontal, 24)
            Text("¿Misma ruta a la vuelta?")
                .font(.palatino(.title3, weight: .bold))
            VStack(spacing: 12) {
                Button {
                    // Siempre pasa por returnAirlineChoice para preguntar la aerolínea
                    query = ""; step = .returnAirlineChoice
                } label: {
                    Text("↩️  Sí, ida y vuelta (×2)")
                        .font(.palatino(.body, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                Button { buildAndSave(isReturn: false) } label: {
                    Text("✈️  No, solo ida")
                        .font(.palatino(.body, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.primary)
                }
                Button {
                    // Pre-fill: la salida de la vuelta es típicamente el último
                    // aeropuerto del outbound (auto-detect). El destino de la
                    // vuelta es típicamente el origen (favorito/casa). El usuario
                    // puede sobrescribir si la ruta es asimétrica de verdad.
                    returnDepartureIata = finalIata
                    returnFinalIata = departureIata
                    query = ""; step = .returnDeparture
                } label: {
                    Text("🔀  Ruta de vuelta diferente")
                        .font(.palatino(.body, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.primary)
                }
            }.padding(.horizontal, 24)
            Spacer()
        }
    }

    // ── Return layover choice ──
    private var returnLayoverChoiceView: some View {
        VStack(spacing: 24) {
            Spacer()
            if let ap = Self.allAirports.first(where: { $0.iata == returnDepartureIata }) {
                Text("Salida vuelta: \(returnDepartureIata) · \(ap.city)")
                    .font(.palatino(.subheadline)).foregroundStyle(.secondary)
            }
            Text("¿El vuelo de vuelta tiene escala?")
                .font(.palatino(.title3, weight: .bold)).multilineTextAlignment(.center)
            VStack(spacing: 12) {
                Button {
                    // Limpieza simétrica al `layoverChoiceView` — evita que
                    // cualquier escala heredada se cuele en la vuelta directa.
                    returnLayoverStops = []
                    query = ""; step = .returnFinalDest
                } label: {
                    Text("✈️  Vuelo directo")
                        .font(.palatino(.body, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                Button { query = ""; step = .returnLayoverAddAirport } label: {
                    Text("🔄  Con escala(s)")
                        .font(.palatino(.body, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.primary)
                }
            }.padding(.horizontal, 24)
            Spacer()
        }
    }

    // ── Return layover list ──
    private var returnLayoverListView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(returnLayoverStops.indices, id: \.self) { i in
                        let stop = returnLayoverStops[i]
                        let ap = Self.allAirports.first { $0.iata == stop.iata }
                        HStack(spacing: 10) {
                            FlagLabel(emoji: ap?.flagEmoji ?? "🌐", size: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(stop.iata) – \(ap?.name ?? stop.iata)")
                                    .font(.palatino(.caption, weight: .bold))
                                Text(stop.airline.isEmpty ? "Sin aerolínea" : stop.airline)
                                    .font(.palatino(.caption)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { returnLayoverStops.remove(at: i) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.red.opacity(0.7))
                            }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        if i < returnLayoverStops.count - 1 { Divider().padding(.leading, 16) }
                    }
                }
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16).padding(.top, 16)
            }
            VStack(spacing: 10) {
                Button { query = ""; step = .returnLayoverAddAirport } label: {
                    Label("Añadir otra escala", systemImage: "plus.circle")
                        .font(.palatino(.body))
                }
                Button { query = ""; step = .returnFinalDest } label: {
                    Text("Siguiente →")
                        .font(.palatino(.body, weight: .bold)).frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            .background(Color(.systemBackground))
        }
    }
}

// MARK: - Airport picker
struct RoutePickerSheet: View {
    @Binding var airports: [TripAirport]
    @Binding var airlines: [TripAirline]
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var showAirlines = false

    static let allAirports: [AirportData] = {
        guard let url = Bundle.main.url(forResource: "airports", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([AirportData].self, from: data) else { return [] }
        return arr.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }()

    private var filtered: [AirportData] {
        if query.isEmpty { return Self.allAirports }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return Self.allAirports.filter {
            $0.iata.range(of: query, options: opts) != nil ||
            $0.name.range(of: query, options: opts) != nil ||
            $0.city.range(of: query, options: opts) != nil
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Selected airports with count stepper
                if !airports.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(airports, id: \.iata) { ap in
                            let apData = Self.allAirports.first { $0.iata == ap.iata }
                            HStack(spacing: 10) {
                                FlagLabel(emoji: apData?.flagEmoji ?? "🌐", size: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(ap.iata) – \(apData?.name ?? ap.iata)")
                                        .font(.palatino(.caption, weight: .bold))
                                    Text(apData?.city ?? "").font(.palatino(.caption2)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Stepper("", value: Binding(
                                    get: { ap.count },
                                    set: { newVal in
                                        if let idx = airports.firstIndex(where: { $0.iata == ap.iata }) {
                                            airports[idx].count = newVal
                                        }
                                    }
                                ), in: 1...10)
                                .labelsHidden()
                                Text("\(ap.count)x")
                                    .font(.palatino(.caption, weight: .bold))
                                    .frame(width: 24, alignment: .trailing)
                                Button { airports.removeAll { $0.iata == ap.iata } } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red.opacity(0.6))
                                }.buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            Divider().padding(.leading, 16)
                        }
                    }
                    .background(Color(.systemGray6))
                    Divider()
                }

                List(filtered) { ap in
                    let isSelected = airports.contains(where: { $0.iata == ap.iata })
                    Button {
                        if isSelected {
                            airports.removeAll { $0.iata == ap.iata }
                        } else {
                            airports.append(TripAirport(iata: ap.iata, count: 1))
                        }
                    } label: {
                        HStack(spacing: 10) {
                            FlagLabel(emoji: ap.flagEmoji, size: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(ap.iata).font(.palatino(.subheadline, weight: .bold))
                                    Text(ap.name).font(.palatino(.body)).foregroundStyle(.primary)
                                }
                                Text(ap.city).font(.palatino(.caption)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
                        }
                    }.buttonStyle(.plain)
                }
                .listStyle(.plain)
                .searchable(text: $query, prompt: "Buscar aeropuerto o IATA")

                Button {
                    showAirlines = true
                } label: {
                    Text(airports.isEmpty ? "Selecciona aeropuertos" : "Continuar → Aerolíneas")
                        .font(.palatino(.body, weight: .bold)).frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(airports.isEmpty ? Color(.systemGray4) : Color.blue, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .disabled(airports.isEmpty)
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(Color(.systemBackground))
            }
            .navigationTitle("Ruta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .sheet(isPresented: $showAirlines) {
                AirlinePickerSheet(selected: $airlines, onDone: { dismiss() })
            }
        }
        .presentationDetents([.large])
        .appColorScheme()
    }
}

// Compatibility alias


// MARK: - Airline picker (multi-select with count)
struct AirlinePickerSheet: View {
    @Binding var selected: [TripAirline]
    var onDone: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    static let airlines: [AirlineData] = {
        guard let url = Bundle.main.url(forResource: "airlines", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([AirlineData].self, from: data) else { return [] }
        return arr.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }()

    private var filtered: [AirlineData] {
        if query.isEmpty { return Self.airlines }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return Self.airlines.filter {
            $0.name.range(of: query, options: opts) != nil ||
            $0.iata.range(of: query, options: opts) != nil
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Selected airlines with count stepper
                if !selected.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(selected, id: \.name) { al in
                            HStack(spacing: 10) {
                                Text(al.name).font(.palatino(.caption, weight: .bold))
                                Spacer()
                                Stepper("", value: Binding(
                                    get: { al.count },
                                    set: { newVal in
                                        if let idx = selected.firstIndex(where: { $0.name == al.name }) {
                                            selected[idx].count = newVal
                                        }
                                    }
                                ), in: 1...20)
                                .labelsHidden()
                                Text("\(al.count)x")
                                    .font(.palatino(.caption, weight: .bold))
                                    .frame(width: 24, alignment: .trailing)
                                Button { selected.removeAll { $0.name == al.name } } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red.opacity(0.6))
                                }.buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            Divider().padding(.leading, 16)
                        }
                    }
                    .background(Color(.systemGray6))
                    Divider()
                }

                List(filtered) { al in
                    let isSelected = selected.contains(where: { $0.name == al.name })
                    Button {
                        if isSelected {
                            selected.removeAll { $0.name == al.name }
                        } else {
                            selected.append(TripAirline(name: al.name, count: 1))
                        }
                    } label: {
                        HStack {
                            Text(al.name).font(.palatino(.body)).foregroundStyle(.primary)
                            Spacer()
                            if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
                        }
                    }.buttonStyle(.plain)
                }
                .listStyle(.plain)
                .searchable(text: $query, prompt: "Buscar aerolínea")

                Button {
                    dismiss()
                    onDone?()
                } label: {
                    Text(selected.isEmpty ? "Listo" : "Listo (\(selected.count) aerolínea\(selected.count == 1 ? "" : "s"))")
                        .font(.palatino(.body, weight: .bold)).frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(Color(.systemBackground))
            }
            .navigationTitle("Aerolíneas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .appColorScheme()
    }
}

// MARK: - Airport stats sheet
struct AirportStatsSheet: View {
    let airports: [(iata: String, name: String, country: String, count: Int)]
    let allFeatures: [CountryFeature]
    @Environment(\.dismiss) private var dismiss

    private func flagEmoji(_ a2: String) -> String {
        guard a2.count == 2 else { return "🌐" }
        return a2.uppercased().unicodeScalars.compactMap {
            Unicode.Scalar(127397 + $0.value).map { String($0) }
        }.joined()
    }

    var body: some View {
        NavigationStack {
            List(airports, id: \.iata) { ap in
                HStack(spacing: 10) {
                    FlagLabel(emoji: flagEmoji(ap.country), size: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ap.name).font(.palatino(.body)).foregroundStyle(.primary)
                        Text(ap.iata).font(.palatino(.caption, weight: .bold)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(ap.count)x")
                        .font(.palatino(.subheadline, weight: .bold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(.systemGray5), in: Capsule())
                }
                .padding(.vertical, 2)
            }
            .listStyle(.plain)
            .navigationTitle("✈️ Aeropuertos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .appColorScheme()
    }
}

// MARK: - Airline stats sheet
struct AirlineStatsSheet: View {
    let airlines: [(name: String, count: Int)]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(airlines, id: \.name) { al in
                HStack {
                    Text(al.name).font(.palatino(.body))
                    Spacer()
                    Text("\(al.count)x")
                        .font(.palatino(.subheadline, weight: .bold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(.systemGray5), in: Capsule())
                }
                .padding(.vertical, 2)
            }
            .listStyle(.plain)
            .navigationTitle("🛫 Aerolíneas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .appColorScheme()
    }
}

// MARK: - Seat stats sheet
struct SeatStatsSheet: View {
    let seats: [(seat: String, count: Int)]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if seats.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "seat.fill")
                            .font(.system(size: 40)).foregroundStyle(.secondary)
                        Text("Aún no hay asientos registrados")
                            .font(.palatino(.subheadline)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(seats, id: \.seat) { s in
                        HStack {
                            Text(s.seat).font(.palatino(.body, weight: .bold))
                            Spacer()
                            Text("\(s.count)x")
                                .font(.palatino(.subheadline, weight: .bold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color(.systemGray5), in: Capsule())
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("💺 Asientos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .appColorScheme()
    }
}

// MARK: - Seat position stats sheet
struct SeatPositionStatsSheet: View {
    let positions: [(position: String, count: Int)]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if positions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.rectangle")
                            .font(.system(size: 40)).foregroundStyle(.secondary)
                        Text("Aún no hay tipos de asiento registrados")
                            .font(.palatino(.subheadline)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(positions, id: \.position) { p in
                        HStack {
                            Text(p.position.capitalized).font(.palatino(.body))
                            Spacer()
                            Text("\(p.count)x")
                                .font(.palatino(.subheadline, weight: .bold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color(.systemGray5), in: Capsule())
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("🪟 Tipo asiento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .appColorScheme()
    }
}

// MARK: - Raskmap Pro
// IDs de producto en App Store Connect.
private let raskmapProLifetimeID = "com.raskmap.pro.lifetime"
private let raskmapProAllIDs     = [raskmapProLifetimeID]

struct SubscriptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isRaskmapPro") private var isRaskmapPro: Bool = false
    @AppStorage("raskmapProPlanID") private var raskmapProPlanID: String = ""
    @AppStorage("raskmapProByCode") private var raskmapProByCode: Bool = false

    @State private var lifetimeProduct: Product? = nil
    @State private var isLoading: Bool = true
    @State private var purchasingID: String? = nil
    @State private var isActivePro: Bool = false
    @State private var errorMessage: String? = nil

    private var isPurchasing: Bool { purchasingID != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {

                    // Hero
                    VStack(spacing: 14) {
                        Text("✈️")
                            .font(.system(size: 64))
                        Text("Raskmap Pro")
                            .font(.palatino(.largeTitle, weight: .bold))
                            .foregroundStyle(.purple)
                        Text("Apoya el desarrollo de Raskmap\ny desbloquea funciones exclusivas")
                            .font(.palatino(.body))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 36)

                    // Beneficios
                    VStack(alignment: .leading, spacing: 18) {
                        proBenefitRow(icon: "map.fill",              text: "Exportación de tu mapa y listas personalizadas")
                        proBenefitRow(icon: "chart.bar.fill",        text: "Estadísticas avanzadas de transportes")
                        proBenefitRow(icon: "trophy.fill",           text: "Sistema de logros")
                        proBenefitRow(icon: "globe.americas.fill",   text: "Ve tu porcentaje del mundo visitado")
                        proBenefitRow(icon: "timer",                 text: "Cuentas atrás y Live Activities")
                        proBenefitRow(icon: "paintpalette.fill",     text: "Personaliza tu mapa con colores")
                        proBenefitRow(icon: "crown.fill",            text: "Insignia Pro")
                        proBenefitRow(icon: "heart.fill",            text: "Apoyas el desarrollo independiente")
                    }
                    .padding(.horizontal, 36)

                    // Estado / botones
                    if isLoading {
                        ProgressView()
                            .padding(.top, 8)
                    } else if isActivePro {
                        VStack(spacing: 16) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.purple)
                            VStack(spacing: 6) {
                                Text("Pro activo")
                                    .font(.palatino(.title3, weight: .bold))
                                    .foregroundStyle(.purple)
                                Text("Pago único · Vitalicio")
                                    .font(.palatino(.subheadline))
                                    .foregroundStyle(.secondary)
                            }
                            Text("¡Gracias por apoyar Raskmap!")
                                .font(.palatino(.body))
                                .foregroundStyle(.secondary)

                        }
                        .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 12) {
                            purchaseButton(
                                product: lifetimeProduct,
                                productID: raskmapProLifetimeID,
                                label: lifetimeProduct.map { "Pago único · \($0.displayPrice)" } ?? "Pago único · 3,99 €",
                                isProminent: true
                            )

                            Button {
                                Task { await restorePurchases() }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Restaurar compras")
                                        .font(.palatino(.body, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.purple.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.purple)
                            }
                            .buttonStyle(.plain)
                            .disabled(isPurchasing)
                            .accessibilityLabel("Restaurar compras anteriores")
                            .accessibilityHint("Verifica con tu Apple ID si ya compraste Raskmap Pro previamente")
                        }
                        .padding(.horizontal, 32)

                        if let error = errorMessage {
                            Text(error)
                                .font(.palatino(.caption))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    }

                    // Legal
                    Text("El pago único desbloquea Pro de forma permanente.")
                        .font(.palatino(.caption2))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 48)
                }
            }
            .navigationTitle("Raskmap Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                        .font(.palatino(.body))
                }
            }
        }
        .appColorScheme()
        .task {
            await loadProducts()
            await checkProStatus()
        }
    }

    @ViewBuilder
    private func purchaseButton(product: Product?, productID: String, label: String, isProminent: Bool) -> some View {
        Button {
            Task { await purchase(productID: productID, product: product) }
        } label: {
            Group {
                if purchasingID == productID {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text(label)
                        .font(.palatino(.body, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                (isPurchasing || product == nil) ? Color.purple.opacity(0.4) : Color.purple,
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing || product == nil)
    }

    @ViewBuilder
    private func proBenefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.purple)
                .frame(width: 22, alignment: .center)
            Text(text)
                .font(.palatino(.body))
                .foregroundStyle(.primary)
        }
    }

    private func loadProducts() async {
        isLoading = true
        do {
            let products = try await Product.products(for: raskmapProAllIDs)
            lifetimeProduct = products.first { $0.id == raskmapProLifetimeID }
            if lifetimeProduct == nil {
                errorMessage = "El producto no está disponible todavía."
            }
        } catch {
            errorMessage = "No se pudieron cargar las opciones. Comprueba tu conexión."
        }
        isLoading = false
    }

    private func checkProStatus() async {
        #if DEBUG
        if isRaskmapPro { isActivePro = true; return }
        #endif
        guard !raskmapProByCode else { isActivePro = true; return }
        var found = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.productID == raskmapProLifetimeID {
                found = true
                break
            }
        }
        isActivePro = found
        isRaskmapPro = found
        raskmapProPlanID = found ? raskmapProLifetimeID : ""
    }

    private func purchase(productID: String, product: Product?) async {
        guard let product else { return }
        purchasingID = productID
        errorMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(_) = verification {
                    await checkProStatus()
                }
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Compra pendiente de aprobación parental."
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Error al procesar el pago. Inténtalo de nuevo."
        }
        purchasingID = nil
    }

    private func restorePurchases() async {
        purchasingID = raskmapProLifetimeID // bloquea UI
        errorMessage = nil
        do {
            try await AppStore.sync()
            await checkProStatus()
            if !isActivePro {
                errorMessage = "No se encontró ninguna compra anterior."
            }
        } catch {
            errorMessage = "No se pudieron restaurar las compras."
        }
        purchasingID = nil
    }
}
