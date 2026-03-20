//
//  ContentView.swift
//  Raskmap
//

import SwiftUI
import SwiftData
import Combine
import MapKit
import Photos
import CoreLocation

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
    @State private var locationIsoCode: String? = nil
    @State private var showVisitedToast: Bool = false
    @State private var visitedToastMessage: String = ""
    @State private var pendingAddTripCountry: Country? = nil
    @State private var statusBeforeVisit: CountryStatus = .none
    @State private var refreshTrigger: Bool = false
    @State private var shouldOpenAddTrip: Bool = false
    @State private var lastModifiedCountry: Country? = nil
    @State private var editingFutureTrip: Trip? = nil
    @State private var bannerTappedCountry: Country? = nil
    @StateObject private var locationManager = LocationManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingDateStatus: CountryStatus = .none
    @State private var deferredDateCountry: Country? = nil
    @State private var searchText: String = ""
    @StateObject private var mapStore = MapStore()
    @EnvironmentObject private var colorTheme: ColorThemeManager
    @AppStorage("username") private var username: String = ""
    @State private var showOnboarding: Bool = false
    @State private var usernameInput: String = ""
    @State private var isLoadingFeatures: Bool = true
    @State private var pendingShowSheet: Bool = false
    @State private var showProfile: Bool = false
    @AppStorage("countingMode") private var countingModeRaw: String = CountingMode.all.rawValue
    @AppStorage("menuPosition")    private var menuPositionRaw: String = "bottom"
    @AppStorage("showLived")      private var showLived: Bool = true
    @AppStorage("showBucketList") private var showBucketList: Bool = true
    @AppStorage("showCountdown")  private var showCountdown: Bool = true
    @AppStorage("topGold")   private var topGold:   String = "[]"
    @AppStorage("topSilver") private var topSilver: String = "[]"
    @AppStorage("topBronze") private var topBronze: String = "[]"
    @AppStorage("topTable")  private var topTable:  String = "{}"
    @State private var highlightedIsoCode: String? = nil
    @State private var profileImage: UIImage? = {
        guard let data = UserDefaults.standard.data(forKey: "profileImageData") else { return nil }
        return UIImage(data: data)
    }()

    private var menuPositionIsTop: Bool { menuPositionRaw == "top" }

    private var countingMode: CountingMode { CountingMode(rawValue: countingModeRaw) ?? .all }

    // Conteos totales reales (para listas)
    private var visitedCountAll: Int { countries.filter { $0.status == .visited }.count }
    private var wantCountAll: Int    { countries.filter { $0.status == .wantToVisit }.count }
    private var livedCountAll: Int      { countries.filter { $0.status == .lived }.count }
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

    // All "próximos": wantToVisit + visited with future trip
    private var allProximos: [Country] {
        let wantToVisit = countries.filter { $0.status == .wantToVisit }
        return (wantToVisit + visitedWithFutureTrip)
    }

    // Extended próximos count for badge
    private var proxCount: Int {
        let base = countries.filter { $0.status == .wantToVisit && countingMode.counts($0.isoCode) }.count
        let extra = visitedWithFutureTrip.filter { countingMode.counts($0.isoCode) }.count
        return base + extra
    }
    private var livedCount: Int {
        countingMode == .all ? livedCountAll :
        countries.filter { $0.status == .lived && countingMode.counts($0.isoCode) }.count
    }
    private var bucketListCount: Int {
        countingMode == .all ? bucketListCountAll :
        countries.filter { $0.status == .bucketList && countingMode.counts($0.isoCode) }.count
    }

    private var sortedFeatures: [CountryFeature] {
        features.sorted { $0.localizedName < $1.localizedName }
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
        return grouped.keys.sorted().map { letter in
            (letter: letter, features: grouped[letter]!.sorted { $0.localizedName < $1.localizedName })
        }
    }


    @ViewBuilder
    private func badgesRow() -> some View {
        HStack(spacing: 8) {
            StatBadge(value: visitedCount + (showLived ? livedCount : 0), label: "Visitados", color: colorTheme.visitedColor)
                .onTapGesture { showAllCountries = true }
            if showBucketList {
                StatBadge(value: bucketListCount, label: "Quiero", color: colorTheme.bucketListColor)
                    .onTapGesture { statusListFilter = .bucketList }
            }
            StatBadge(value: proxCount, label: "Próximos", color: colorTheme.wantToVisitColor)
                .onTapGesture { statusListFilter = .wantToVisit }
            if showLived {
                StatBadge(value: livedCount, label: "Vivido", color: colorTheme.livedColor)
                    .onTapGesture { statusListFilter = .lived }
            }
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

    private var nextProximosBanner: (days: Int, flag: String, name: String, isoCode: String)? {
        let today = Calendar.current.startOfDay(for: Date())
        var entries: [(days: Int, flag: String, name: String, isoCode: String, date: Date)] = []
        // wantToVisit countries
        for country in countries where country.status == .wantToVisit {
            guard let date = country.plannedDate else { continue }
            let d = Calendar.current.startOfDay(for: date)
            guard d > today else { continue }
            let days = Calendar.current.dateComponents([.day], from: today, to: d).day ?? 0
            let flag = features.first(where: { $0.isoCode == country.isoCode })?.flagEmoji ?? "🌐"
            let name = features.first(where: { $0.isoCode == country.isoCode })?.localizedName ?? country.name
            entries.append((days, flag, name, country.isoCode, d))
        }
        // visited countries with future trips
        for trip in trips where trip.isoCode != "" {
            let d = Calendar.current.startOfDay(for: trip.dateFrom)
            guard d >= today else { continue }
            guard countries.first(where: { $0.isoCode == trip.isoCode })?.status == .visited else { continue }
            let days = Calendar.current.dateComponents([.day], from: today, to: d).day ?? 0
            guard days > 0 else { continue }  // skip today's auto-trips
            let flag = features.first(where: { $0.isoCode == trip.isoCode })?.flagEmoji ?? "🌐"
            let name = features.first(where: { $0.isoCode == trip.isoCode })?.localizedName ?? trip.isoCode
            entries.append((days, flag, name, trip.isoCode, d))
        }
        guard let next = entries.sorted(by: { $0.date < $1.date }).first else { return nil }
        return (next.days, next.flag, next.name, next.isoCode)
    }

    @ViewBuilder
    private func menuOverlay() -> some View {
        if menuPositionIsTop {
            // ── ARRIBA ──
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button { showProfile = true } label: {
                        HStack(spacing: 8) {
                            ProfileAvatarView(image: profileImage, size: 34)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Raskmap")
                                    .font(.palatino(.headline, weight: .bold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !username.isEmpty {
                                    Text("@ \(username)")
                                        .font(.palatino(.caption))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                    badgesRow().fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 6)
                .padding(.top, 8)

                counterRow(alignment: .top)
                    .padding(.top, 6)
            }
        } else {
            // ── ABAJO ──
            VStack(spacing: 6) {
                counterRow(alignment: .bottom)
                HStack(spacing: 8) {
                    Button { showProfile = true } label: {
                        HStack(spacing: 8) {
                            ProfileAvatarView(image: profileImage, size: 34)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Raskmap")
                                    .font(.palatino(.headline, weight: .bold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !username.isEmpty {
                                    Text("@ \(username)")
                                        .font(.palatino(.caption))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                    badgesRow().fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 6)
                .padding(.bottom, 32)
            }
        }
    }

    var body: some View {
        mapWithSheets()
            .onChange(of: locationManager.currentLocation) { old, location in
                guard let location else { locationIsoCode = nil; return }
                // Immediate on first fix, debounced after
                checkLocationCountry(location, immediate: old == nil)
            }
            .onChange(of: profileImage) {
                if let img = profileImage, let data = img.jpegData(compressionQuality: 0.8) {
                    UserDefaults.standard.set(data, forKey: "profileImageData")
                }
            }
            .task {
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
                        // Detect country once features are loaded
                        if let loc = self.locationManager.currentLocation {
                            self.checkLocationCountry(loc, immediate: true)
                        }
                    }
                } else {
                    isLoadingFeatures = false
                    onContentReady?()
                    // Detect country with existing features
                    if let loc = locationManager.currentLocation {
                        checkLocationCountry(loc, immediate: true)
                    }
                }
                if username.isEmpty { showOnboarding = true }

                // Request location
                locationManager.requestAndStart()

                // Auto-marcar como visitado los Próximos cuya fecha ya pasó
                let today = Calendar.current.startOfDay(for: Date())
                var changed = false
                for country in countries {
                    guard country.status == .wantToVisit,
                          let planned = country.plannedDate else { continue }
                    let plannedDay = Calendar.current.startOfDay(for: planned)
                    if plannedDay < today {
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
                }
                if changed { try? modelContext.save() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                let today = Calendar.current.startOfDay(for: Date())
                var changed = false
                for country in countries {
                    guard country.status == .wantToVisit,
                          let planned = country.plannedDate else { continue }
                    let plannedDay = Calendar.current.startOfDay(for: planned)
                    if plannedDay < today {
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
                }
                if changed { try? modelContext.save() }
            }
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
                    onStatusChange: { newStatus in
                        updateCountryStatus(country: country, newStatus: newStatus)
                        selectedCountry = nil
                    },
                    onDismiss: {
                        highlightedIsoCode = nil
                        selectedCountry = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            recheckLocationIfNeeded()
                        }
                    },
                    showLived: showLived,
                    showBucketList: showBucketList
                )
                .presentationDetents([.fraction(0.40)])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showSearch, onDismiss: {
                if pendingShowSheet { pendingShowSheet = false; showSheet = true }
            }) { searchSheet() }
            .sheet(isPresented: $showOnboarding) { onboardingSheet() }
            .sheet(isPresented: $showAllCountries) {
                let visitedCodes: Set<String> = Set(countries.compactMap { country -> String? in
                    if country.status == .visited { return country.isoCode }
                    if showLived && country.status == .lived { return country.isoCode }
                    return nil
                })
                AllCountriesSheet(features: features, mode: countingMode, visitedIsoCodes: visitedCodes, countries: countries, trips: trips)
            }
            .sheet(item: $statusListFilter) { filter in
                StatusListSheet(
                    filter: filter,
                    countries: filter == .wantToVisit ? allProximos : countries,
                    features: features,
                    trips: trips,
                    onRemove: { country in
                        if country.status == .visited {
                            // Remove future trips for this country
                            let today = Calendar.current.startOfDay(for: Date())
                            for trip in trips where trip.isoCode == country.isoCode {
                                if Calendar.current.startOfDay(for: trip.dateFrom) > today {
                                    modelContext.delete(trip)
                                }
                            }
                        } else {
                            country.status = .none; country.plannedDate = nil
                        }
                        try? modelContext.save()
                    },
                    onSetDate: filter == .wantToVisit ? { country, trip in
                        if let trip = trip {
                            // Close StatusListSheet first, then open EditTripSheet
                            statusListFilter = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                editingFutureTrip = trip
                            }
                        } else {
                            deferredDateCountry = country
                            statusListFilter = nil
                        }
                    } : nil
                )
            }
            .sheet(item: $editingFutureTrip) { trip in
                EditTripSheet(trip: trip)
            }
            .sheet(item: $bannerTappedCountry) { country in
                CountryTripsSheet(
                    country: country,
                    trips: trips.filter { $0.isoCode == country.isoCode },
                    displayName: localizedName(for: country),
                    flagEmoji: flagEmoji(for: country) ?? "🌐"
                )
            }
            .sheet(item: $pendingDateCountry) { country in datePicker(for: country) }
            .sheet(item: $pendingAddTripCountry) { country in
                AddTripSheet(
                    isoCode: country.isoCode,
                    displayName: localizedName(for: country),
                    flagEmoji: flagEmoji(for: country) ?? "🌐",
                    onSave: { trip in
                        modelContext.insert(trip)
                        try? modelContext.save()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            refreshTrigger.toggle()
                        }
                        // Only show toast if we actually changed status to visited
                        if statusBeforeVisit != .visited {
                            let name = localizedName(for: country)
                            visitedToastMessage = "✅ \(name) visitado"
                            showVisitedToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { showVisitedToast = false }
                        }
                    },
                    onCancel: {
                        // Only revert if we changed the status (not for visited->addTrip)
                        if statusBeforeVisit != .visited {
                            country.status = statusBeforeVisit
                            try? modelContext.save()
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
    }

    @ViewBuilder
    private func mapCore() -> some View {
        ZStack(alignment: menuPositionIsTop ? .top : .bottom) {
            RaskMapView(
                countries: countries, features: features,
                onCountryTapped: { handleCountryTap($0) },
                highlightedIsoCode: highlightedIsoCode,
                showLived: showLived, showBucketList: showBucketList,
                locationIsoCode: locationIsoCode,
                onReady: { mapStore.centerOnCountry = $0 }
            )
            .ignoresSafeArea()
            menuOverlay()

            // Próximos countdown banner — opposite side to menu
            if showCountdown, let banner = nextProximosBanner {
                VStack {
                    if menuPositionIsTop { Spacer() }
                    let dayWord = banner.days == 1 ? "día" : "días"
                    let quedaWord = banner.days == 1 ? "Queda" : "Quedan"
                    let bannerText = "\(quedaWord) \(banner.days) \(dayWord) para \(banner.flag) \(banner.name)"
                    Button {
                        if let country = countries.first(where: { $0.isoCode == banner.isoCode }) {
                            bannerTappedCountry = country
                        }
                    } label: {
                        Text(bannerText)
                            .font(.palatino(.footnote, weight: .bold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, menuPositionIsTop ? 16 : 0)
                    .padding(.top, menuPositionIsTop ? 0 : 16)
                    if !menuPositionIsTop { Spacer() }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }

            // Visited toast
            if showVisitedToast {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white)
                            .font(.title3)
                        Text(visitedToastMessage)
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.bottom, menuPositionIsTop ? 40 : 120)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(duration: 0.3), value: showVisitedToast)
            }
        }
        // MARK: - Sheet país
        .sheet(item: $selectedCountry, onDismiss: {
            highlightedIsoCode = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                recheckLocationIfNeeded()
            }
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
                onStatusChange: { newStatus in
                    updateCountryStatus(country: country, newStatus: newStatus)
                    selectedCountry = nil
                },
                onDismiss: {
                    highlightedIsoCode = nil
                    selectedCountry = nil
                },
                showLived: showLived,
                showBucketList: showBucketList
            )
            .presentationDetents([.fraction(0.40)])
            .presentationDragIndicator(.visible)
        }


    }

    @ViewBuilder
    private func searchSheet() -> some View {
        NavigationStack {
            List {
                ForEach(groupedSearchResults, id: \.letter) { section in
                    Section(header: searchText.isEmpty ? Text(section.letter) : nil) {
                        ForEach(section.features, id: \.isoCode) { feature in
                            HStack {
                                Text(feature.flagEmoji ?? "🌐")
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
                    }
                }
            }
            .listStyle(.plain)
            .scrollIndicators(.visible)
            .searchable(text: $searchText, prompt: "Buscar país...")
            .navigationTitle("Buscar país")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { showSearch = false; searchText = "" }
                }
            }
        }
    }

    @ViewBuilder
    private func onboardingSheet() -> some View {
        VStack(spacing: 24) {
            Spacer()
            Text("👋 Bienvenido a Raskmap").font(.palatino(.title2, weight: .bold))
            Text("¿Cómo quieres que te llamemos?").font(.palatino(.subheadline)).foregroundStyle(.secondary)
            TextField("Tu nombre de usuario", text: $usernameInput)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 32)
                .onChange(of: usernameInput) {
                    usernameInput = String(usernameInput.filter { $0.isLetter || $0.isNumber }.prefix(10))
                }
            Button(action: {
                let clean = String(usernameInput.filter { $0.isLetter || $0.isNumber }.prefix(10))
                if !clean.isEmpty { username = clean; showOnboarding = false }
            }) {
                Text("Empezar").fontWeight(.semibold)
                    .frame(maxWidth: .infinity).padding()
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .interactiveDismissDisabled(true)
    }

    @ViewBuilder
    private func datePicker(for country: Country) -> some View {
        let editing = country.plannedDate != nil
        PlannedDatePickerSheet(
            countryName: localizedName(for: country),
            flagEmoji: flagEmoji(for: country) ?? "🌐",
            existingDate: country.plannedDate,
            existingDateTo: country.plannedDateTo,
            existingTransport: country.transport,
            existingTitle: country.plannedTitle,
            isEditing: editing,
            onSave: { dateFrom, dateTo, transport, title in
                country.status = .wantToVisit
                country.plannedDate = dateFrom
                country.plannedDateTo = dateTo
                country.transport = transport
                country.plannedTitle = title?.trimmingCharacters(in: .whitespaces)
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
    private func profileContent() -> some View {
        let visitedFlags: Set<String> = Set(
            countries.filter { $0.status == .visited || $0.status == .lived }
                .compactMap { country in features.first(where: { $0.isoCode == country.isoCode })?.flagEmoji }
        )
        ProfileSheet(
            username: $username, profileImage: $profileImage,
            countingModeRaw: $countingModeRaw, menuPositionRaw: $menuPositionRaw,
            showLived: $showLived, showBucketList: $showBucketList,
            showCountdown: $showCountdown,
            onClearStatus: { status in
                for country in countries where country.status == status { country.status = .none }
                try? modelContext.save()
            },
            topGold: $topGold, topSilver: $topSilver, topBronze: $topBronze, topTable: $topTable,
            visitedFlags: visitedFlags,
            allFeatures: features,
            visitedIsoCodes: Set(countries.filter { $0.status == .visited || $0.status == .lived }.map { $0.isoCode }),
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
            if hasFutureTrip { return } // visual translucency handled elsewhere
            return
        }
        switch country.status {
        case .none, .wantToVisit:
            country.status = .visited
            country.plannedDate = nil
            country.plannedDateTo = nil
            country.transport = nil
            try? modelContext.save()
        case .bucketList:
            let hasFutureTrip = trips.contains { $0.isoCode == isoCode && Calendar.current.startOfDay(for: $0.dateFrom) > today }
            if hasFutureTrip {
                // Has future trip registered — mark as wantToVisit, keep trip
                country.status = .wantToVisit
            } else {
                // No future trip — mark visited, create auto trip for today
                country.status = .visited
                let df = DateFormatter(); df.dateStyle = .long; df.locale = Locale(identifier: "es_ES")
                let autoTrip = Trip(isoCode: isoCode,
                                    title: "Visita en el día \(df.string(from: Date()))",
                                    dateFrom: today, dateTo: nil, transport: "✈️")
                modelContext.insert(autoTrip)
            }
            country.plannedDate = nil
            country.plannedDateTo = nil
            country.transport = nil
            try? modelContext.save()
        case .lived:
            if !showLived {
                country.status = .visited
                try? modelContext.save()
            }
        case .visited:
            break
        }
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

    private func localizedName(for country: Country) -> String {
        features.first(where: { $0.isoCode == country.isoCode })?.localizedName ?? country.name
    }

    private func flagEmoji(for country: Country) -> String? {
        features.first(where: { $0.isoCode == country.isoCode })?.flagEmoji
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
            if newStatus == .none {
                country.plannedDate = nil
                country.plannedDateTo = nil
                country.transport = nil
                country.visitCount = 0
            }

            // Remove future trips only when explicitly unmarking (going to .none)
            if newStatus == .none {
                let today = Calendar.current.startOfDay(for: Date())
                for trip in trips where trip.isoCode == country.isoCode {
                    if Calendar.current.startOfDay(for: trip.dateFrom) >= today {
                        modelContext.delete(trip)
                    }
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
        VStack(spacing: 1) {
            Text("\(value)")
                .font(.palatino(.title3, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.palatino(.caption2))
                .foregroundStyle(.secondary)
        }
        .frame(width: 56)
        .padding(.vertical, 6)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(0.6))
                .frame(width: 16, height: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(color, lineWidth: 1)
                )
            Text(label)
                .font(.palatino(.caption2))
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
    let onStatusChange: (CountryStatus) -> Void
    let onDismiss: () -> Void
    var showLived: Bool = true
    var showBucketList: Bool = true

    @EnvironmentObject private var colorTheme: ColorThemeManager
    @State private var showRemoveConfirm = false

    var body: some View {
        VStack(spacing: 20) {
            Group {
                if let flag = flagEmoji {
                    Text("\(flag) \(displayName) \(flag)")
                } else {
                    Text(displayName)
                }
            }
            .font(.palatino(.title2, weight: .bold))
            .padding(.top, 72)

            VStack(spacing: 10) {
                ActionButton(
                    label: "✅ Visitados",
                    color: colorTheme.visitedColor,
                    isSelected: country.status == .visited,
                    action: {
                        if country.status == .visited { showRemoveConfirm = true }
                        else { onStatusChange(.visited) }
                    }
                )
                ActionButton(
                    label: "🔜 Próximo",
                    color: colorTheme.wantToVisitColor,
                    isSelected: country.status == .wantToVisit,
                    action: {
                        if country.status == .wantToVisit { showRemoveConfirm = true }
                        else { onStatusChange(.wantToVisit) }
                    }
                )
                if showBucketList {
                    ActionButton(
                        label: "📝 Quiero",
                        color: colorTheme.bucketListColor,
                        isSelected: country.status == .bucketList,
                        action: {
                            if country.status == .bucketList { showRemoveConfirm = true }
                            else { onStatusChange(.bucketList) }
                        }
                    )
                }
                if showLived {
                    ActionButton(
                        label: "🏠 He vivido aquí",
                        color: colorTheme.livedColor,
                        isSelected: country.status == .lived,
                        action: {
                            if country.status == .lived { showRemoveConfirm = true }
                            else { onStatusChange(.lived) }
                        }
                    )
                }
                Divider()
                    .padding(.top, 14)
                Button("✕  Cerrar") {
                    onDismiss()
                }
                .font(.palatino(.subheadline))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .confirmationDialog(
            "¿Eliminar de la lista?",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
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
            HStack {
                Text(label)
                    .fontWeight(.medium)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
            .padding()
            .background(
                isSelected ? color.opacity(0.15) : Color(.systemGray6),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? color : .clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? color : .primary)
        }
    }
}

// MARK: - Sheet lista de países por estado
struct StatusListSheet: View {
    let filter: CountryStatus
    let countries: [Country]
    let features: [CountryFeature]
    var trips: [Trip] = []
    let onRemove: (Country) -> Void
    var onSetDate: ((Country, Trip?) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var countryToRemove: Country? = nil

    private var filtered: [Country] {
        // For wantToVisit, countries already contains allProximos (visited+future included)
        if filter == .wantToVisit { return countries }
        return countries.filter { $0.status == filter }
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

    // Para Próximos: ordenar por fecha (sin fecha al final), luego alfabético
    private var sortedFiltered: [Country] {
        if filter == .wantToVisit {
            return filtered.sorted {
                switch (proximoDateFrom(for: $0), proximoDateFrom(for: $1)) {
                case let (a?, b?): return a < b
                case (_?, nil):    return true
                case (nil, _?):    return false
                default:           return displayName(for: $0) < displayName(for: $1)
                }
            }
        }
        return filtered.sorted { displayName(for: $0) < displayName(for: $1) }
    }

    // Agrupados por primera letra (solo para no-Próximos) o por mes/año (Próximos con fecha)
    private var grouped: [(letter: String, items: [Country])] {
        if filter == .wantToVisit {
            // Para Próximos: agrupar por mes/año o "Sin fecha"
            var result: [(letter: String, items: [Country])] = []
            for country in sortedFiltered {
                let key: String
                if let date = proximoDateFrom(for: country) {
                    let df = DateFormatter()
                    df.dateFormat = "MMMM yyyy"
                    df.locale = Locale(identifier: "es_ES")
                    key = df.string(from: date).capitalized
                } else {
                    key = "Sin fecha"
                }
                if let idx = result.firstIndex(where: { $0.letter == key }) {
                    result[idx].items.append(country)
                } else {
                    result.append((letter: key, items: [country]))
                }
            }
            return result
        }
        let sorted = filtered.sorted { displayName(for: $0) < displayName(for: $1) }
        var result: [(letter: String, items: [Country])] = []
        for country in sorted {
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
                if filtered.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Text("Ningún país marcado como")
                            .font(.palatino(.subheadline))
                            .foregroundStyle(.secondary)
                        Text(filter.label)
                            .font(.palatino(.title3, weight: .bold))
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(grouped, id: \.letter) { section in
                            Section(header: Text(section.letter).font(.palatino(.caption, weight: .bold))) {
                                ForEach(section.items, id: \.isoCode) { country in
                                    HStack {
                                        Text(flagEmoji(for: country))
                                        VStack(alignment: .leading, spacing: 2) {
                                            if filter == .wantToVisit {
                                                let tripTitle: String? = country.status == .wantToVisit
                                                    ? country.plannedTitle
                                                    : futureTrip(for: country)?.title
                                                if let title = tripTitle, !title.isEmpty {
                                                    HStack(spacing: 6) {
                                                        Text(title).font(.palatino(.body, weight: .bold))
                                                        Text("|").foregroundStyle(.secondary)
                                                        Text(displayName(for: country)).font(.palatino(.body)).foregroundStyle(.secondary)
                                                    }
                                                } else {
                                                    Text(displayName(for: country)).font(.palatino(.body))
                                                }
                                                HStack(spacing: 4) {
                                                    if let t = proximoTransport(for: country) { Text(t).font(.caption) }
                                                    if let from = proximoDateFrom(for: country) {
                                                        Text(Self.dateFormatter.string(from: from))
                                                            .font(.palatino(.caption)).foregroundStyle(.secondary)
                                                        if let to = proximoDateTo(for: country) {
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
                                            } else {
                                                Text(displayName(for: country)).font(.palatino(.body))
                                            }
                                        }
                                        Spacer()
                                        if filter == .wantToVisit, let onSetDate {
                                            Button {
                                                onSetDate(country, futureTrip(for: country))
                                            } label: {
                                                Image(systemName: "calendar")
                                                    .foregroundStyle(.blue)
                                                    .font(.body)
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.trailing, 8)
                                        }
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        // Cierra la sheet asignando nil al binding externo
                        // Se hace pasando un @Environment dismiss
                        dismiss()
                    }
                    .font(.palatino(.body))
                }
            }
        }
        .confirmationDialog(
            "¿Eliminar de la lista?",
            isPresented: Binding(
                get: { countryToRemove != nil },
                set: { if !$0 { countryToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
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
    }
}

// MARK: - Avatar pequeño para el header
struct ProfileAvatarView: View {
    let image: UIImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color(.systemGray4), lineWidth: 1))
    }
}

// MARK: - Pantalla de perfil
struct ProfileSheet: View {
    @Binding var username: String
    @Binding var profileImage: UIImage?
    @Binding var countingModeRaw: String
    @Binding var menuPositionRaw: String
    @Binding var showLived: Bool
    @Binding var showBucketList: Bool
    @Binding var showCountdown: Bool
    var onClearStatus: (CountryStatus) -> Void = { _ in }
    @Binding var topGold: String
    @Binding var topSilver: String
    @Binding var topBronze: String
    @Binding var topTable: String
    let visitedFlags: Set<String>
    let allFeatures: [CountryFeature]
    let visitedIsoCodes: Set<String>
    let countries: [Country]
    let trips: [Trip]

    @EnvironmentObject private var colorTheme: ColorThemeManager
    @Environment(\.dismiss) private var dismiss
    @State private var usernameInput: String = ""
    @State private var showImagePicker: Bool = false
    @State private var usernameError: String? = nil
    @State private var showSavedToast: Bool = false
    @State private var showCountingToast: Bool = false
    @State private var showResetToast: Bool = false
    @State private var editingMedal: MedalSlot? = nil
    @State private var editingSpot: TopSpot? = nil
    @State private var showSettings: Bool = false
    @State private var showMapExport: Bool = false

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

    private func tableFlag(region: TopRegion, medal: MedalSlot) -> String? {
        tableDict()[region.rawValue + "_" + medal.rawValue]
    }

    private func setTableFlag(_ emoji: String?, region: TopRegion, medal: MedalSlot) {
        var dict = tableDict()
        let key = region.rawValue + "_" + medal.rawValue
        if let emoji { dict[key] = emoji } else { dict.removeValue(forKey: key) }
        let data = (try? JSONEncoder().encode(dict)) ?? Data()
        topTable = String(data: data, encoding: .utf8) ?? "{}"
    }

    private func tableDict() -> [String: String] {
        guard let data = topTable.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    private func allUsedTableFlags() -> Set<String> {
        Set(tableDict().values)
    }

    private func visitedFeaturesForRegion(_ region: TopRegion) -> [CountryFeature] {
        allFeatures
            .filter { visitedIsoCodes.contains($0.isoCode) && region.isoCodes.contains($0.isoCode) }
            .sorted { $0.localizedName < $1.localizedName }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // ── Avatar centrado ──
                    Button { showImagePicker = true } label: {
                        ZStack(alignment: .bottomTrailing) {
                            ProfileAvatarView(image: profileImage, size: 100)
                            Image(systemName: "pencil.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                                .background(Color(.systemBackground), in: Circle())
                        }
                    }
                    .padding(.top, 20)

                    // ── Nombre de usuario inline ──
                    UsernameEditView(username: $username)

                    Divider().padding(.horizontal, 24)

                    // ── Años + Finalizados/Próximos ──
                    YearTravelView(
                        countries: countries,
                        features: allFeatures,
                        trips: trips
                    )

                    Divider().padding(.horizontal, 24)
                    // ── Mi top — tabla región × medalla ──
                    Text("Medallero")
                        .font(.palatino(.title2, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, -20)
                    VStack(spacing: 8) {
                        VStack(spacing: 0) {
                            // Cabecera medallas
                            HStack(spacing: 0) {
                                Text("")
                                    .frame(width: 88)
                                ForEach([MedalSlot.gold, .silver, .bronze], id: \.id) { medal in
                                    Text(medal.emoji)
                                        .font(.title2)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .padding(.vertical, 8)

                            Divider()

                            ForEach(TopRegion.allCases) { region in
                                VStack(spacing: 0) {
                                    HStack(spacing: 0) {
                                        Text(region.rawValue)
                                            .font(.palatino(.caption, weight: .bold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 88, alignment: .leading)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.6)
                                        ForEach([MedalSlot.gold, .silver, .bronze], id: \.id) { medal in
                                            let emoji = tableFlag(region: region, medal: medal)
                                            Button {
                                                editingSpot = TopSpot(region: region, medal: medal)
                                            } label: {
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .fill(Color(.systemGray5))
                                                        .frame(width: 52, height: 52)
                                                    if let emoji {
                                                        Text(emoji)
                                                            .font(.system(size: 34))
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
                                    if region != TopRegion.allCases.last {
                                        Divider().padding(.leading, 88)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal, 12)
                    }

                    Spacer(minLength: 32)
                }
            }
            .navigationTitle("Perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                        .font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showMapExport = true } label: {
                        Image(systemName: "chart.bar.xaxis.ascending")
                    }
                }
            }
            .onAppear { usernameInput = username }
            .overlay {
                if showSavedToast {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white)
                        Text("Nombre actualizado")
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showSavedToast)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(image: $profileImage)
        }
        .sheet(item: $editingSpot) { spot in
            TableFlagPickerSheet(
                spot: spot,
                features: visitedFeaturesForRegion(spot.region),
                currentEmoji: tableFlag(region: spot.region, medal: spot.medal),
                usedEmojis: allUsedTableFlags(),
                onSelect: { emoji in
                    setTableFlag(emoji, region: spot.region, medal: spot.medal)
                },
                onClear: {
                    setTableFlag(nil, region: spot.region, medal: spot.medal)
                }
            )
        }
        .sheet(isPresented: $showMapExport) {
            MapExportSheet(
                visitedCountries: countries.filter { $0.status == .visited || $0.status == .lived },
                features: allFeatures,
                counter: "\(countries.filter { $0.status == .visited || $0.status == .lived }.count)/\(CountingMode(rawValue: countingModeRaw)?.denominator ?? 244)",
                visitedColor: colorTheme.visitedColor,
                countingModeRaw: countingModeRaw,
                trips: trips
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                countingModeRaw: $countingModeRaw,
                menuPositionRaw: $menuPositionRaw,
                showLived: $showLived,
                showBucketList: $showBucketList,
                showCountdown: $showCountdown,
                onClearStatus: onClearStatus
            )
            .environmentObject(colorTheme)
        }
    }
}

// MARK: - Pantalla de ajustes
struct SettingsSheet: View {
    @Binding var countingModeRaw: String
    @Binding var menuPositionRaw: String
    @Binding var showLived: Bool
    @Binding var showBucketList: Bool
    @Binding var showCountdown: Bool
    var onClearStatus: (CountryStatus) -> Void = { _ in }

    @State private var pendingClear: CountryStatus? = nil
    @State private var isConfirming: Bool = false

    @EnvironmentObject private var colorTheme: ColorThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var showCountingToast: Bool = false
    @State private var showResetToast: Bool = false

    private var countingMode: CountingMode { CountingMode(rawValue: countingModeRaw) ?? .all }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {

                    // Conteo de territorios
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Conteo de territorios/países:")
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            ForEach(CountingMode.allCases, id: \.self) { mode in
                                Button {
                                    countingModeRaw = mode.rawValue
                                    showCountingToast = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        showCountingToast = false
                                    }
                                } label: {
                                    Text(mode.label)
                                        .font(.palatino(.footnote, weight: countingMode == mode ? .bold : .regular))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            countingMode == mode ? Color.blue : Color(.systemGray5),
                                            in: RoundedRectangle(cornerRadius: 10)
                                        )
                                        .foregroundStyle(countingMode == mode ? .white : .primary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    // Posición del menú
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Posición del menú:")
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            ForEach([("top", "Arriba"), ("bottom", "Abajo")], id: \.0) { value, label in
                                Button {
                                    menuPositionRaw = value
                                } label: {
                                    Text(label)
                                        .font(.palatino(.footnote, weight: menuPositionRaw == value ? .bold : .regular))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            menuPositionRaw == value ? Color.blue : Color(.systemGray5),
                                            in: RoundedRectangle(cornerRadius: 10)
                                        )
                                        .foregroundStyle(menuPositionRaw == value ? .white : .primary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    // Visibilidad de categorías
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mostrar categorías:")
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.secondary)

                        VStack(spacing: 0) {
                            // Bucket List toggle manual (sin onChange para evitar bucles)
                            Button {
                                if showBucketList { pendingClear = .bucketList }
                                else { showBucketList = true }
                            } label: {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(colorTheme.bucketListColor)
                                        .frame(width: 14, height: 14)
                                    Text("Quiero")
                                        .font(.palatino(.body))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Toggle("", isOn: .constant(showBucketList))
                                        .labelsHidden()
                                        .tint(.blue)
                                        .allowsHitTesting(false)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            Divider().padding(.leading, 16)

                            // Vivido toggle manual
                            Button {
                                if showLived { pendingClear = .lived }
                                else { showLived = true }
                            } label: {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(colorTheme.livedColor)
                                        .frame(width: 14, height: 14)
                                    Text("Vivido")
                                        .font(.palatino(.body))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Toggle("", isOn: .constant(showLived))
                                        .labelsHidden()
                                        .tint(.blue)
                                        .allowsHitTesting(false)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 24)

                    // Contador próximo viaje
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Contador próximo viaje:")
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundStyle(.blue)
                                .frame(width: 20)
                            Text("Mostrar contador")
                                .font(.palatino(.body))
                            Spacer()
                            Toggle("", isOn: $showCountdown)
                                .labelsHidden()
                                .tint(.blue)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 24)

                    // Colores
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Colores")
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)

                        VStack(spacing: 0) {
                            ColorPickerRow(label: "Visitado",    color: $colorTheme.visitedColor)
                            Divider().padding(.leading, 56)
                            ColorPickerRow(label: "Quiero", color: $colorTheme.bucketListColor)
                            Divider().padding(.leading, 56)
                            ColorPickerRow(label: "Próximo",     color: $colorTheme.wantToVisitColor)
                            Divider().padding(.leading, 56)
                            ColorPickerRow(label: "Vivido",      color: $colorTheme.livedColor)
                        }
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 24)

                        Button {
                            colorTheme.resetToDefaults()
                            showResetToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showResetToast = false
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
                        .padding(.top, 4)
                    }

                    .padding(.bottom, 32)
                }
                .padding(.top, 20)
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                        .font(.palatino(.body))
                }
            }
            .confirmationDialog(
                "¿Eliminar datos?",
                isPresented: Binding(
                    get: { pendingClear != nil },
                    set: { if !$0 { pendingClear = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Eliminar", role: .destructive) {
                    if let status = pendingClear {
                        if status == .lived { showLived = false }
                        if status == .bucketList { showBucketList = false }
                        onClearStatus(status)
                    }
                    pendingClear = nil
                }
                Button("Cancelar", role: .cancel) {
                    pendingClear = nil
                }
            } message: {
                if let status = pendingClear {
                    Text("Se eliminarán todos los países de \(status == .lived ? "Vivido" : "Bucket list"). Esta acción no se puede deshacer.")
                }
            }
            .overlay {
                if showCountingToast || showResetToast {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white)
                        Text(showCountingToast ? "Conteo actualizado" : "Colores restablecidos")
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
        }
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
                                            Text(emoji)
                                                .font(.system(size: 36))
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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var editingVisitCount: Country? = nil
    @State private var addingTripFor: Country? = nil
    @State private var viewingTripsFor: Country? = nil
    @State private var confirmDeleteCountry: Country? = nil

    private var filtered: [CountryFeature] {
        let modeFiltered: [CountryFeature]
        switch mode {
        case .all:    modeFiltered = features
        case .un:     modeFiltered = features.filter { CountingMode.unMembers.contains($0.isoCode) }
        case .unPlus: modeFiltered = features.filter { CountingMode.unMembers.contains($0.isoCode) || CountingMode.unObservers.contains($0.isoCode) }
        }
        return modeFiltered.filter { visitedIsoCodes.contains($0.isoCode) }
    }

    private var grouped: [(letter: String, items: [CountryFeature])] {
        let sorted = filtered.sorted { $0.localizedName < $1.localizedName }
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
            List {
                ForEach(grouped, id: \.letter) { section in
                    Section(header: Text(section.letter).font(.palatino(.caption, weight: .bold))) {
                        ForEach(section.items, id: \.isoCode) { feature in
                            let c = country(for: feature.isoCode)
                            HStack(spacing: 10) {
                                Text(feature.flagEmoji ?? "🌐").font(.title3)
                                if c?.status == .lived {
                                    Text(feature.localizedName)
                                        .font(.palatino(.body)).foregroundStyle(.primary)
                                    Spacer()
                                } else {
                                    Button {
                                        if let c { viewingTripsFor = c }
                                    } label: {
                                        HStack(spacing: 10) {
                                            Text(feature.localizedName)
                                                .font(.palatino(.body)).foregroundStyle(.primary)
                                            Spacer()
                                            Text("\(c.map { totalVisits(for: $0) } ?? 0)x")
                                                .font(.palatino(.subheadline, weight: .bold))
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 8).padding(.vertical, 3)
                                                .background(Color(.systemGray5), in: Capsule())
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    Button {
                                        if let c { addingTripFor = c }
                                    } label: {
                                        Image(systemName: "calendar.badge.plus")
                                            .font(.title3).foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                // Delete button
                                Button {
                                    if let c { confirmDeleteCountry = c }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.callout).foregroundStyle(.red.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Visitados (\(filtered.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
            .confirmationDialog(
                "¿Eliminar este territorio?",
                isPresented: Binding(get: { confirmDeleteCountry != nil }, set: { if !$0 { confirmDeleteCountry = nil } }),
                presenting: confirmDeleteCountry
            ) { country in
                Button("Eliminar", role: .destructive) {
                    // Set to none, remove all trips
                    country.status = .none
                    country.plannedDate = nil
                    country.plannedDateTo = nil
                    country.transport = nil
                    country.visitCount = 0
                    for trip in trips where trip.isoCode == country.isoCode {
                        modelContext.delete(trip)
                    }
                    try? modelContext.save()
                    confirmDeleteCountry = nil
                }
                Button("Cancelar", role: .cancel) { confirmDeleteCountry = nil }
            } message: { country in
                let name = features.first(where: { $0.isoCode == country.isoCode })?.localizedName ?? country.name
                Text("Se eliminarán todos los datos de \(name): visitas, viajes y fechas.")
            }
            .sheet(item: $editingVisitCount) { country in
                VisitCountPickerSheet(country: country,
                    displayName: features.first(where: { $0.isoCode == country.isoCode })?.localizedName ?? country.name,
                    flagEmoji: features.first(where: { $0.isoCode == country.isoCode })?.flagEmoji ?? "🌐")
            }
            .sheet(item: $addingTripFor) { country in
                AddTripSheet(
                    isoCode: country.isoCode,
                    displayName: features.first(where: { $0.isoCode == country.isoCode })?.localizedName ?? country.name,
                    flagEmoji: features.first(where: { $0.isoCode == country.isoCode })?.flagEmoji ?? "🌐",
                    onSave: { trip in
                        modelContext.insert(trip)
                        try? modelContext.save()
                    }
                )
            }
            .sheet(item: $viewingTripsFor) { country in
                CountryTripsSheet(
                    country: country,
                    trips: trips.filter { $0.isoCode == country.isoCode },
                    displayName: features.first(where: { $0.isoCode == country.isoCode })?.localizedName ?? country.name,
                    flagEmoji: features.first(where: { $0.isoCode == country.isoCode })?.flagEmoji ?? "🌐"
                )
            }
        }
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


// MARK: - Selector de fecha para Próximos
struct PlannedDatePickerSheet: View {
    let countryName: String
    let flagEmoji: String
    let existingDate: Date?
    let existingDateTo: Date?
    let existingTransport: String?
    let existingTitle: String?
    var isEditing: Bool = false
    let onSave: (Date, Date?, String?, String?) -> Void  // dateFrom, dateTo, transport, title

    @Environment(\.dismiss) private var dismiss
    @State private var dateFrom: Date
    @State private var dateTo: Date?
    @State private var pickingFrom: Bool = true
    @State private var selectedTransport: String?
    @State private var tripTitle: String
    @State private var selectedAirports: [TripAirport] = []
    @State private var selectedAirlines: [AirlineData] = []
    @State private var airlineCounts: [String: Int] = [:]
    @State private var showAirportPicker = false
    @State private var showAirlinePicker = false

    static let transports: [(emoji: String, label: String)] = [
        ("✈️", "Avión"), ("🚗", "Coche"), ("🚂", "Tren"), ("🚌", "Bus"), ("🚢", "Barco"), ("🚶🏻", "Andando")
    ]
    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.locale = Locale(identifier: "es_ES"); return f
    }()

    init(countryName: String, flagEmoji: String,
         existingDate: Date?, existingDateTo: Date?, existingTransport: String?,
         existingTitle: String? = nil, isEditing: Bool = false,
         onSave: @escaping (Date, Date?, String?, String?) -> Void) {
        self.countryName = countryName
        self.flagEmoji = flagEmoji
        self.existingDate = existingDate
        self.existingDateTo = existingDateTo
        self.existingTransport = existingTransport
        self.existingTitle = existingTitle
        self.isEditing = isEditing
        self.onSave = onSave
        _dateFrom = State(initialValue: existingDate ?? Date())
        _dateTo = State(initialValue: existingDateTo)
        _selectedTransport = State(initialValue: existingTransport)
        _tripTitle = State(initialValue: existingTitle ?? "")
    }

    @ViewBuilder
    private func transportRow() -> some View {
        HStack(spacing: 8) {
            ForEach(Self.transports, id: \.emoji) { t in
                let isSelected = selectedTransport == t.emoji
                Button { selectedTransport = isSelected ? nil : t.emoji } label: {
                    VStack(spacing: 2) {
                        Text(t.emoji).font(.title3)
                        Text(t.label).font(.system(size: 9))
                            .foregroundStyle(isSelected ? .white : .secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(isSelected ? Color.blue : Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    @ViewBuilder
    private func dateTabsRow() -> some View {
        let fromLabel = Self.fmt.string(from: dateFrom)
        let toLabel = dateTo.map { Self.fmt.string(from: $0) } ?? "Sin vuelta"
        HStack(spacing: 0) {
            dateTab(isFrom: true, label: "DESDE", value: fromLabel)
            dateTab(isFrom: false, label: "HASTA", value: toLabel)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func dateTab(isFrom: Bool, label: String, value: String) -> some View {
        let active = pickingFrom == isFrom
        let color: Color = active ? .blue : (isFrom ? .primary : (dateTo == nil ? .secondary : .primary))
        Button { pickingFrom = isFrom } label: {
            VStack(spacing: 2) {
                Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Text(value).font(.palatino(.subheadline, weight: .bold)).foregroundStyle(color)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(active ? Color.blue.opacity(0.08) : Color.clear)
            .overlay(alignment: .bottom) {
                if active { Rectangle().fill(Color.blue).frame(height: 2) }
            }
        }.buttonStyle(.plain)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: 0) {
                Text("\(flagEmoji) \(countryName)")
                    .font(.palatino(.title3, weight: .bold))
                    .padding(.top, 12).padding(.bottom, isEditing ? 4 : 8)

                if isEditing {
                    TextField("Título del viaje *", text: $tripTitle)
                        .font(.palatino(.body))
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 16).padding(.bottom, 8)
                }

                transportRow()

                // Airport + Airlines (only for ✈️)
                if selectedTransport == "✈️" {
                    VStack(spacing: 8) {
                        Button { showAirportPicker = true } label: {
                            HStack {
                                Text(selectedAirports.isEmpty ? "Aeropuerto(s) de destino" : selectedAirports.map { "\($0.iata)\($0.roundTrip ? " (I/V)" : "")" }.joined(separator: ", "))
                                    .font(.palatino(.body))
                                    .foregroundStyle(selectedAirports.isEmpty ? .secondary : .primary)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)

                        Button { showAirlinePicker = true } label: {
                            HStack {
                                Text(selectedAirlines.isEmpty ? "Aerolínea(s)" : selectedAirlines.map { $0.name }.joined(separator: ", "))
                                    .font(.palatino(.body))
                                    .foregroundStyle(selectedAirlines.isEmpty ? .secondary : .primary)
                                    .lineLimit(2)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 8)
                }

                dateTabsRow()

                RangeDatePicker(dateFrom: $dateFrom, dateTo: $dateTo, pickingFrom: $pickingFrom)
                    .padding(.horizontal, 8)

                let canSave = selectedTransport != nil && (!isEditing || !tripTitle.isEmpty)
                Button {
                    let title: String? = isEditing && !tripTitle.isEmpty ? tripTitle : nil
                    onSave(dateFrom, dateTo, selectedTransport, title)
                    dismiss()
                } label: {
                    Text(isEditing ? "Guardar cambios" : "Añadir a Próximos")
                        .font(.palatino(.body, weight: .bold)).frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canSave ? Color.blue : Color(.systemGray4), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .disabled(!canSave)
                .padding(.horizontal, 24).padding(.bottom, 24)
            } // VStack
            } // ScrollView
            .navigationTitle("📅 Fecha de viaje")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .presentationDetents([.large])
        .sheet(isPresented: $showAirportPicker) {
            AirportPickerSheet(selected: $selectedAirports)
        }
        .sheet(isPresented: $showAirlinePicker) {
            AirlinePickerSheet(selected: $selectedAirlines)
        }
    }
}

struct RangeDatePicker: UIViewRepresentable {
    @Binding var dateFrom: Date
    @Binding var dateTo: Date?
    @Binding var pickingFrom: Bool

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
        // Show dateFrom as selected when picking from, dateTo when picking to
        let cal = Calendar.current
        let showDate = pickingFrom ? dateFrom : (dateTo ?? dateFrom)
        context.coordinator.singleSel?.selectedDate = cal.dateComponents([.year,.month,.day], from: showDate)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, UICalendarSelectionSingleDateDelegate {
        var parent: RangeDatePicker!
        weak var calendarView: UICalendarView?
        weak var singleSel: UICalendarSelectionSingleDate?

        func dateSelection(_ selection: UICalendarSelectionSingleDate,
                           didSelectDate dateComponents: DateComponents?) {
            guard let comps = dateComponents,
                  let date = Calendar.current.date(from: comps) else { return }
            if parent.pickingFrom {
                parent.dateFrom = date
                if let to = parent.dateTo, to <= date { parent.dateTo = nil }
                parent.pickingFrom = false
            } else {
                if date <= parent.dateFrom {
                    parent.dateFrom = date
                    parent.dateTo = nil
                } else {
                    parent.dateTo = date
                }
            }
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate,
                           canSelectDate dateComponents: DateComponents?) -> Bool { true }
    }
}


// MARK: - Vista de años de viaje en perfil
struct YearTravelView: View {
    let countries: [Country]
    let features: [CountryFeature]
    let trips: [Trip]

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    // Años: año actual + años con trips finalizados
    private var availableYears: [Int] {
        var years = Set<Int>()
        years.insert(currentYear)
        for trip in trips {
            let end = Calendar.current.startOfDay(for: trip.effectiveEndDate)
            if end <= today { years.insert(trip.year) }
        }
        // Also from country planned dates (legacy)
        for country in countries {
            let endDate = country.plannedDateTo ?? country.plannedDate
            guard let end = endDate else { continue }
            let endDay = Calendar.current.startOfDay(for: end)
            if endDay <= today { years.insert(Calendar.current.component(.year, from: end)) }
        }
        return years.sorted(by: >)
    }

    // Finalizados: países con al menos un trip finalizado en el año seleccionado.
    // Cada país aparece UNA sola vez. Orden FIFO: por dateFrom del PRIMER viaje a ese país en el año.
    private var finalizados: [(isoCode: String, lastDate: Date)] {
        // Collect all (isoCode, dateFrom) pairs for finished trips this year
        var allEntries: [String: [Date]] = [:]  // isoCode -> list of dateFrom
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
        // For each country: take earliest dateFrom (FIFO = first trip comes first)
        var result: [(isoCode: String, lastDate: Date)] = []
        for (iso, dates) in allEntries {
            if let earliest = dates.min() {
                result.append((isoCode: iso, lastDate: earliest))
            }
        }
        return result.sorted { $0.lastDate < $1.lastDate }
    }

    // Próximos: status wantToVisit
    private var proximos: [Country] {
        let today = Calendar.current.startOfDay(for: Date())
        // Include wantToVisit + visited with future trip (same as badge proxCount)
        let futureIsoCodes = Set(trips.compactMap { trip -> String? in
            guard Calendar.current.startOfDay(for: trip.dateFrom) >= today else { return nil }
            return trip.isoCode
        })
        let visitedWithFuture = countries.filter { $0.status == .visited && futureIsoCodes.contains($0.isoCode) }
        let wantToVisit = countries.filter { $0.status == .wantToVisit }
        let all = (wantToVisit + visitedWithFuture)
        func nextDate(_ country: Country) -> Date? {
            if country.status == .wantToVisit { return country.plannedDate }
            return trips.filter { t in
                t.isoCode == country.isoCode && Calendar.current.startOfDay(for: t.dateFrom) >= today
            }.min(by: { lhs, rhs in lhs.dateFrom < rhs.dateFrom })?.dateFrom
        }
        return all.sorted { c0, c1 in
            switch (nextDate(c0), nextDate(c1)) {
            case let (a?, b?): return a < b
            case (_?, nil): return true
            default: return false
            }
        }
        .prefix(10).map { $0 }
    }

    private func flagEmoji(for country: Country) -> String? {
        features.first(where: { $0.isoCode == country.isoCode })?.flagEmoji
    }

    var body: some View {
        VStack(spacing: 20) {
            // Selector de años — siempre scroll por si hay muchos
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableYears, id: \.self) { year in
                        Button {
                            selectedYear = year
                        } label: {
                            Text(String(year))
                                .font(.palatino(.subheadline, weight: selectedYear == year ? .bold : .regular))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background(selectedYear == year ? Color.blue : Color(.systemGray5),
                                            in: Capsule())
                                .foregroundStyle(selectedYear == year ? .white : .primary)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }

            if selectedYear == currentYear {
                // Año actual: Finalizados (izq) + Próximos (der)
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .center, spacing: 6) {
                        Text("Finalizados")
                            .font(.palatino(.caption, weight: .bold))
                            .foregroundStyle(.secondary)
                        if finalizados.isEmpty {
                            Text("–").font(.palatino(.caption)).foregroundStyle(.secondary)
                        } else {
                            FlowLayoutCentered(emojis: finalizados.compactMap { f in features.first(where: { $0.isoCode == f.isoCode })?.flagEmoji })
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    Divider()

                    VStack(alignment: .center, spacing: 6) {
                        Text("Próximos")
                            .font(.palatino(.caption, weight: .bold))
                            .foregroundStyle(.secondary)
                        if proximos.isEmpty {
                            Text("–").font(.palatino(.caption)).foregroundStyle(.secondary)
                        } else {
                            FlowLayoutCentered(emojis: proximos.compactMap { flagEmoji(for: $0) })
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, 24)
            } else {
                // Año pasado: solo Finalizados centrado
                VStack(alignment: .center, spacing: 6) {
                    Text("Finalizados")
                        .font(.palatino(.caption, weight: .bold))
                        .foregroundStyle(.secondary)
                    if finalizados.isEmpty {
                        Text("–").font(.palatino(.caption)).foregroundStyle(.secondary)
                    } else {
                        FlowLayoutCentered(emojis: finalizados.compactMap { f in features.first(where: { $0.isoCode == f.isoCode })?.flagEmoji })
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)
            }
        }
    }
}

// Wrapping row of flag emojis
struct FlowLayout: View {
    let emojis: [String]
    var body: some View {
        let rows = stride(from: 0, to: emojis.count, by: 10).map {
            Array(emojis[$0..<min($0+10, emojis.count)])
        }
        VStack(alignment: .leading, spacing: 2) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 2) {
                    ForEach(rows[i], id: \.self) { e in
                        Text(e).font(.system(size: 22))
                    }
                }
            }
        }
    }
}

struct FlowLayoutCentered: View {
    let emojis: [String]
    var body: some View {
        let rows = stride(from: 0, to: emojis.count, by: 10).map {
            Array(emojis[$0..<min($0+10, emojis.count)])
        }
        VStack(alignment: .center, spacing: 2) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 2) {
                    ForEach(rows[i], id: \.self) { e in
                        Text(e).font(.system(size: 22))
                    }
                }
            }
        }
    }
}

// MARK: - Banderas de Próximos en perfil (máx 10, ordenadas por fecha)
struct ProximosFlagsView: View {
    let countries: [Country]
    let features: [CountryFeature]

    private var proximos: [Country] {
        let filtered = countries.filter { $0.status == .wantToVisit }
        let sorted = filtered.sorted {
            switch ($0.plannedDate, $1.plannedDate) {
            case let (a?, b?): return a < b
            case (_?, nil):    return true
            case (nil, _?):    return false
            default:           return false
            }
        }
        return Array(sorted.prefix(10))
    }

    private func flagEmoji(for country: Country) -> String {
        features.first(where: { $0.isoCode == country.isoCode })?.flagEmoji ?? "🌐"
    }

    var body: some View {
        if !proximos.isEmpty {
            VStack(spacing: 6) {
                Text("Próximos")
                    .font(.palatino(.title2, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 4) {
                    ForEach(proximos, id: \.isoCode) { country in
                        Text(flagEmoji(for: country))
                            .font(.system(size: 28))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 24)
        }
    }
}


// MARK: - Selector de número de visitas
struct VisitCountPickerSheet: View {
    @Bindable var country: Country
    let displayName: String
    let flagEmoji: String

    @Environment(\.dismiss) private var dismiss
    @State private var count: Int

    init(country: Country, displayName: String, flagEmoji: String) {
        self.country = country
        self.displayName = displayName
        self.flagEmoji = flagEmoji
        _count = State(initialValue: max(1, country.visitCount))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Text("\(flagEmoji) \(displayName)")
                    .font(.palatino(.title2, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("¿Cuántas veces has visitado?")
                    .font(.palatino(.subheadline))
                    .foregroundStyle(.secondary)

                // Stepper grande
                HStack(spacing: 40) {
                    Button {
                        if count > 1 { count -= 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(count > 1 ? .blue : Color(.systemGray4))
                    }
                    .disabled(count <= 1)

                    Text("\(count)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .frame(minWidth: 80)
                        .monospacedDigit()

                    Button {
                        count += 1
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                    }
                }

                Text(count == 1 ? "vez" : "veces")
                    .font(.palatino(.title3))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    country.visitCount = count
                    dismiss()
                } label: {
                    Text("Guardar")
                        .font(.palatino(.body, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .navigationTitle("Visitas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }
                        .font(.palatino(.body))
                }
            }
        }
        .presentationDetents([.large])
    }
}


// MARK: - Exportar mapa como imagen
struct MapExportSheet: View {
    let visitedCountries: [Country]
    let features: [CountryFeature]
    let counter: String
    let visitedColor: Color
    let countingModeRaw: String
    let trips: [Trip]

    @Environment(\.dismiss) private var dismiss
    @State private var renderedImage: UIImage? = nil
    @State private var isRendering: Bool = true
    @State private var isSaving: Bool = false
    @State private var savedToast: Bool = false
    @State private var selectedZone: ExportZone = .europa
    @State private var selectedSubgroup: SubgroupInfo? = nil
    @State private var showTransportStats: Bool = false

    enum ExportZone: String, CaseIterable, Identifiable {
        case europa      = "Europa"
        case asia        = "Asia"
        case medioOriente = "M. Oriente"
        case africa      = "África"
        case america     = "América"
        case oceania     = "Oceanía"
        var id: String { rawValue }

        func denominator(mode: CountingMode) -> Int {
            let codes = isoCodes
            switch mode {
            case .all:    return codes.count
            case .un:     return codes.filter { CountingMode.unMembers.contains($0) }.count
            case .unPlus: return codes.filter { CountingMode.unMembers.contains($0) || CountingMode.unObservers.contains($0) }.count
            }
        }

        var region: MKCoordinateRegion {
            switch self {
            case .europa:
                return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 54, longitude: 15),
                                          span: MKCoordinateSpan(latitudeDelta: 36, longitudeDelta: 50))
            case .asia:
                return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 35, longitude: 95),
                                          span: MKCoordinateSpan(latitudeDelta: 60, longitudeDelta: 90))
            case .medioOriente:
                return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 27, longitude: 42),
                                          span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 36))
            case .africa:
                return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 2, longitude: 20),
                                          span: MKCoordinateSpan(latitudeDelta: 90, longitudeDelta: 75))
            case .america:
                return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 15, longitude: -80),
                                          span: MKCoordinateSpan(latitudeDelta: 100, longitudeDelta: 100))
            case .oceania:
                return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: -20, longitude: 150),
                                          span: MKCoordinateSpan(latitudeDelta: 60, longitudeDelta: 70))
            }
        }

        var isoCodes: Set<String> {
            switch self {
            case .europa:
                return ["ALB","AND","AUT","BLR","BEL","BIH","BGR","HRV","CYP","CZE","DNK","EST","FIN","FRA","DEU",
                        "GRC","HUN","ISL","IRL","ITA","LVA","LIE","LTU","LUX","MLT","MDA","MCO","MNE","NLD","MKD",
                        "NOR","POL","PRT","ROU","RUS","SMR","SRB","SVK","SVN","ESP","SWE","CHE","UKR","GBR","VAT",
                        "KOS","ALD","FRO","GIB","GGY","IMN","JEY"]
            case .asia:
                return ["AFG","ARM","AZE","BGD","BTN","BRN","KHM","CHN","GEO","IND","IDN","JPN","KAZ","PRK","KOR",
                        "KGZ","LAO","MYS","MDV","MNG","MMR","NPL","PAK","PHL","SGP","LKA","TWN","TJK","THA","TLS",
                        "TKM","UZB","VNM","HKG","MAC","IOT"]
            case .medioOriente:
                return ["BHR","IRN","IRQ","ISR","JOR","KWT","LBN","OMN","PSE","PSX","QAT","SAU","SYR","TUR","ARE","YEM"]
            case .africa:
                return ["DZA","AGO","BEN","BWA","BFA","BDI","CPV","CMR","CAF","TCD","COM","COD","COG","CIV","DJI",
                        "EGY","GNQ","ERI","ETH","GAB","GMB","GHA","GIN","GNB","KEN","LSO","LBR","LBY","MDG","MWI",
                        "MLI","MRT","MUS","MAR","MOZ","NAM","NER","NGA","RWA","STP","SEN","SYC","SLE","SOM","ZAF",
                        "SSD","SDS","SDN","SWZ","TZA","TGO","TUN","UGA","ZMB","ZWE","SAH","SHN"]
            case .america:
                return ["ATG","ARG","BHS","BRB","BLZ","BOL","BRA","CAN","CHL","COL","CRI","CUB","DMA","DOM","ECU",
                        "SLV","GRD","GTM","GUY","HTI","HND","JAM","MEX","NIC","PAN","PRY","PER","KNA","LCA","VCT",
                        "SUR","TTO","USA","URY","VEN","ABW","AIA","BMU","VGB","CYM","CUW","FLK","GRL","MSR","PRI",
                        "BLM","MAF","SPM","SXM","TCA","VIR"]
            case .oceania:
                return ["AUS","FJI","KIR","MHL","FSM","NRU","NZL","PLW","PNG","WSM","SLB","TON","TUV","VUT",
                        "ASM","COK","PYF","GUM","NCL","NIU","NFK","MNP","PCN","WLF"]
            }
        }
    }

    private var filteredCountries: [Country] {
        let codes = selectedZone.isoCodes
        return visitedCountries.filter { codes.contains($0.isoCode) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Selector de zona — 2 filas de 3
                let zones = ExportZone.allCases
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(zones.prefix(3)) { zone in zoneButton(zone) }
                    }
                    HStack(spacing: 8) {
                        ForEach(zones.dropFirst(3)) { zone in zoneButton(zone) }
                    }
                }
                .padding(.horizontal, 16)

                // Imagen generada
                ZStack {
                    if let img = renderedImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(radius: 6)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                VStack(spacing: 12) {
                                    ProgressView()
                                    Text("Generando mapa…")
                                        .font(.palatino(.caption))
                                        .foregroundStyle(.secondary)
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .id(selectedZone)
                .onAppear { renderMap() }
                .onChange(of: selectedZone) { _, _ in renderMap() }

                // Estadísticas por subregión
                if selectedZone == .europa {
                    europaStatsView()
                } else if selectedZone == .asia {
                    asiaStatsView()
                } else if selectedZone == .america {
                    americaStatsView()
                } else if selectedZone == .medioOriente {
                    medioOrienteStatsView()
                } else if selectedZone == .africa {
                    africaStatsView()
                } else if selectedZone == .oceania {
                    oceaniaStatsView()
                }

                Spacer()

                Button {
                    guard let img = renderedImage else { return }
                    isSaving = true
                    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                        DispatchQueue.main.async {
                            guard status == .authorized || status == .limited else {
                                isSaving = false
                                return
                            }
                            PHPhotoLibrary.shared().performChanges({
                                PHAssetChangeRequest.creationRequestForAsset(from: img)
                            }) { success, _ in
                                DispatchQueue.main.async {
                                    isSaving = false
                                    if success {
                                        savedToast = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                            savedToast = false
                                        }
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isSaving { ProgressView().tint(.white) }
                        else { Image(systemName: "square.and.arrow.down") }
                        Text(savedToast ? "¡Guardada!" : "Guardar en galería")
                    }
                    .font(.palatino(.body, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(savedToast ? Color.green : Color.blue, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .disabled(renderedImage == nil)
                .animation(.easeInOut(duration: 0.2), value: savedToast)
            }
            .padding(.top, 8)
            .navigationTitle("Estadísticas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showTransportStats = true
                    } label: {
                        Image(systemName: "airplane.departure")
                    }
                    .font(.palatino(.body))
                }
            }
            .sheet(isPresented: $showTransportStats) {
                TransportStatsSheet(visitedCountries: visitedCountries, trips: trips, allFeatures: features)
            }
            .sheet(item: $selectedSubgroup) { info in
                SubgroupListSheet(
                    title: info.title,
                    emoji: info.emoji,
                    isoCodes: info.isoCodes,
                    visitedCountries: visitedCountries,
                    features: features,
                    countingModeRaw: countingModeRaw,
                    trips: trips
                )
            }
        }
    }

    // Capital coordinates by ISO A3
    private static let capitals: [String: CLLocationCoordinate2D] = [
        "AFG": CLLocationCoordinate2D(latitude: 34.52, longitude: 69.17),
        "ALB": CLLocationCoordinate2D(latitude: 40.46, longitude: 19.49),
        "DZA": CLLocationCoordinate2D(latitude: 36.74, longitude: 3.06),
        "AND": CLLocationCoordinate2D(latitude: 42.51, longitude: 1.52),
        "AGO": CLLocationCoordinate2D(latitude: -8.84, longitude: 13.23),
        "ARG": CLLocationCoordinate2D(latitude: -34.60, longitude: -58.38),
        "ARM": CLLocationCoordinate2D(latitude: 40.18, longitude: 44.51),
        "AUS": CLLocationCoordinate2D(latitude: -35.28, longitude: 149.13),
        "AUT": CLLocationCoordinate2D(latitude: 47.27, longitude: 11.40),
        "AZE": CLLocationCoordinate2D(latitude: 40.41, longitude: 49.87),
        "BHS": CLLocationCoordinate2D(latitude: 25.05, longitude: -77.35),
        "BHR": CLLocationCoordinate2D(latitude: 26.21, longitude: 50.59),
        "BGD": CLLocationCoordinate2D(latitude: 23.72, longitude: 90.41),
        "BRB": CLLocationCoordinate2D(latitude: 13.10, longitude: -59.62),
        "BLR": CLLocationCoordinate2D(latitude: 53.90, longitude: 27.57),
        "BEL": CLLocationCoordinate2D(latitude: 50.85, longitude: 4.35),
        "BLZ": CLLocationCoordinate2D(latitude: 17.25, longitude: -88.77),
        "BEN": CLLocationCoordinate2D(latitude: 6.37, longitude: 2.43),
        "BTN": CLLocationCoordinate2D(latitude: 27.47, longitude: 89.64),
        "BOL": CLLocationCoordinate2D(latitude: -16.50, longitude: -68.15),
        "BIH": CLLocationCoordinate2D(latitude: 43.85, longitude: 18.36),
        "BWA": CLLocationCoordinate2D(latitude: -24.63, longitude: 25.91),
        "BRA": CLLocationCoordinate2D(latitude: -15.78, longitude: -47.93),
        "BRN": CLLocationCoordinate2D(latitude: 4.94, longitude: 114.95),
        "BGR": CLLocationCoordinate2D(latitude: 42.15, longitude: 24.75),
        "BFA": CLLocationCoordinate2D(latitude: 12.37, longitude: -1.53),
        "BDI": CLLocationCoordinate2D(latitude: -3.38, longitude: 29.36),
        "CPV": CLLocationCoordinate2D(latitude: 14.93, longitude: -23.51),
        "KHM": CLLocationCoordinate2D(latitude: 11.57, longitude: 104.92),
        "CMR": CLLocationCoordinate2D(latitude: 3.87, longitude: 11.52),
        "CAN": CLLocationCoordinate2D(latitude: 45.42, longitude: -75.70),
        "CAF": CLLocationCoordinate2D(latitude: 4.36, longitude: 18.56),
        "TCD": CLLocationCoordinate2D(latitude: 12.11, longitude: 15.05),
        "CHL": CLLocationCoordinate2D(latitude: -33.46, longitude: -70.65),
        "CHN": CLLocationCoordinate2D(latitude: 39.92, longitude: 116.38),
        "COL": CLLocationCoordinate2D(latitude: 4.71, longitude: -74.07),
        "COM": CLLocationCoordinate2D(latitude: -11.70, longitude: 43.26),
        "COD": CLLocationCoordinate2D(latitude: -4.32, longitude: 15.32),
        "COG": CLLocationCoordinate2D(latitude: -4.27, longitude: 15.28),
        "CRI": CLLocationCoordinate2D(latitude: 9.93, longitude: -84.08),
        "CIV": CLLocationCoordinate2D(latitude: 6.82, longitude: -5.28),
        "HRV": CLLocationCoordinate2D(latitude: 43.51, longitude: 16.44),
        "CUB": CLLocationCoordinate2D(latitude: 23.13, longitude: -82.38),
        "CYP": CLLocationCoordinate2D(latitude: 35.17, longitude: 33.37),
        "CZE": CLLocationCoordinate2D(latitude: 50.08, longitude: 14.47),
        "DNK": CLLocationCoordinate2D(latitude: 55.73, longitude: 9.12),
        "DJI": CLLocationCoordinate2D(latitude: 11.59, longitude: 43.15),
        "DMA": CLLocationCoordinate2D(latitude: 15.30, longitude: -61.39),
        "DOM": CLLocationCoordinate2D(latitude: 18.48, longitude: -69.89),
        "ECU": CLLocationCoordinate2D(latitude: -0.22, longitude: -78.52),
        "EGY": CLLocationCoordinate2D(latitude: 30.06, longitude: 31.25),
        "SLV": CLLocationCoordinate2D(latitude: 13.70, longitude: -89.21),
        "GNQ": CLLocationCoordinate2D(latitude: 3.75, longitude: 8.78),
        "ERI": CLLocationCoordinate2D(latitude: 15.33, longitude: 38.93),
        "EST": CLLocationCoordinate2D(latitude: 59.44, longitude: 24.75),
        "ETH": CLLocationCoordinate2D(latitude: 9.03, longitude: 38.74),
        "FJI": CLLocationCoordinate2D(latitude: -18.14, longitude: 178.44),
        "FIN": CLLocationCoordinate2D(latitude: 61.50, longitude: 23.77),
        "FRA": CLLocationCoordinate2D(latitude: 48.85, longitude: 2.35),
        "GAB": CLLocationCoordinate2D(latitude: 0.39, longitude: 9.45),
        "GMB": CLLocationCoordinate2D(latitude: 13.45, longitude: -16.58),
        "GEO": CLLocationCoordinate2D(latitude: 41.69, longitude: 44.83),
        "DEU": CLLocationCoordinate2D(latitude: 52.52, longitude: 13.40),
        "GHA": CLLocationCoordinate2D(latitude: 5.56, longitude: -0.20),
        "GRC": CLLocationCoordinate2D(latitude: 37.98, longitude: 23.73),
        "GRD": CLLocationCoordinate2D(latitude: 12.05, longitude: -61.75),
        "GTM": CLLocationCoordinate2D(latitude: 14.64, longitude: -90.51),
        "GIN": CLLocationCoordinate2D(latitude: 9.54, longitude: -13.68),
        "GNB": CLLocationCoordinate2D(latitude: 11.86, longitude: -15.60),
        "GUY": CLLocationCoordinate2D(latitude: 6.80, longitude: -58.16),
        "HTI": CLLocationCoordinate2D(latitude: 18.54, longitude: -72.34),
        "HND": CLLocationCoordinate2D(latitude: 14.10, longitude: -87.22),
        "HUN": CLLocationCoordinate2D(latitude: 47.50, longitude: 19.04),
        "ISL": CLLocationCoordinate2D(latitude: 64.66, longitude: -14.28),
        "IND": CLLocationCoordinate2D(latitude: 28.61, longitude: 77.21),
        "IDN": CLLocationCoordinate2D(latitude: -6.21, longitude: 106.85),
        "IRN": CLLocationCoordinate2D(latitude: 35.69, longitude: 51.42),
        "IRQ": CLLocationCoordinate2D(latitude: 33.34, longitude: 44.40),
        "IRL": CLLocationCoordinate2D(latitude: 53.33, longitude: -6.25),
        "ISR": CLLocationCoordinate2D(latitude: 31.77, longitude: 35.22),
        "ITA": CLLocationCoordinate2D(latitude: 40.85, longitude: 14.27),
        "JAM": CLLocationCoordinate2D(latitude: 17.99, longitude: -76.79),
        "JPN": CLLocationCoordinate2D(latitude: 35.69, longitude: 139.69),
        "JOR": CLLocationCoordinate2D(latitude: 31.95, longitude: 35.93),
        "KAZ": CLLocationCoordinate2D(latitude: 51.18, longitude: 71.45),
        "KEN": CLLocationCoordinate2D(latitude: -1.28, longitude: 36.82),
        "KIR": CLLocationCoordinate2D(latitude: 1.33, longitude: 173.02),
        "PRK": CLLocationCoordinate2D(latitude: 39.03, longitude: 125.75),
        "KOR": CLLocationCoordinate2D(latitude: 37.55, longitude: 126.99),
        "KWT": CLLocationCoordinate2D(latitude: 29.37, longitude: 47.98),
        "KGZ": CLLocationCoordinate2D(latitude: 42.87, longitude: 74.59),
        "LAO": CLLocationCoordinate2D(latitude: 17.97, longitude: 102.60),
        "LVA": CLLocationCoordinate2D(latitude: 56.95, longitude: 24.11),
        "LBN": CLLocationCoordinate2D(latitude: 33.89, longitude: 35.50),
        "LSO": CLLocationCoordinate2D(latitude: -29.32, longitude: 27.48),
        "LBR": CLLocationCoordinate2D(latitude: 6.30, longitude: -10.80),
        "LBY": CLLocationCoordinate2D(latitude: 32.90, longitude: 13.18),
        "LIE": CLLocationCoordinate2D(latitude: 47.14, longitude: 9.52),
        "LTU": CLLocationCoordinate2D(latitude: 54.69, longitude: 25.28),
        "LUX": CLLocationCoordinate2D(latitude: 49.61, longitude: 6.13),
        "MDG": CLLocationCoordinate2D(latitude: -18.91, longitude: 47.54),
        "MWI": CLLocationCoordinate2D(latitude: -13.97, longitude: 33.79),
        "MYS": CLLocationCoordinate2D(latitude: 3.15, longitude: 101.69),
        "MDV": CLLocationCoordinate2D(latitude: 4.17, longitude: 73.51),
        "MLI": CLLocationCoordinate2D(latitude: 12.65, longitude: -8.00),
        "MLT": CLLocationCoordinate2D(latitude: 35.90, longitude: 14.51),
        "MHL": CLLocationCoordinate2D(latitude: 7.10, longitude: 171.38),
        "MRT": CLLocationCoordinate2D(latitude: 18.08, longitude: -15.97),
        "MUS": CLLocationCoordinate2D(latitude: -20.16, longitude: 57.49),
        "MEX": CLLocationCoordinate2D(latitude: 19.43, longitude: -99.13),
        "FSM": CLLocationCoordinate2D(latitude: 6.92, longitude: 158.16),
        "MDA": CLLocationCoordinate2D(latitude: 47.01, longitude: 28.86),
        "MCO": CLLocationCoordinate2D(latitude: 43.74, longitude: 7.41),
        "MNG": CLLocationCoordinate2D(latitude: 47.91, longitude: 106.92),
        "MNE": CLLocationCoordinate2D(latitude: 42.49, longitude: 18.70),
        "MAR": CLLocationCoordinate2D(latitude: 31.63, longitude: -8.00),
        "MOZ": CLLocationCoordinate2D(latitude: -25.97, longitude: 32.59),
        "MMR": CLLocationCoordinate2D(latitude: 16.80, longitude: 96.16),
        "NAM": CLLocationCoordinate2D(latitude: -22.56, longitude: 17.08),
        "NRU": CLLocationCoordinate2D(latitude: -0.55, longitude: 166.92),
        "NPL": CLLocationCoordinate2D(latitude: 27.70, longitude: 85.32),
        "NLD": CLLocationCoordinate2D(latitude: 52.38, longitude: 4.90),
        "NZL": CLLocationCoordinate2D(latitude: -41.29, longitude: 174.78),
        "NIC": CLLocationCoordinate2D(latitude: 12.13, longitude: -86.28),
        "NER": CLLocationCoordinate2D(latitude: 13.51, longitude: 2.12),
        "NGA": CLLocationCoordinate2D(latitude: 9.07, longitude: 7.40),
        "MKD": CLLocationCoordinate2D(latitude: 41.65, longitude: 22.47),
        "NOR": CLLocationCoordinate2D(latitude: 59.91, longitude: 10.75),
        "OMN": CLLocationCoordinate2D(latitude: 23.61, longitude: 58.59),
        "PAK": CLLocationCoordinate2D(latitude: 33.72, longitude: 73.06),
        "PLW": CLLocationCoordinate2D(latitude: 7.34, longitude: 134.48),
        "PSE": CLLocationCoordinate2D(latitude: 31.90, longitude: 35.20),
        "PAN": CLLocationCoordinate2D(latitude: 8.99, longitude: -79.52),
        "PNG": CLLocationCoordinate2D(latitude: -9.44, longitude: 147.18),
        "PRY": CLLocationCoordinate2D(latitude: -25.29, longitude: -57.65),
        "PER": CLLocationCoordinate2D(latitude: -12.05, longitude: -77.04),
        "PHL": CLLocationCoordinate2D(latitude: 14.60, longitude: 120.98),
        "POL": CLLocationCoordinate2D(latitude: 52.23, longitude: 21.01),
        "PRT": CLLocationCoordinate2D(latitude: 38.72, longitude: -9.14),
        "QAT": CLLocationCoordinate2D(latitude: 25.29, longitude: 51.53),
        "ROU": CLLocationCoordinate2D(latitude: 44.44, longitude: 26.10),
        "RUS": CLLocationCoordinate2D(latitude: 55.75, longitude: 37.62),
        "RWA": CLLocationCoordinate2D(latitude: -1.95, longitude: 30.06),
        "KNA": CLLocationCoordinate2D(latitude: 17.30, longitude: -62.72),
        "LCA": CLLocationCoordinate2D(latitude: 13.99, longitude: -61.01),
        "VCT": CLLocationCoordinate2D(latitude: 13.16, longitude: -61.22),
        "WSM": CLLocationCoordinate2D(latitude: -13.82, longitude: -171.77),
        "STP": CLLocationCoordinate2D(latitude: 0.34, longitude: 6.73),
        "SAU": CLLocationCoordinate2D(latitude: 24.69, longitude: 46.72),
        "SEN": CLLocationCoordinate2D(latitude: 14.69, longitude: -17.44),
        "SRB": CLLocationCoordinate2D(latitude: 44.80, longitude: 20.46),
        "SYC": CLLocationCoordinate2D(latitude: -4.62, longitude: 55.46),
        "SLE": CLLocationCoordinate2D(latitude: 8.49, longitude: -13.23),
        "SGP": CLLocationCoordinate2D(latitude: 1.28, longitude: 103.85),
        "SVK": CLLocationCoordinate2D(latitude: 48.15, longitude: 17.12),
        "SVN": CLLocationCoordinate2D(latitude: 46.05, longitude: 14.51),
        "SLB": CLLocationCoordinate2D(latitude: -9.43, longitude: 160.03),
        "SOM": CLLocationCoordinate2D(latitude: 2.05, longitude: 45.34),
        "ZAF": CLLocationCoordinate2D(latitude: -25.74, longitude: 28.19),
        "SSD": CLLocationCoordinate2D(latitude: 4.85, longitude: 31.57),
        "ESP": CLLocationCoordinate2D(latitude: 40.42, longitude: -3.70),
        "LKA": CLLocationCoordinate2D(latitude: 6.92, longitude: 79.86),
        "SDN": CLLocationCoordinate2D(latitude: 15.55, longitude: 32.53),
        "SUR": CLLocationCoordinate2D(latitude: 5.87, longitude: -55.17),
        "SWZ": CLLocationCoordinate2D(latitude: -26.32, longitude: 31.14),
        "SWE": CLLocationCoordinate2D(latitude: 59.33, longitude: 18.07),
        "CHE": CLLocationCoordinate2D(latitude: 46.95, longitude: 7.45),
        "SYR": CLLocationCoordinate2D(latitude: 33.51, longitude: 36.29),
        "TWN": CLLocationCoordinate2D(latitude: 25.05, longitude: 121.56),
        "TJK": CLLocationCoordinate2D(latitude: 38.56, longitude: 68.77),
        "TZA": CLLocationCoordinate2D(latitude: -6.18, longitude: 35.74),
        "THA": CLLocationCoordinate2D(latitude: 13.75, longitude: 100.52),
        "TLS": CLLocationCoordinate2D(latitude: -8.56, longitude: 125.58),
        "TGO": CLLocationCoordinate2D(latitude: 6.14, longitude: 1.22),
        "TON": CLLocationCoordinate2D(latitude: -21.13, longitude: -175.20),
        "TTO": CLLocationCoordinate2D(latitude: 10.65, longitude: -61.52),
        "TUN": CLLocationCoordinate2D(latitude: 34.41, longitude: 8.81),
        "TUR": CLLocationCoordinate2D(latitude: 39.92, longitude: 32.86),
        "TKM": CLLocationCoordinate2D(latitude: 37.95, longitude: 58.38),
        "TUV": CLLocationCoordinate2D(latitude: -8.52, longitude: 179.20),
        "UGA": CLLocationCoordinate2D(latitude: 0.32, longitude: 32.58),
        "UKR": CLLocationCoordinate2D(latitude: 50.45, longitude: 30.52),
        "ARE": CLLocationCoordinate2D(latitude: 24.47, longitude: 54.37),
        "GBR": CLLocationCoordinate2D(latitude: 51.51, longitude: -0.13),
        "USA": CLLocationCoordinate2D(latitude: 37.68, longitude: -97.33),
        "URY": CLLocationCoordinate2D(latitude: -34.86, longitude: -56.17),
        "UZB": CLLocationCoordinate2D(latitude: 41.30, longitude: 69.27),
        "VUT": CLLocationCoordinate2D(latitude: -17.73, longitude: 168.32),
        "VAT": CLLocationCoordinate2D(latitude: 41.90, longitude: 12.45),
        "VEN": CLLocationCoordinate2D(latitude: 10.48, longitude: -66.90),
        "VNM": CLLocationCoordinate2D(latitude: 21.03, longitude: 105.85),
        "YEM": CLLocationCoordinate2D(latitude: 15.35, longitude: 44.21),
        "ZMB": CLLocationCoordinate2D(latitude: -15.42, longitude: 28.28),
        "ZWE": CLLocationCoordinate2D(latitude: -17.83, longitude: 31.05),
        "XKX": CLLocationCoordinate2D(latitude: 42.67, longitude: 21.17),
        "KOS": CLLocationCoordinate2D(latitude: 42.67, longitude: 21.17),
        "HKG": CLLocationCoordinate2D(latitude: 22.32, longitude: 114.17),
        "MAC": CLLocationCoordinate2D(latitude: 22.20, longitude: 113.54),
        "PSX": CLLocationCoordinate2D(latitude: 31.90, longitude: 35.20),
        "GRL": CLLocationCoordinate2D(latitude: 64.18, longitude: -51.74),
        "PRI": CLLocationCoordinate2D(latitude: 18.47, longitude: -66.11),
        "GIB": CLLocationCoordinate2D(latitude: 36.14, longitude: -5.35),
        "FRO": CLLocationCoordinate2D(latitude: 62.01, longitude: -6.77),
        "SDS": CLLocationCoordinate2D(latitude: 4.85, longitude: 31.57),
    ]

    private func capitalCoord(for isoCode: String, feature: CountryFeature) -> CLLocationCoordinate2D {
        if let cap = Self.capitals[isoCode] { return cap }
        return MKCoordinateRegion(feature.boundingMapRect).center
    }

        private static let sudEsteAsiatico: Set<String> = [
        "BRN","KHM","IDN","LAO","MYS","MMR","PHL","SGP","THA","TLS","VNM"
    ]
    private static let asiaCentral: Set<String> = [
        "KAZ","KGZ","TJK","TKM","UZB","MNG","AFG"
    ]
    private static let asiaSur: Set<String> = [
        "BGD","BTN","IND","MDV","NPL","PAK","LKA"
    ]
    private static let asiaEste: Set<String> = ["CHN","JPN","KOR","PRK","TWN","HKG","MAC","MNG"]

    @ViewBuilder
    private func asiaStatsView() -> some View {
        let sudeste = visitedCount(in: Self.sudEsteAsiatico)
        let central = visitedCount(in: Self.asiaCentral)
        let sur     = visitedCount(in: Self.asiaSur)
        let este    = visitedCount(in: Self.asiaEste)

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statTile(title: "Asia central",     visited: central.visited, total: central.total, emoji: "🏔️", group: Self.asiaCentral)
            statTile(title: "Asia este",        visited: este.visited,    total: este.total,    emoji: "🗾", group: Self.asiaEste)
            statTile(title: "Asia sur",         visited: sur.visited,     total: sur.total,     emoji: "🕌", group: Self.asiaSur)
            statTile(title: "Asia sudeste", visited: sudeste.visited, total: sudeste.total, emoji: "🌴", group: Self.sudEsteAsiatico)
        }
        .padding(.horizontal, 16)
    }

        // América subregions
    private static let norteamerica: Set<String> = ["USA","CAN","MEX"]
    private static let centroamerica: Set<String> = ["GTM","BLZ","HND","SLV","NIC","CRI","PAN"]
    private static let sudamerica: Set<String> = [
        "COL","VEN","GUY","SUR","BRA","ECU","PER","BOL","CHL","ARG","URY","PRY","FLK"
    ]
    private static let caribe: Set<String> = [
        "CUB","JAM","HTI","DOM","PRI","TTO","BRB","LCA","VCT","GRD","ATG","DMA","KNA",
        "ABW","AIA","BMU","VGB","CYM","CUW","MSR","BLM","MAF","SPM","SXM","TCA","VIR"
    ]

    // África subregions
    private static let sahel: Set<String> = [
        "MRT","MLI","NER","TCD","SDN","BFA","SEN","GMB","GNB","ERI","ETH","SOM","DJI"
    ]
    private static let norteafrica: Set<String> = [
        "MAR","DZA","TUN","LBY","EGY","SDN","SAH"
    ]
    private static let safaris: Set<String> = [
        "KEN","TZA","ZAF","BWA","ZWE","ZMB","UGA","RWA","NAM","MOZ","ETH","TGO"
    ]
    private static let insularesAfrica: Set<String> = [
        "CPV","COM","MDG","MUS","SYC","STP"
    ]

    // Oceanía subregions
    // Solo una isla (o isla principal única): Nauru, Niue
    private static let soloUnaIsla: Set<String> = ["NRU","NIU"]

        // Medio Oriente subregions
    private static let paisesArabesMO: Set<String> = [
        "SAU","YEM","IRQ","SYR","JOR","LBN","KWT","BHR","QAT","ARE","OMN","PSE","PSX"
    ]
    private static let petrolerosMO: Set<String> = [
        "SAU","IRQ","IRN","KWT","ARE","QAT","BHR","OMN"
    ]
    private static let historicosMO: Set<String> = [
        "IRQ","IRN","TUR","PSE","PSX","JOR","SYR","LBN","YEM","OMN"
    ]
    // F1 actuales Medio Oriente (Bahréin, Arabia Saudí, Abu Dhabi, Qatar)
    private static let f1MO: Set<String> = ["BHR","SAU","ARE","QAT"]

        private static let ue: Set<String> = [
        "DEU","FRA","ITA","ESP","PRT","NLD","BEL","LUX","AUT","FIN","SWE","IRL",
        "GRC","CYP","MLT","EST","LVA","LTU","POL","CZE","SVK","HUN","ROU","BGR",
        "HRV","SVN","DNK"
    ]
    private static let nordicos: Set<String> = ["NOR","SWE","FIN","DNK","ISL"]
    private static let microestados: Set<String> = ["AND","MCO","SMR","VAT","LIE","MLT"]
    private static let balcanes: Set<String> = [
        "SRB","BIH","MNE","ALB","MKD","KOS","SVN","HRV","GRC","BGR","ROU"
    ]

    private func visitedCount(in group: Set<String>) -> (visited: Int, total: Int) {
        let mode = CountingMode(rawValue: countingModeRaw) ?? .all
        let validCodes = group.filter { mode.counts($0) }
        let visited = visitedCountries.filter { validCodes.contains($0.isoCode) }.count
        return (visited, validCodes.count)
    }

    @ViewBuilder
    private func africaStatsView() -> some View {
        let sahel     = visitedCount(in: Self.sahel)
        let norte     = visitedCount(in: Self.norteafrica)
        let safaris   = visitedCount(in: Self.safaris)
        let insulares = visitedCount(in: Self.insularesAfrica)

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statTile(title: "Sahel",          visited: sahel.visited,     total: sahel.total,     emoji: "🏜️", group: Self.sahel)
            statTile(title: "Norte de África",visited: norte.visited,     total: norte.total,     emoji: "🐪", group: Self.norteafrica)
            statTile(title: "Safaris",        visited: safaris.visited,   total: safaris.total,   emoji: "🦁", group: Self.safaris)
            statTile(title: "Insulares",      visited: insulares.visited, total: insulares.total, emoji: "🌊", group: Self.insularesAfrica)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func oceaniaStatsView() -> some View {
        let unaIsla = visitedCount(in: Self.soloUnaIsla)
        VStack(spacing: 6) {
            statTile(title: "Solo una isla", visited: unaIsla.visited, total: unaIsla.total, emoji: "🏝️", group: Self.soloUnaIsla)
                .frame(maxWidth: 180)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func americaStatsView() -> some View {
        let norte  = visitedCount(in: Self.norteamerica)
        let centro = visitedCount(in: Self.centroamerica)
        let sur    = visitedCount(in: Self.sudamerica)
        let caribe = visitedCount(in: Self.caribe)

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statTile(title: "Norteamérica",   visited: norte.visited,  total: norte.total,  emoji: "🦅", group: Self.norteamerica)
            statTile(title: "Centroamérica",  visited: centro.visited, total: centro.total, emoji: "🌋", group: Self.centroamerica)
            statTile(title: "Sudamérica",     visited: sur.visited,    total: sur.total,    emoji: "🌿", group: Self.sudamerica)
            statTile(title: "Caribe",         visited: caribe.visited, total: caribe.total, emoji: "🏖️", group: Self.caribe)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func medioOrienteStatsView() -> some View {
        let arabes    = visitedCount(in: Self.paisesArabesMO)
        let petroleo  = visitedCount(in: Self.petrolerosMO)
        let historicos = visitedCount(in: Self.historicosMO)
        let f1        = visitedCount(in: Self.f1MO)

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statTile(title: "Países árabes",  visited: arabes.visited,     total: arabes.total,     emoji: "🕌", group: Self.paisesArabesMO)
            statTile(title: "Petroleros",     visited: petroleo.visited,   total: petroleo.total,   emoji: "🛢️", group: Self.petrolerosMO)
            statTile(title: "Históricos",     visited: historicos.visited, total: historicos.total, emoji: "🏛️", group: Self.historicosMO)
            statTile(title: "F1",             visited: f1.visited,         total: f1.total,         emoji: "🏎️", group: Self.f1MO)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func europaStatsView() -> some View {
        let ue = visitedCount(in: Self.ue)
        let nord = visitedCount(in: Self.nordicos)
        let micro = visitedCount(in: Self.microestados)
        let balc = visitedCount(in: Self.balcanes)

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statTile(title: "Unión Europea", visited: ue.visited, total: ue.total, emoji: "🇪🇺", group: Self.ue)
            statTile(title: "Países nórdicos", visited: nord.visited, total: nord.total, emoji: "❄️", group: Self.nordicos)
            statTile(title: "Microestados", visited: micro.visited, total: micro.total, emoji: "🏰", group: Self.microestados)
            statTile(title: "Balcanes", visited: balc.visited, total: balc.total, emoji: "⛰️", group: Self.balcanes)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func statTile(title: String, visited: Int, total: Int, emoji: String,
                           group: Set<String> = []) -> some View {
        Button {
            if !group.isEmpty {
                selectedSubgroup = SubgroupInfo(title: title, emoji: emoji, isoCodes: group)
            }
        } label: {
            VStack(spacing: 4) {
                Text(emoji)
                    .font(.title2)
                Text("\(visited)/\(total)")
                    .font(.palatino(.title3, weight: .bold))
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // Subgroup sheet model
    struct SubgroupInfo: Identifiable {
        let id = UUID()
        let title: String
        let emoji: String
        let isoCodes: Set<String>
    }

            @ViewBuilder
    private func zoneButton(_ zone: ExportZone) -> some View {
        Button {
            selectedZone = zone
            renderedImage = nil
            isRendering = true
        } label: {
            Text(zone.rawValue)
                .font(.palatino(.footnote, weight: selectedZone == zone ? .bold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(selectedZone == zone ? Color.blue : Color(.systemGray5), in: Capsule())
                .foregroundStyle(selectedZone == zone ? .white : .primary)
        }
    }

        private func renderMap() {
        isRendering = true
        let size = CGSize(width: 800, height: 800)
        let region = selectedZone.region

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.scale = 2.0
        options.mapType = .standard
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false

        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { snapshot, error in
            guard let snapshot else { return }

            let countingMode = CountingMode(rawValue: countingModeRaw) ?? .all
            let zoneDenominator = selectedZone.denominator(mode: countingMode)
            // Numerator: only countries that pass the countingMode filter
            let zoneVisited = filteredCountries.filter { countingMode.counts($0.isoCode) }.count
            let zoneCounter = "\(zoneVisited)/\(zoneDenominator)"

            let annotations: [(coord: CLLocationCoordinate2D, emoji: String)] = filteredCountries.compactMap { country in
                guard countingMode.counts(country.isoCode),
                      let feature = features.first(where: { $0.isoCode == country.isoCode }),
                      let emoji = feature.flagEmoji else { return nil }
                let coord = capitalCoord(for: country.isoCode, feature: feature)
                return (coord, emoji)
            }

            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { ctx in
                snapshot.image.draw(at: .zero)

                for ann in annotations {
                    let point = snapshot.point(for: ann.coord)
                    guard point.x >= 0 && point.x <= size.width &&
                          point.y >= 0 && point.y <= size.height else { continue }
                    drawBalloon(emoji: ann.emoji, at: point, in: ctx.cgContext, imageSize: size)
                }

                // Contador centrado abajo
                let text = zoneCounter as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont(name: "Palatino-Bold", size: 22) ?? .boldSystemFont(ofSize: 22),
                    .foregroundColor: UIColor.white
                ]
                let textSize = text.size(withAttributes: attrs)
                let pad: CGFloat = 12
                let bgW = textSize.width + pad * 2
                let bgX = (size.width - bgW) / 2
                let bgRect = CGRect(x: bgX, y: size.height - textSize.height - pad * 2 - 16,
                                    width: bgW, height: textSize.height + pad * 2)
                let path = UIBezierPath(roundedRect: bgRect, cornerRadius: 10)
                UIColor.black.withAlphaComponent(0.55).setFill()
                path.fill()
                text.draw(at: CGPoint(x: bgRect.minX + pad, y: bgRect.minY + pad), withAttributes: attrs)
            }

            DispatchQueue.main.async {
                renderedImage = image
                isRendering = false
            }
        }
    }

    private func drawBalloon(emoji: String, at point: CGPoint, in ctx: CGContext, imageSize: CGSize) {
        let label = UILabel()
        label.text = emoji
        label.font = .systemFont(ofSize: 20)
        label.sizeToFit()

        let pad: CGFloat = 5
        let cornerRadius: CGFloat = 8
        let tailH: CGFloat = 8
        let boxW = label.frame.width + pad * 2
        let boxH = label.frame.height + pad * 2
        let totalH = boxH + tailH

        // Position: center box above the point
        let boxX = point.x - boxW / 2
        let boxY = point.y - totalH

        // Clamp to image bounds
        let clampedX = min(max(boxX, 2), imageSize.width - boxW - 2)
        let clampedY = max(boxY, 2)

        // Draw balloon path
        let rect = CGRect(x: clampedX, y: clampedY, width: boxW, height: boxH)
        let path = UIBezierPath()
        // Top-left → top-right (top edge)
        path.move(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        // Top-right corner
        path.addArc(withCenter: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
                    radius: cornerRadius, startAngle: -.pi/2, endAngle: 0, clockwise: true)
        // Right edge down to bottom-right corner start
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        // Bottom-right corner
        path.addArc(withCenter: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius),
                    radius: cornerRadius, startAngle: 0, endAngle: .pi/2, clockwise: true)

        // Bottom edge with tail
        let tailTipX = min(max(point.x, clampedX + cornerRadius), clampedX + boxW - cornerRadius)
        path.addLine(to: CGPoint(x: tailTipX + 5, y: rect.maxY))
        path.addLine(to: CGPoint(x: tailTipX, y: rect.maxY + tailH))
        path.addLine(to: CGPoint(x: tailTipX - 5, y: rect.maxY))

        // Continue bottom edge to bottom-left corner start
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        // Bottom-left corner
        path.addArc(withCenter: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
                    radius: cornerRadius, startAngle: .pi/2, endAngle: .pi, clockwise: true)
        // Left edge up to top-left corner start
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        // Top-left corner
        path.addArc(withCenter: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
                    radius: cornerRadius, startAngle: .pi, endAngle: -.pi/2, clockwise: true)
        path.close()

        UIColor.white.setFill()
        path.fill()
        UIColor.lightGray.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 0.8
        path.stroke()

        // Draw emoji
        let emojiRect = CGRect(x: clampedX + pad, y: clampedY + pad,
                               width: label.frame.width, height: label.frame.height)
        (emoji as NSString).draw(in: emojiRect, withAttributes: [
            .font: UIFont.systemFont(ofSize: 20)
        ])
    }
}


// MARK: - Lista de subgrupo (visitados arriba, pendientes abajo en gris)
struct SubgroupListSheet: View {
    let title: String
    let emoji: String
    let isoCodes: Set<String>
    let visitedCountries: [Country]
    let features: [CountryFeature]
    let countingModeRaw: String
    let trips: [Trip]

    @Environment(\.dismiss) private var dismiss

    private var mode: CountingMode { CountingMode(rawValue: countingModeRaw) ?? .all }

    private var validCodes: Set<String> {
        isoCodes.filter { mode.counts($0) }
    }

    private var visitedIsoCodes: Set<String> {
        Set(visitedCountries.map { $0.isoCode })
    }

    private func flagEmoji(for isoCode: String) -> String {
        features.first(where: { $0.isoCode == isoCode })?.flagEmoji ?? "🌐"
    }

    private func name(for isoCode: String) -> String {
        features.first(where: { $0.isoCode == isoCode })?.localizedName ?? isoCode
    }

    private var visited: [String] {
        validCodes.filter { visitedIsoCodes.contains($0) }
            .sorted { name(for: $0) < name(for: $1) }
    }

    private var pending: [String] {
        validCodes.filter { !visitedIsoCodes.contains($0) }
            .sorted { name(for: $0) < name(for: $1) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !visited.isEmpty {
                    Section(header: Text("Visitados (\(visited.count))")
                        .font(.palatino(.caption, weight: .bold))) {
                        ForEach(visited, id: \.self) { iso in
                            HStack(spacing: 10) {
                                Text(flagEmoji(for: iso))
                                    .font(.title3)
                                Text(name(for: iso))
                                    .font(.palatino(.body))
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                if !pending.isEmpty {
                    Section(header: Text("Pendientes (\(pending.count))")
                        .font(.palatino(.caption, weight: .bold))
                        .foregroundStyle(.secondary)) {
                        ForEach(pending, id: \.self) { iso in
                            HStack(spacing: 10) {
                                Text(flagEmoji(for: iso))
                                    .font(.title3)
                                    .opacity(0.4)
                                Text(name(for: iso))
                                    .font(.palatino(.body))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("\(emoji) \(title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                        .font(.palatino(.body))
                }
            }
        }
        .presentationDetents([.large])
    }
}


// MARK: - Editar fechas de viaje desde lista de visitados
struct AddTripSheet: View {
    let isoCode: String
    let displayName: String
    let flagEmoji: String
    let onSave: (Trip) -> Void
    var onCancel: (() -> Void)? = nil

    @State private var didSave = false
    @Environment(\.dismiss) private var dismiss
    @State private var tripTitle: String = ""
    @State private var dateFrom: Date = Date()
    @State private var dateTo: Date? = nil
    @State private var pickingFrom: Bool = true
    @State private var selectedTransport: String? = nil
    @State private var selectedAirports: [TripAirport] = []
    @State private var selectedAirlines: [AirlineData] = []
    @State private var airlineCounts: [String: Int] = [:]
    @State private var showAirportPicker = false
    @State private var showAirlinePicker = false

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.locale = Locale(identifier: "es_ES"); return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: 0) {
                Text("\(flagEmoji) \(displayName)")
                    .font(.palatino(.title3, weight: .bold))
                    .padding(.top, 12).padding(.bottom, 4)

                TextField("Título del viaje *", text: $tripTitle)
                    .font(.palatino(.body))
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16).padding(.bottom, 8)

                HStack(spacing: 8) {
                    ForEach(PlannedDatePickerSheet.transports, id: \.emoji) { t in
                        Button { selectedTransport = selectedTransport == t.emoji ? nil : t.emoji } label: {
                            VStack(spacing: 2) {
                                Text(t.emoji).font(.title3)
                                Text(t.label).font(.system(size: 9))
                                    .foregroundStyle(selectedTransport == t.emoji ? .white : .secondary)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(selectedTransport == t.emoji ? Color.blue : Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 8)

                // Airport + Airlines (only for ✈️)
                if selectedTransport == "✈️" {
                    VStack(spacing: 8) {
                        Button { showAirportPicker = true } label: {
                            HStack {
                                Text(selectedAirports.isEmpty ? "Aeropuerto(s) de destino *" : selectedAirports.map { "\($0.iata)\($0.roundTrip ? " (I/V)" : "")" }.joined(separator: ", "))
                                    .font(.palatino(.body))
                                    .foregroundStyle(selectedAirports.isEmpty ? .secondary : .primary)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)

                        Button { showAirlinePicker = true } label: {
                            HStack {
                                if selectedAirlines.isEmpty {
                                    Text("Aerolínea(s) *")
                                        .font(.palatino(.body)).foregroundStyle(.secondary)
                                } else {
                                    Text(selectedAirlines.map { $0.name }.joined(separator: ", "))
                                        .font(.palatino(.body)).foregroundStyle(.primary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)

                        // Manual count steppers for multi-airline
                        if selectedAirlines.count > 1 {
                            VStack(spacing: 0) {
                                ForEach(selectedAirlines, id: \.iata) { al in
                                    HStack {
                                        Text(al.name).font(.palatino(.caption)).foregroundStyle(.primary)
                                        Spacer()
                                        Stepper("", value: Binding(
                                            get: { airlineCounts[al.name] ?? 0 },
                                            set: { airlineCounts[al.name] = $0 }
                                        ), in: 0...20)
                                        .labelsHidden()
                                        Text("\(airlineCounts[al.name] ?? 0)")
                                            .font(.palatino(.caption, weight: .bold))
                                            .frame(width: 20, alignment: .trailing)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 6)
                                    if al.iata != selectedAirlines.last?.iata { Divider().padding(.leading, 16) }
                                }
                            }
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 8)
                } else {
                    Color.clear.frame(height: 16)
                }

                HStack(spacing: 0) {
                    ForEach([(true, "DESDE", Self.fmt.string(from: dateFrom)),
                             (false, "HASTA", dateTo.map { Self.fmt.string(from: $0) } ?? "Sin vuelta")], id: \.1) { isFrom, label, value in
                        Button { pickingFrom = isFrom } label: {
                            VStack(spacing: 2) {
                                Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                                Text(value).font(.palatino(.subheadline, weight: .bold))
                                    .foregroundStyle(pickingFrom == isFrom ? .blue : (isFrom ? .primary : (dateTo == nil ? .secondary : .primary)))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(pickingFrom == isFrom ? Color.blue.opacity(0.08) : Color.clear)
                            .overlay(alignment: .bottom) { if pickingFrom == isFrom { Rectangle().fill(Color.blue).frame(height: 2) } }
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)

                RangeDatePicker(dateFrom: $dateFrom, dateTo: $dateTo, pickingFrom: $pickingFrom)
                    .padding(.horizontal, 8)

                let isPlane = selectedTransport == "✈️"
                let canSave = selectedTransport != nil && !tripTitle.isEmpty &&
                              (!isPlane || (!selectedAirports.isEmpty && !selectedAirlines.isEmpty))
                Button {
                    let trimmed = tripTitle.trimmingCharacters(in: .whitespaces)
                    let trip = Trip(isoCode: isoCode, title: trimmed.isEmpty ? nil : trimmed,
                                   dateFrom: dateFrom, dateTo: dateTo, transport: selectedTransport,
                                   tripAirports: selectedAirports, airlines: selectedAirlines.map { $0.name },
                                   airlineCounts: selectedAirlines.count > 1 ? airlineCounts : [:])
                    didSave = true
                    onSave(trip)
                    dismiss()
                } label: {
                    Text("Guardar viaje")
                        .font(.palatino(.body, weight: .bold)).frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canSave ? Color.blue : Color(.systemGray4), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .disabled(!canSave)
                .padding(.horizontal, 24).padding(.bottom, 24)
            } // end VStack
            } // end ScrollView
            .navigationTitle("➕ Añadir viaje")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        onCancel?()
                        dismiss()
                    }.font(.palatino(.body))
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(false)
        .onDisappear {
            if !didSave { onCancel?() }
        }
        .sheet(isPresented: $showAirportPicker) {
            AirportPickerSheet(selected: $selectedAirports)
        }
        .sheet(isPresented: $showAirlinePicker) {
            AirlinePickerSheet(selected: $selectedAirlines)
        }
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

    private let transports = PlannedDatePickerSheet.transports

    private var pastTrips: [Trip] {
        let today = Calendar.current.startOfDay(for: Date())
        return trips.filter { Calendar.current.startOfDay(for: $0.dateFrom) <= today }
    }

    private var counts: [(emoji: String, label: String, count: Int)] {
        transports.map { t in
            let matchEmojis: Set<String> = t.emoji == "🚶🏻" ? ["🚶🏻", "🚶"] : [t.emoji]
            let fromTrips = pastTrips.filter { matchEmojis.contains($0.transport ?? "") }.count
            let fromCountry = visitedCountries.filter { matchEmojis.contains($0.transport ?? "") }.count
            return (t.emoji, t.label, fromTrips + fromCountry)
        }.filter { $0.count > 0 }
        .sorted { $0.count > $1.count }
    }

    private var totalTrips: Int { pastTrips.count }

    // Top airports by count
    private var topAirports: [(iata: String, name: String, country: String, count: Int)] {
        var counts: [String: Int] = [:]
        var lastDate: [String: Date] = [:]
        for trip in pastTrips where trip.transport == "✈️" {
            for (iata, cnt) in trip.airportCountForStats {
                counts[iata, default: 0] += cnt
                if let prev = lastDate[iata] { if trip.dateFrom > prev { lastDate[iata] = trip.dateFrom } }
                else { lastDate[iata] = trip.dateFrom }
            }
        }
        return counts.map { iata, count -> (iata: String, name: String, country: String, count: Int) in
            let ap = AirportPickerSheet.airports.first { $0.iata == iata }
            return (iata, ap?.name ?? iata, ap?.country ?? "", count)
        }.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return (lastDate[$0.iata] ?? .distantPast) > (lastDate[$1.iata] ?? .distantPast)
        }
    }

    private var topAirlines: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        var lastDate: [String: Date] = [:]
        for trip in pastTrips where trip.transport == "✈️" {
            let als = trip.airlines
            guard !als.isEmpty else { continue }
            for al in als {
                let increment = trip.countForAirline(al)
                counts[al, default: 0] += increment
                if let prev = lastDate[al] { if trip.dateFrom > prev { lastDate[al] = trip.dateFrom } }
                else { lastDate[al] = trip.dateFrom }
            }
        }
        return counts.map { ($0.key, $0.value) }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return (lastDate[$0.0] ?? .distantPast) > (lastDate[$1.0] ?? .distantPast)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // ── Gráfica centrada ──
                    VStack(spacing: 4) {
                        Text("\(totalTrips)")
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                        Text("total viajes")
                            .font(.palatino(.subheadline)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

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
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 32)
                    }

                    // ── Cuadrantes aeropuertos / aerolíneas ──
                    if !topAirports.isEmpty || !topAirlines.isEmpty {
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
                                                    Text(flagEmoji(a2)).font(.caption)
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
                    }

                    Spacer(minLength: 24)
                }
            }
            .navigationTitle("🚀 Transporte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
            .sheet(item: Binding(
                get: { selectedTransportFilter.map { TransportFilter(emoji: $0.0, label: $0.1) } },
                set: { _ in selectedTransportFilter = nil }
            )) { filter in
                TransportTripsListSheet(transportEmoji: filter.emoji, transportLabel: filter.label, trips: trips, allFeatures: allFeatures)
            }
            .sheet(isPresented: $showAirportStats) {
                AirportStatsSheet(airports: topAirports, allFeatures: allFeatures)
            }
            .sheet(isPresented: $showAirlineStats) {
                AirlineStatsSheet(airlines: topAirlines)
            }
        }
        .presentationDetents([.large])
    }

    private func countryA2(_ iso2: String) -> String? { iso2.count == 2 ? iso2 : nil }
    private func flagEmoji(_ a2: String) -> String {
        a2.uppercased().unicodeScalars.compactMap {
            Unicode.Scalar(127397 + $0.value).map { String($0) }
        }.joined()
    }
}

struct TransportFilter: Identifiable {
    let id = UUID()
    let emoji: String
    let label: String
}


// MARK: - Historial de viajes de un país
struct CountryTripsSheet: View {
    @Bindable var country: Country
    let trips: [Trip]
    let displayName: String
    let flagEmoji: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete: Trip? = nil
    @State private var showDeleteConfirm: Bool = false
    @State private var editingTrip: Trip? = nil

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.locale = Locale(identifier: "es_ES"); return f
    }()

    private var sortedTrips: [Trip] {
        trips.sorted { $0.effectiveEndDate > $1.effectiveEndDate }
    }

    var body: some View {
        NavigationStack {
            List {
                // Manual visit count section (not for lived)
                if country.status != .lived {
                    Section(header: Text("Visitas manuales").font(.palatino(.caption, weight: .bold))) {
                        HStack {
                            Text("Contador manual")
                                .font(.palatino(.body))
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
            .confirmationDialog("¿Eliminar este viaje?", isPresented: $showDeleteConfirm, presenting: confirmDelete) { trip in
                Button("Eliminar", role: .destructive) {
                    modelContext.delete(trip)
                    try? modelContext.save()
                }
                Button("Cancelar", role: .cancel) {}
            } message: { trip in
                Text("\(Self.fmt.string(from: trip.dateFrom))\(trip.dateTo.map { " → \(Self.fmt.string(from: $0))" } ?? "")")
            }
            .sheet(item: $editingTrip) { trip in
                EditTripSheet(trip: trip)
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func tripRow(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(trip.transport ?? "🌐").font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    if let t = trip.title, !t.isEmpty {
                        HStack(spacing: 6) {
                            Text(t).font(.palatino(.body, weight: .bold))
                            Text("|").foregroundStyle(.secondary)
                            Text(Self.fmt.string(from: trip.dateFrom))
                                .font(.palatino(.body)).foregroundStyle(.secondary)
                        }
                    } else {
                        Text(Self.fmt.string(from: trip.dateFrom)).font(.palatino(.body))
                    }
                    if let to = trip.dateTo {
                        Text("→ \(Self.fmt.string(from: to))")
                            .font(.palatino(.caption)).foregroundStyle(.secondary)
                    }
                    if trip.transport == "✈️" {
                        let aps = trip.airports
                        let als = trip.airlines
                        if !aps.isEmpty || !als.isEmpty {
                            HStack(spacing: 6) {
                                if !aps.isEmpty {
                                    Text(aps.joined(separator: ", "))
                                        .font(.palatino(.caption, weight: .bold)).foregroundStyle(.blue)
                                }
                                if !als.isEmpty {
                                    Text(als.joined(separator: ", "))
                                        .font(.palatino(.caption)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                }
                Spacer()
                Button { confirmDelete = trip; showDeleteConfirm = true } label: {
                    Image(systemName: "trash").foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain).frame(width: 28)
            }
            Button { editingTrip = trip } label: {
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
        return trips.filter { matchEmojis.contains($0.transport ?? "") &&
            Calendar.current.startOfDay(for: $0.dateFrom) <= today }
             .sorted { $0.dateFrom > $1.dateFrom }
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
                    Text(flagEmoji(for: trip.isoCode)).font(.title3)
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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var dateFrom: Date
    @State private var dateTo: Date?
    @State private var pickingFrom: Bool = true
    @State private var selectedTransport: String?
    @State private var tripTitle: String
    @State private var selectedAirports: [TripAirport] = []
    @State private var selectedAirlines: [AirlineData] = []
    @State private var airlineCounts: [String: Int] = [:]
    @State private var showAirportPicker = false
    @State private var showAirlinePicker = false

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.locale = Locale(identifier: "es_ES"); return f
    }()

    init(trip: Trip) {
        self.trip = trip
        _dateFrom = State(initialValue: trip.dateFrom)
        _dateTo = State(initialValue: trip.dateTo)
        _selectedTransport = State(initialValue: trip.transport)
        _tripTitle = State(initialValue: trip.title ?? "")
        // Load airports if exist
        _selectedAirports = State(initialValue: trip.tripAirports)
        let savedAirlines = trip.airlines.compactMap { name in
            AirlinePickerSheet.airlines.first { $0.name == name }
        }
        _selectedAirlines = State(initialValue: savedAirlines)
        _airlineCounts = State(initialValue: trip.airlineCounts)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: 0) {
                TextField("Título del viaje *", text: $tripTitle)
                    .font(.palatino(.body))
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16).padding(.vertical, 8)

                HStack(spacing: 8) {
                    ForEach(PlannedDatePickerSheet.transports, id: \.emoji) { t in
                        Button { selectedTransport = selectedTransport == t.emoji ? nil : t.emoji } label: {
                            VStack(spacing: 2) {
                                Text(t.emoji).font(.title3)
                                Text(t.label).font(.system(size: 9))
                                    .foregroundStyle(selectedTransport == t.emoji ? .white : .secondary)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(selectedTransport == t.emoji ? Color.blue : Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 8)

                // Airport + Airlines (only for ✈️)
                if selectedTransport == "✈️" {
                    VStack(spacing: 8) {
                        Button { showAirportPicker = true } label: {
                            HStack {
                                Text(selectedAirports.isEmpty ? "Aeropuerto(s) de destino *" : selectedAirports.map { "\($0.iata)\($0.roundTrip ? " (I/V)" : "")" }.joined(separator: ", "))
                                    .font(.palatino(.body))
                                    .foregroundStyle(selectedAirports.isEmpty ? .secondary : .primary)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)

                        Button { showAirlinePicker = true } label: {
                            HStack {
                                if selectedAirlines.isEmpty {
                                    Text("Aerolínea(s) *")
                                        .font(.palatino(.body)).foregroundStyle(.secondary)
                                } else {
                                    Text(selectedAirlines.map { $0.name }.joined(separator: ", "))
                                        .font(.palatino(.body)).foregroundStyle(.primary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)

                        // Manual count steppers for multi-airline
                        if selectedAirlines.count > 1 {
                            VStack(spacing: 0) {
                                ForEach(selectedAirlines, id: \.iata) { al in
                                    HStack {
                                        Text(al.name).font(.palatino(.caption)).foregroundStyle(.primary)
                                        Spacer()
                                        Stepper("", value: Binding(
                                            get: { airlineCounts[al.name] ?? 0 },
                                            set: { airlineCounts[al.name] = $0 }
                                        ), in: 0...20)
                                        .labelsHidden()
                                        Text("\(airlineCounts[al.name] ?? 0)")
                                            .font(.palatino(.caption, weight: .bold))
                                            .frame(width: 20, alignment: .trailing)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 6)
                                    if al.iata != selectedAirlines.last?.iata { Divider().padding(.leading, 16) }
                                }
                            }
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 8)
                } else {
                    Color.clear.frame(height: 16)
                }

                HStack(spacing: 0) {
                    ForEach([(true, "DESDE", Self.fmt.string(from: dateFrom)),
                             (false, "HASTA", dateTo.map { Self.fmt.string(from: $0) } ?? "Sin vuelta")], id: \.1) { isFrom, label, value in
                        Button { pickingFrom = isFrom } label: {
                            VStack(spacing: 2) {
                                Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                                Text(value).font(.palatino(.subheadline, weight: .bold))
                                    .foregroundStyle(pickingFrom == isFrom ? .blue : (isFrom ? .primary : (dateTo == nil ? .secondary : .primary)))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(pickingFrom == isFrom ? Color.blue.opacity(0.08) : Color.clear)
                            .overlay(alignment: .bottom) { if pickingFrom == isFrom { Rectangle().fill(Color.blue).frame(height: 2) } }
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                RangeDatePicker(dateFrom: $dateFrom, dateTo: $dateTo, pickingFrom: $pickingFrom)
                    .padding(.horizontal, 8)
                    .frame(height: 340)
                    .padding(.bottom, 16)

                Button {
                    trip.dateFrom = dateFrom
                    trip.dateTo = dateTo
                    trip.transport = selectedTransport
                    let trimmedTitle = tripTitle.trimmingCharacters(in: .whitespaces)
                    trip.title = trimmedTitle.isEmpty ? nil : trimmedTitle
                    trip.tripAirports = selectedAirports
                    trip.airlines = selectedAirlines.map { $0.name }
                    trip.airlineCounts = selectedAirlines.count > 1 ? airlineCounts : [:]
                    try? modelContext.save()
                    dismiss()
                } label: {
                    Text("Guardar cambios")
                        .font(.palatino(.body, weight: .bold)).frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(selectedTransport != nil && !tripTitle.isEmpty ? Color.blue : Color(.systemGray4),
                                    in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .disabled(selectedTransport == nil || tripTitle.isEmpty)
                .padding(.horizontal, 24).padding(.bottom, 24)
            } // end VStack
            } // end ScrollView
            .navigationTitle("✏️ Editar viaje")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .presentationDetents([.large])
        .sheet(isPresented: $showAirportPicker) {
            AirportPickerSheet(selected: $selectedAirports)
        }
        .sheet(isPresented: $showAirlinePicker) {
            AirlinePickerSheet(selected: $selectedAirlines)
        }
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

// MARK: - Selector de imagen del sistema
struct ImagePickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerView
        init(_ parent: ImagePickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Country.self, inMemory: true)
}

// MARK: - Extensión para aplicar Palatino respetando los tamaños del sistema
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
        case .bold:        return .custom("Palatino-Bold", size: size)
        case .semibold:    return .custom("Palatino-Bold", size: size)
        default:           return .custom("Palatino", size: size)
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
}

struct AirlineData: Identifiable, Codable, Hashable {
    var id: String { iata }
    let iata: String
    let name: String
    let country: String
}

// MARK: - Airport picker
struct AirportPickerSheet: View {
    @Binding var selected: [TripAirport]
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    static let airports: [AirportData] = {
        guard let url = Bundle.main.url(forResource: "airports", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([AirportData].self, from: data) else { return [] }
        return arr.sorted { $0.name < $1.name }
    }()

    private var filtered: [AirportData] {
        if query.isEmpty { return Self.airports }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return Self.airports.filter {
            $0.iata.range(of: query, options: opts) != nil ||
            $0.name.range(of: query, options: opts) != nil ||
            $0.city.range(of: query, options: opts) != nil
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Selected airports with roundtrip toggle
                if !selected.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(selected, id: \.iata) { tripAp in
                            let ap = AirportPickerSheet.airports.first { $0.iata == tripAp.iata }
                            HStack(spacing: 10) {
                                Text(ap?.flagEmoji ?? "🌐").font(.title3)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(tripAp.iata) – \(ap?.name ?? tripAp.iata)")
                                        .font(.palatino(.caption, weight: .bold))
                                    Text(ap?.city ?? "").font(.palatino(.caption2)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                HStack(spacing: 4) {
                                    Text(tripAp.roundTrip ? "I/V" : "Ida")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Toggle("", isOn: Binding(
                                        get: { tripAp.roundTrip },
                                        set: { newVal in
                                            if let idx = selected.firstIndex(where: { $0.iata == tripAp.iata }) {
                                                selected[idx].roundTrip = newVal
                                            }
                                        }
                                    ))
                                    .labelsHidden()
                                    .tint(.blue)
                                }
                                Button {
                                    selected.removeAll { $0.iata == tripAp.iata }
                                } label: {
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
                    let isSelected = selected.contains(where: { $0.iata == ap.iata })
                    Button {
                        if let idx = selected.firstIndex(where: { $0.iata == ap.iata }) {
                            selected.remove(at: idx)
                        } else {
                            selected.append(TripAirport(iata: ap.iata, roundTrip: false))
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Text(ap.flagEmoji).font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(ap.iata).font(.palatino(.subheadline, weight: .bold))
                                    Text(ap.name).font(.palatino(.body)).foregroundStyle(.primary)
                                }
                                Text(ap.city).font(.palatino(.caption)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .searchable(text: $query, prompt: "Buscar aeropuerto o IATA")

                Button { dismiss() } label: {
                    Text(selected.isEmpty ? "Listo" : "Listo (\(selected.count) aeropuerto\(selected.count == 1 ? "" : "s"))")
                        .font(.palatino(.body, weight: .bold)).frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(Color(.systemBackground))
            }
            .navigationTitle("Aeropuerto(s)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Airline picker (multi-select)
struct AirlinePickerSheet: View {
    @Binding var selected: [AirlineData]
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    static let airlines: [AirlineData] = {
        guard let url = Bundle.main.url(forResource: "airlines", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([AirlineData].self, from: data) else { return [] }
        return arr.sorted { $0.name < $1.name }
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
                List(filtered) { al in
                    Button {
                        if let idx = selected.firstIndex(where: { $0.iata == al.iata }) {
                            selected.remove(at: idx)
                        } else {
                            selected.append(al)
                        }
                    } label: {
                        HStack {
                            Text(al.name).font(.palatino(.body)).foregroundStyle(.primary)
                            Spacer()
                            if selected.contains(where: { $0.iata == al.iata }) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .searchable(text: $query, prompt: "Buscar aerolínea")

                // Sticky Listo button always visible
                Button { dismiss() } label: {
                    Text(selected.isEmpty ? "Listo" : "Listo (\(selected.count) seleccionada\(selected.count == 1 ? "" : "s"))")
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
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
                    Text(flagEmoji(ap.country)).font(.title3)
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
