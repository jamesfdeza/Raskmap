//
//  ProfileSheet.swift
//  Raskmap
//
//  Pantalla principal del perfil del usuario. Compuesta por:
//  · Header con avatar pasaporte + username.
//  · Resumen de viajes por año (YearTravelView).
//  · Cards de logros, medallero, transporte, banderas, exportar.
//  · Sub-sheets gestionadas internamente (finalizados, próximos)
//    para evitar conflicto de sheet-sobre-sheet de SwiftUI.
//  · Sección "Lugares por descubrir" con onDiscoveryTap callback.
//
//  La sheet más compleja del proyecto — acceso a multitud de
//  @AppStorage, @Query indirecto vía params, y varios sub-sheets.
//
//  Extraído de ContentView.swift durante Fase D.
//

import SwiftUI
import SwiftData
import MapKit

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
    /// Callback opcional: el usuario tappea una bandera en "Lugares por
    /// descubrir". El parent debe cerrar este sheet y replicar el efecto
    /// de un tap directo en el mapa (centerMap + highlight + country sheet).
    var onDiscoveryTap: ((CountryFeature) -> Void)? = nil
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
                    RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
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
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.section, style: .continuous))
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

                    // ── Lugares por descubrir ──
                    discoverSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)

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
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.section, style: .continuous))
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
                    modelContext.saveOrWarn()
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
                    modelContext.saveOrWarn()
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
                    modelContext.saveOrWarn()
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
                    if country.plannedDate.map({ trip.dateFrom < $0 }) ?? true {
                        country.plannedDate = trip.dateFrom
                        country.plannedDateTo = trip.dateTo
                        country.transport = trip.transport
                        country.plannedTitle = trip.title
                    }
                    modelContext.saveOrWarn()
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
                    modelContext.saveOrWarn()
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
                    modelContext.saveOrWarn()
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
                            if country.plannedDate.map({ newFrom < $0 }) ?? true {
                                country.plannedDate = newFrom
                                country.plannedDateTo = newTo
                                country.transport = src.transport
                                country.plannedTitle = src.title
                            }
                        }
                        _ = cal // suppress unused warning if calendar isn't used elsewhere
                    }
                    modelContext.saveOrWarn()
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
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: Radius.sheet))
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

    /// Sugerencias de países sin visitar, **1 por región** (máx 9 cards):
    /// Europa, Asia, África, Medio Oriente, Oceanía, Norteamérica, Caribe,
    /// Sudamérica, Centroamérica. Siempre se evalúan TODAS las regiones,
    /// incluso aquellas sin visitas previas (el usuario quiere descubrir
    /// Oceanía aunque no haya estado allí nunca).
    ///
    /// Para cada región se elige el unvisited cuyo **centro del bounding box
    /// está más cerca de cualquier país visitado** (priorización por
    /// proximidad geográfica → fronterizos a tu cluster). Fallback alfabético
    /// por ISO cuando no hay visitas o todos quedan a igual distancia.
    ///
    /// Garantías:
    /// · **No repeticiones** — si un país pertenece a varias regiones (p.ej.
    ///   ISR ∈ Asia ∩ Medio Oriente) solo la primera región que lo elija
    ///   se lo queda; el resto buscan otra opción de su pool.
    /// · **Sanctioned ISOs excluidos** — países que no queremos recomendar
    ///   por motivos políticos/éticos (lista en `sanctionedDiscoveryISOs`).
    private static let sanctionedDiscoveryISOs: Set<String> = ["ISR"]

    private var discoveryCandidates: [CountryFeature] {
        let visited = Set(visitedIsoCodes)
        let regions: [Set<String>] = [
            AchievementKind.visitedEuropa.regionIsoCodes,
            AchievementKind.visitedAsia.regionIsoCodes,
            AchievementKind.visitedAfrica.regionIsoCodes,
            AchievementKind.visitedMedioOriente.regionIsoCodes,
            AchievementKind.visitedOceania.regionIsoCodes,
            AchievementKind.visitedNortamerica.regionIsoCodes,
            AchievementKind.visitedCaribe.regionIsoCodes,
            AchievementKind.visitedSudamerica.regionIsoCodes,
            AchievementKind.visitedCentroamerica.regionIsoCodes
        ]
        // Pre-indexar centros (bbox midpoint) por ISO para O(1) lookup.
        var centerByIso: [String: MKMapPoint] = [:]
        centerByIso.reserveCapacity(allFeatures.count)
        for f in allFeatures {
            let r = f.boundingMapRect
            centerByIso[f.isoCode] = MKMapPoint(x: r.midX, y: r.midY)
        }
        let visitedCenters: [MKMapPoint] = visited.compactMap { centerByIso[$0] }

        func minDistance(toAnyVisitedFrom p: MKMapPoint) -> Double {
            guard !visitedCenters.isEmpty else { return .greatestFiniteMagnitude }
            var best = Double.greatestFiniteMagnitude
            for v in visitedCenters {
                let d = p.distance(to: v)
                if d < best { best = d }
            }
            return best
        }

        var picked: [String] = []
        var pickedSet = Set<String>()
        let sanctioned = Self.sanctionedDiscoveryISOs
        for region in regions {
            // Pool por región: ISOs - visitados - sancionados - ya elegidos.
            let pool = region
                .subtracting(visited)
                .subtracting(sanctioned)
                .subtracting(pickedSet)
                .filter { countingMode.counts($0) }
            guard !pool.isEmpty else { continue }
            let best = pool.min { a, b in
                let da = centerByIso[a].map { minDistance(toAnyVisitedFrom: $0) } ?? .greatestFiniteMagnitude
                let db = centerByIso[b].map { minDistance(toAnyVisitedFrom: $0) } ?? .greatestFiniteMagnitude
                if da != db { return da < db }
                return a < b  // tie-breaker estable por ISO
            }
            if let pick = best {
                picked.append(pick)
                pickedSet.insert(pick)
            }
        }
        return picked.compactMap { iso in allFeatures.first(where: { $0.isoCode == iso }) }
    }

    @ViewBuilder
    private var discoverSection: some View {
        let candidates = discoveryCandidates
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.caption).foregroundStyle(.purple)
                    Text("Lugares por descubrir")
                        .font(.custom("Satoshi-Bold", size: 13))
                        .tracking(0.6)
                        .foregroundStyle(.primary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(candidates, id: \.isoCode) { feature in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onDiscoveryTap?(feature)
                            } label: {
                                VStack(spacing: 6) {
                                    FlagLabel(emoji: feature.flagEmoji ?? "🌐", size: 32)
                                    Text(feature.localizedName)
                                        .font(.palatino(.caption, weight: .bold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                        .frame(maxWidth: 90)
                                        .foregroundStyle(.primary)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 12)
                                .frame(width: 110)
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.card))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func refreshPastTripsCache() {
        let today = Calendar.current.startOfDay(for: Date())
        cachedPastTrips = trips.filter { Calendar.current.startOfDay(for: $0.dateFrom) <= today }
    }
}
