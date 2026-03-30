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
import MessageUI

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
    @AppStorage("showBucketList") private var showBucketList: Bool = true
    @AppStorage("showCountdown")  private var showCountdown: Bool = true
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
        HStack(spacing: 8) {
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
                HStack(spacing: 10) {
                    Button { showProfile = true } label: {
                        HStack(spacing: 10) {
                            ProfileAvatarView(image: profileImage, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Raskmap")
                                    .font(.palatino(.title3, weight: .bold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if !username.isEmpty {
                                    Text("@\(username)")
                                        .font(.palatino(.subheadline))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                    badgesRow().fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
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
                HStack(spacing: 10) {
                    Button { showProfile = true } label: {
                        HStack(spacing: 10) {
                            ProfileAvatarView(image: profileImage, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Raskmap")
                                    .font(.palatino(.title3, weight: .bold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if !username.isEmpty {
                                    Text("@\(username)")
                                        .font(.palatino(.subheadline))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                    badgesRow().fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
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
                    if country.status == .visited || country.status == .lived { return country.isoCode }
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
                showBucketList: showBucketList,
                locationIsoCode: locationIsoCode,
                onReady: { mapStore.centerOnCountry = $0 }
            )
            .ignoresSafeArea()
            menuOverlay()
                .ignoresSafeArea(.keyboard)

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
            showBucketList: $showBucketList,
            showCountdown: $showCountdown,
            onClearStatus: { status in
                for country in countries where country.status == status { country.status = .none }
                try? modelContext.save()
            },
            topTable: $topTable,
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
            break
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
            .padding(.top, 28)

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

// MARK: - Logros
enum AchievementKind: CaseIterable {
    // Especiales
    case firstTrip, firstLayover, trips100, allWorld
    // Trophy
    case visitedAntarctica
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
    // Plata – 5 viajes en la región
    case fiveEurope, fiveAsia, fiveAfrica, fiveMedioOriente, fiveOceania
    case fiveNortamerica, fiveCaribe, fiveSudamerica, fiveCentroamerica

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
        case .fiveEurope:           return "Cinco veces en Europa"
        case .fiveAsia:             return "Cinco veces en Asia"
        case .fiveAfrica:           return "Cinco veces en África"
        case .fiveMedioOriente:     return "Cinco veces en Medio Oriente"
        case .fiveOceania:          return "Cinco veces en Oceanía"
        case .fiveNortamerica:      return "Cinco veces en Norteamérica"
        case .fiveCaribe:           return "Cinco veces en el Caribe"
        case .fiveSudamerica:       return "Cinco veces en Sudamérica"
        case .fiveCentroamerica:    return "Cinco veces en Centroamérica"
        }
    }

    var medal: String {
        switch self {
        case .allWorld, .visitedAntarctica:
            return "🏆"
        case .trips100, .europaCompleta, .asiaCompleta, .medioOrienteCompleto,
             .africaCompleta, .americaCompleta, .oceaniaCompleta, .ambosHemisferios,
             .todaLaUE:
            return "🥇"
        case .fiveEurope, .fiveAsia, .fiveAfrica, .fiveMedioOriente, .fiveOceania,
             .fiveNortamerica, .fiveCaribe, .fiveSudamerica, .fiveCentroamerica,
             .firstLayover,
             .todosEslavos, .todosEscandinavos, .todosBalcanicos, .todosMicroestados:
            return "🥈"
        case .firstTrip, .visitedNortamerica, .visitedCaribe, .visitedSudamerica,
             .visitedCentroamerica, .visitedAfrica, .visitedEuropa, .visitedMedioOriente,
             .visitedOceania, .visitedAsia:
            return "🥉"
        }
    }

    var medalOrder: Int {
        switch self {
        case .allWorld, .visitedAntarctica: return 0
        case .trips100, .europaCompleta, .asiaCompleta, .medioOrienteCompleto,
             .africaCompleta, .americaCompleta, .oceaniaCompleta, .ambosHemisferios,
             .todaLaUE: return 1
        case .fiveEurope, .fiveAsia, .fiveAfrica, .fiveMedioOriente, .fiveOceania,
             .fiveNortamerica, .fiveCaribe, .fiveSudamerica, .fiveCentroamerica,
             .firstLayover,
             .todosEslavos, .todosEscandinavos, .todosBalcanicos, .todosMicroestados: return 2
        case .firstTrip, .visitedNortamerica, .visitedCaribe, .visitedSudamerica,
             .visitedCentroamerica, .visitedAfrica, .visitedEuropa, .visitedMedioOriente,
             .visitedOceania, .visitedAsia: return 3
        }
    }
}

// MARK: - Pantalla de perfil
struct ProfileSheet: View {
    @Binding var username: String
    @Binding var profileImage: UIImage?
    @Binding var countingModeRaw: String
    @Binding var menuPositionRaw: String
    @Binding var showBucketList: Bool
    @Binding var showCountdown: Bool
    var onClearStatus: (CountryStatus) -> Void = { _ in }
    @Binding var topTable: String
    let visitedFlags: Set<String>
    let allFeatures: [CountryFeature]
    let visitedIsoCodes: Set<String>
    let countries: [Country]
    let trips: [Trip]

    @EnvironmentObject private var colorTheme: ColorThemeManager
    @Environment(\.dismiss) private var dismiss
    @State private var showSettings: Bool = false
    @State private var showMapExport: Bool = false
    @State private var showLogros: Bool = false
    @State private var showVisitedFlags: Bool = false
    @State private var showMedallero: Bool = false
    @State private var showTransportStats: Bool = false

    @AppStorage("multiContinentRaw") private var multiContinentRaw: String = "{}"
    private var multiContinentAssignments: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(multiContinentRaw.utf8))) ?? [:]
    }

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
    private var pastTrips: [Trip] {
        let today = Calendar.current.startOfDay(for: Date())
        return trips.filter { Calendar.current.startOfDay(for: $0.dateFrom) <= today }
    }
    private var firstTrip: Trip? { pastTrips.min(by: { $0.dateFrom < $1.dateFrom }) }
    private var firstLayoverTrip: Trip? { pastTrips.filter { $0.hasLayover }.min(by: { $0.dateFrom < $1.dateFrom }) }
    private var trip100: Trip? {
        let sorted = pastTrips.sorted { $0.dateFrom < $1.dateFrom }
        return sorted.count >= 100 ? sorted[99] : nil
    }
    private func profileLastTripDate(for kind: AchievementKind) -> Date {
        switch kind {
        case .firstTrip:    return firstTrip?.effectiveEndDate ?? .distantPast
        case .firstLayover: return firstLayoverTrip?.effectiveEndDate ?? .distantPast
        case .trips100:     return trip100?.effectiveEndDate ?? .distantPast
        case .allWorld, .ambosHemisferios:
            return pastTrips.map { $0.effectiveEndDate }.max() ?? .distantPast
        default:
            let isoCodes = kind.zoneIsoCodes.isEmpty ? kind.regionIsoCodes : kind.zoneIsoCodes
            return pastTrips.filter { isoCodes.contains($0.isoCode) }
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

    private func isAchieved(_ kind: AchievementKind) -> Bool {
        let assignments = multiContinentAssignments
        switch kind {
        case .firstTrip:    return firstTrip != nil
        case .firstLayover: return firstLayoverTrip != nil
        case .trips100:     return trip100 != nil
        case .allWorld:
            let visited = countries.filter { ($0.status == .visited || $0.status == .lived) && countingMode.counts($0.isoCode) }.count
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
            return pastTrips.filter { adjusted.contains($0.isoCode) }.count >= 5
        case .europaCompleta, .asiaCompleta, .medioOrienteCompleto,
             .africaCompleta, .americaCompleta, .oceaniaCompleta,
             .todaLaUE, .todosEslavos, .todosEscandinavos, .todosBalcanicos, .todosMicroestados:
            let base = kind.zoneIsoCodes
            let adjusted = kind.geographicZoneName.map { AchievementKind.adjustSet(base, forZone: $0, assignments: assignments) } ?? base
            let valid = adjusted.filter { countingMode.counts($0) }
            return !valid.isEmpty && valid.allSatisfy { visitedIsoCodes.contains($0) }
        case .ambosHemisferios:
            let south = AchievementKind.southernHemisphere
            let hasSouth = visitedIsoCodes.contains { south.contains($0) && countingMode.counts($0) }
            let hasNorth = visitedIsoCodes.contains { !south.contains($0) && countingMode.counts($0) }
            return hasSouth && hasNorth
        }
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
            ScrollView {
                VStack(spacing: 0) {

                    // ── Logros izquierda + Porcentaje derecha ──
                    HStack(alignment: .center, spacing: 0) {
                        // Logros (mitad izquierda)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Logros")
                                .font(.palatino(.subheadline, weight: .bold))
                            let topAchieved = AchievementKind.allCases
                                .filter { isAchieved($0) }
                                .sorted { a, b in
                                    if a.medalOrder != b.medalOrder { return a.medalOrder < b.medalOrder }
                                    return profileLastTripDate(for: a) > profileLastTripDate(for: b)
                                }
                                .prefix(3)
                            if topAchieved.isEmpty {
                                Text("No tienes logros aún")
                                    .font(.palatino(.caption))
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(Array(topAchieved), id: \.title) { kind in
                                    Button { showLogros = true } label: {
                                        HStack(spacing: 6) {
                                            Text(kind.medal).font(.body)
                                            Text(kind.title)
                                                .font(.palatino(.caption))
                                                .lineLimit(1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                                Button { showLogros = true } label: {
                                    Text("Ver todos")
                                        .font(.palatino(.caption))
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Porcentaje (mitad derecha, centrado) — tap → banderas visitadas
                        let visitedCount = countries.filter { $0.status == .visited || $0.status == .lived }.count
                        let denominator = countingMode.denominator
                        let pct = denominator > 0 ? Double(visitedCount) / Double(denominator) * 100.0 : 0.0
                        Button { showVisitedFlags = true } label: {
                            VStack(alignment: .center, spacing: 4) {
                                Text(String(format: "%.1f%%", pct))
                                    .font(.system(size: 42, weight: .bold, design: .serif))
                                    .minimumScaleFactor(0.6)
                                    .lineLimit(1)
                                Text("del mundo\nvisitado")
                                    .font(.palatino(.caption))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                    // ── Años + Finalizados/Próximos ──
                    YearTravelView(
                        countries: countries,
                        features: allFeatures,
                        trips: trips
                    )
                    .padding(.bottom, 16)

                    // ── Menú accesos rápidos ──
                    VStack(spacing: 0) {
                        Button { showMapExport = true } label: {
                            HStack {
                                Text("Pasaporte")
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
                        Divider().padding(.leading, 16)
                        Button { showMedallero = true } label: {
                            HStack {
                                Text("Premios")
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
                        Divider().padding(.leading, 16)
                        Button { showTransportStats = true } label: {
                            HStack {
                                Text("Transporte")
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
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)

                    Spacer(minLength: 32)
                }
            }
            .navigationTitle(username.isEmpty ? "Perfil" : username)
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
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showTransportStats) {
            TransportStatsSheet(
                visitedCountries: countries.filter { $0.status == .visited || $0.status == .lived },
                trips: trips,
                allFeatures: allFeatures
            )
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
                profileImage: $profileImage,
                countingModeRaw: $countingModeRaw,
                menuPositionRaw: $menuPositionRaw,
                showBucketList: $showBucketList,
                showCountdown: $showCountdown,
                onClearStatus: onClearStatus
            )
            .environmentObject(colorTheme)
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
                                            Text(flag).font(.title2)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 4)
                        }
                        .frame(maxHeight: 300)
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
                features: allFeatures,
                pastTrips: pastTrips,
                visitedIsoCodes: visitedIsoCodes
            ) { kind in isAchieved(kind) }
        }
        .appColorScheme()
    }
}

// MARK: - Logros
struct LogrosSheet: View {
    let firstTrip: Trip?
    let firstLayoverTrip: Trip?
    let trip100: Trip?
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
        case .firstTrip:    return firstTrip?.effectiveEndDate ?? .distantPast
        case .firstLayover: return firstLayoverTrip?.effectiveEndDate ?? .distantPast
        case .trips100:     return trip100?.effectiveEndDate ?? .distantPast
        case .allWorld, .ambosHemisferios:
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
            Text("\(flag) \(name)").font(.palatino(.headline))
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
    @Binding var profileImage: UIImage?
    @Binding var countingModeRaw: String
    @Binding var menuPositionRaw: String
    @Binding var showBucketList: Bool
    @Binding var showCountdown: Bool
    var onClearStatus: (CountryStatus) -> Void = { _ in }

    @State private var pendingClear: CountryStatus? = nil
    @State private var showImagePicker: Bool = false
    @State private var usernameDraft: String = ""
    @FocusState private var usernameFocused: Bool
    @State private var showContact: Bool = false
    @State private var showMultiContinent: Bool = false

    @EnvironmentObject private var colorTheme: ColorThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var showCountingToast: Bool = false
    @State private var showResetToast: Bool = false

    private var countingMode: CountingMode { CountingMode(rawValue: countingModeRaw) ?? .all }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {

                    // Perfil: foto + nombre
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 16) {
                            Button { showImagePicker = true } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    ProfileAvatarView(image: profileImage, size: 72)
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.blue)
                                        .background(Color(.systemBackground), in: Circle())
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
                                        Spacer()
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

                    // Contacto
                    Button { showContact = true } label: {
                        HStack {
                            Label("Contacto", systemImage: "envelope")
                                .font(.palatino(.body))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .contentShape(Rectangle())

                    .padding(.bottom, 32)
                }
                .padding(.top, 20)
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
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
                        if status == .bucketList { showBucketList = false }
                        onClearStatus(status)
                    }
                    pendingClear = nil
                }
                Button("Cancelar", role: .cancel) {
                    pendingClear = nil
                }
            } message: {
                if pendingClear != nil {
                    Text("Se eliminarán todos los países de Bucket list. Esta acción no se puede deshacer.")
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
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(image: $profileImage)
        }
        .sheet(isPresented: $showContact) {
            ContactSheet(username: username)
        }
        .sheet(isPresented: $showMultiContinent) {
            MultiContinentSheet()
        }
        .appColorScheme()
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

    private let maxChars = 150
    private var subject: String { "Solicitud de \(username.isEmpty ? "usuario" : username)" }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Escribe tu mensaje")
                    .font(.palatino(.subheadline))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)

                ZStack(alignment: .bottomTrailing) {
                    TextEditor(text: $messageText)
                        .font(.palatino(.body))
                        .padding(12)
                        .frame(minHeight: 140, maxHeight: 180)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                        .onChange(of: messageText) { _, new in
                            if new.count > maxChars { messageText = String(new.prefix(maxChars)) }
                        }
                    Text("\(messageText.count)/\(maxChars)")
                        .font(.palatino(.caption))
                        .foregroundStyle(messageText.count >= maxChars ? .red : .secondary)
                        .padding(.trailing, 18).padding(.bottom, 10)
                }
                .padding(.horizontal, 24)

                Button {
                    if MFMailComposeViewController.canSendMail() {
                        showMailComposer = true
                    } else if let url = URL(string: "mailto:acederas.boletin-21@icloud.com?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(messageText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                        UIApplication.shared.open(url)
                        dismiss()
                    }
                } label: {
                    Text("Enviar")
                        .font(.palatino(.body, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(messageText.isEmpty ? Color(.systemGray4) : Color.blue,
                                    in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .disabled(messageText.isEmpty)
                .padding(.horizontal, 24)

                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle("Contacto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
            .sheet(isPresented: $showMailComposer) {
                MailComposerView(
                    toRecipients: ["acederas.boletin-21@icloud.com"],
                    subject: subject,
                    body: messageText,
                    isPresented: $showMailComposer,
                    onFinish: { dismiss() }
                )
            }
        }
        .presentationDetents([.medium])
        .appColorScheme()
    }
}

// MARK: - Editar perfil (desde Ajustes)
struct EditProfileSheet: View {
    @Binding var username: String
    @Binding var profileImage: UIImage?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""
    @State private var showImagePicker: Bool = false
    @FocusState private var usernameFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Foto de perfil
                Button { showImagePicker = true } label: {
                    ZStack(alignment: .bottomTrailing) {
                        ProfileAvatarView(image: profileImage, size: 100)
                        Image(systemName: "pencil.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .background(Color(.systemBackground), in: Circle())
                    }
                }
                .padding(.top, 16)

                // Nombre de usuario
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nombre de usuario")
                        .font(.palatino(.caption, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    // Muestra @nombre + lápiz pegado, con el field invisible superpuesto
                    ZStack(alignment: .leading) {
                        HStack(spacing: 2) {
                            Text("@")
                                .font(.palatino(.body, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text(draft.isEmpty ? "usuario" : draft)
                                .font(.palatino(.body))
                                .foregroundStyle(draft.isEmpty ? .tertiary : .primary)
                            Button { usernameFocused = true } label: {
                                Image(systemName: "pencil")
                                    .font(.callout)
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                        // TextField invisible encima para capturar el input
                        TextField("", text: $draft)
                            .font(.palatino(.body))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($usernameFocused)
                            .opacity(usernameFocused ? 1 : 0.01)
                            .padding(12)
                            .background(usernameFocused ? Color(.systemGray6) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                            .onChange(of: draft) {
                                draft = String(draft.filter { $0.isLetter || $0.isNumber }.prefix(10))
                            }
                    }
                    Text("Máximo 10 caracteres alfanuméricos · mín. 1")
                        .font(.palatino(.caption))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .navigationTitle("Perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") {
                        let clean = String(draft.filter { $0.isLetter || $0.isNumber }.prefix(10))
                        if !clean.isEmpty { username = clean }
                        dismiss()
                    }
                    .font(.palatino(.body))
                }
            }
            .onAppear { draft = username }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(image: $profileImage)
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
                                .toolbar {
                                    ToolbarItem(placement: .navigationBarLeading) {
                                        Button("Cerrar") { dismiss() }.font(.palatino(.body))
                                    }
                                }
                        )
                    )
                )
            )
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
        v.confirmationDialog(
            "¿Eliminar este territorio?",
            isPresented: isPresented,
            presenting: confirmDeleteCountry
        ) { country in
            Button("Eliminar", role: .destructive) {
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
                onSave: { trip in
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
                flagEmoji: flagEmoji(for: country.isoCode)
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
        HStack(spacing: 10) {
            Text(feature.flagEmoji ?? "🌐").font(.title3)
            Button(action: onViewTrips) {
                HStack(spacing: 10) {
                    Text(feature.localizedName)
                        .font(.palatino(.body))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(visitCount)x")
                        .font(.palatino(.subheadline, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.systemGray5), in: Capsule())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onAddTrip) {
                Image(systemName: "calendar.badge.plus")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.callout)
                    .foregroundStyle(.red.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
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



// MARK: - Añadir viaje
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
    @State private var selectedAirlines: [TripAirline] = []
    @State private var showRoutePicker = false
    @State private var hasLayover: Bool = false

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.locale = Locale(identifier: "es_ES"); return f
    }()

    private var rutaLabel: String {
        if selectedAirports.isEmpty { return "Aeropuertos y aerolíneas" }
        return selectedAirports.map { "\($0.iata) (\($0.count)x)" }.joined(separator: " → ")
    }

    private var airlinesLabel: String {
        selectedAirlines.map { "\($0.name) \($0.count)x" }.joined(separator: ", ")
    }

    private func saveTrip() {
        let trimmed = tripTitle.trimmingCharacters(in: .whitespaces)
        let trip = Trip(isoCode: isoCode, title: trimmed.isEmpty ? nil : trimmed,
                        dateFrom: dateFrom, dateTo: dateTo, transport: selectedTransport,
                        tripAirports: selectedAirports, tripAirlines: selectedAirlines)
        trip.hasLayover = hasLayover
        didSave = true
        onSave(trip)
        dismiss()
    }

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
                .padding(.horizontal, 16).padding(.bottom, 4)

                // Ruta (airport + airlines) - only for ✈️
                if selectedTransport == "✈️" {
                    Button { showRoutePicker = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ruta *")
                                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                                Text(rutaLabel)
                                        .font(.palatino(.body))
                                        .foregroundStyle(selectedAirports.isEmpty ? .secondary : .primary)
                                if !selectedAirlines.isEmpty {
                                    Text(airlinesLabel)
                                        .font(.palatino(.caption)).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
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

                let isPlane = selectedTransport == "✈️"
                let canSave = selectedTransport != nil && !tripTitle.isEmpty && (!isPlane || !selectedAirports.isEmpty)
                Button { saveTrip() } label: {
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
        .sheet(isPresented: $showRoutePicker) {
            RouteWizardSheet(airports: $selectedAirports, airlines: $selectedAirlines,
                             hasLayover: $hasLayover, onDone: {})
        }
        .appColorScheme()
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
        return result.sorted { $0.lastDate < $1.lastDate }
    }

    private var proximos: [Country] {
        let today = Calendar.current.startOfDay(for: Date())
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
        }.prefix(10).map { $0 }
    }

    private func flagEmoji(for country: Country) -> String? {
        features.first(where: { $0.isoCode == country.isoCode })?.flagEmoji
    }

    private func flagEmoji(for isoCode: String) -> String? {
        features.first(where: { $0.isoCode == isoCode })?.flagEmoji
    }

    var body: some View {
        VStack(spacing: 12) {
            if availableYears.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableYears, id: \.self) { year in
                            Button { selectedYear = year } label: {
                                Text(String(year))
                                    .font(.palatino(.subheadline, weight: selectedYear == year ? .bold : .regular))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(selectedYear == year ? Color.blue : Color(.systemGray5), in: Capsule())
                                    .foregroundStyle(selectedYear == year ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }

            if selectedYear == currentYear {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .center, spacing: 6) {
                        Text("Finalizados").font(.palatino(.caption, weight: .bold)).foregroundStyle(.secondary)
                        if finalizados.isEmpty {
                            Text("–").font(.palatino(.caption)).foregroundStyle(.secondary)
                        } else {
                            let flagged = finalizados.compactMap { flagEmoji(for: $0.isoCode) }
                            FlowLayoutCentered(emojis: flagged, year: selectedYear, isLeft: true)
                        }
                    }.frame(maxWidth: .infinity)
                    Divider()
                    VStack(alignment: .center, spacing: 6) {
                        Text("Próximos").font(.palatino(.caption, weight: .bold)).foregroundStyle(.secondary)
                        if proximos.isEmpty {
                            Text("–").font(.palatino(.caption)).foregroundStyle(.secondary)
                        } else {
                            let flagged = proximos.compactMap { flagEmoji(for: $0) }
                            FlowLayoutCentered(emojis: flagged, year: selectedYear, isLeft: false)
                        }
                    }.frame(maxWidth: .infinity)
                }.padding(.horizontal, 24)
            } else {
                VStack(alignment: .center, spacing: 6) {
                    Text("Finalizados").font(.palatino(.caption, weight: .bold)).foregroundStyle(.secondary)
                    if finalizados.isEmpty {
                        Text("–").font(.palatino(.caption)).foregroundStyle(.secondary)
                    } else {
                        let flagged = finalizados.compactMap { flagEmoji(for: $0.isoCode) }
                        FlowLayoutCentered(emojis: flagged, year: selectedYear, isLeft: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
            }
        }
    }
}

struct FlowLayoutCentered: View {
    let emojis: [String]
    let year: Int
    let isLeft: Bool
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

                dateTabsRow()
                    .padding(.bottom, 12)

                RangeDatePicker(dateFrom: $dateFrom, dateTo: $dateTo, pickingFrom: $pickingFrom)
                    .padding(.horizontal, 8)
                    .frame(height: 340)
                    .padding(.bottom, 16)

                let canSave = selectedTransport != nil && (!isEditing || !tripTitle.isEmpty)
                Button {
                    let title: String? = isEditing && !tripTitle.isEmpty ? tripTitle.trimmingCharacters(in: .whitespaces) : nil
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
        return trips.filter { Calendar.current.startOfDay(for: $0.effectiveEndDate) <= today }
    }

    private var counts: [(emoji: String, label: String, count: Int)] {
        let today = Calendar.current.startOfDay(for: Date())
        let isoCodesWithPastTrips = Set(pastTrips.map { $0.isoCode })
        return transports.compactMap { t -> (emoji: String, label: String, count: Int)? in
            let matchEmojis: Set<String> = t.emoji == "🚶🏻" ? ["🚶🏻", "🚶"] : [t.emoji]
            let fromTrips = pastTrips.filter { matchEmojis.contains($0.transport ?? "") }.count
            let fromCountry = visitedCountries.filter { country -> Bool in
                guard matchEmojis.contains(country.transport ?? "") else { return false }
                guard !isoCodesWithPastTrips.contains(country.isoCode) else { return false }
                let endDate = country.plannedDateTo ?? country.plannedDate
                guard let end = endDate else { return true }
                return Calendar.current.startOfDay(for: end) <= today
            }.count
            let total = fromTrips + fromCountry
            guard total > 0 else { return nil }
            return (t.emoji, t.label, total)
        }.sorted { $0.count > $1.count }
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
        for trip in pastTrips where trip.transport == "✈️" {
            let als = trip.airlines
            guard !als.isEmpty else { continue }
            for al in trip.tripAirlines {
                counts[al.name, default: 0] += al.count
                if let prev = lastDate[al.name] { if trip.dateFrom > prev { lastDate[al.name] = trip.dateFrom } }
                else { lastDate[al.name] = trip.dateFrom }
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
                        Text("total")
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

                    Spacer(minLength: 24)
                }
            }
            .navigationTitle("Transporte")
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
    @State private var selectedAirlines: [TripAirline] = []
    @State private var showRoutePicker = false
    @State private var hasLayover: Bool

    private var rutaLabel: String {
        if selectedAirports.isEmpty { return "Aeropuertos y aerolíneas" }
        return selectedAirports.map { "\($0.iata) (\($0.count)x)" }.joined(separator: " → ")
    }
    private var airlinesLabel: String {
        selectedAirlines.map { "\($0.name) \($0.count)x" }.joined(separator: ", ")
    }

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
        _selectedAirlines = State(initialValue: trip.tripAirlines)
        _hasLayover = State(initialValue: trip.hasLayover)
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
                .padding(.horizontal, 16).padding(.bottom, 4)

// Ruta (airport + airlines) - only for ✈️
                if selectedTransport == "✈️" {
                    Button { showRoutePicker = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ruta *")
                                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                                Text(rutaLabel)
                                        .font(.palatino(.body))
                                        .foregroundStyle(selectedAirports.isEmpty ? .secondary : .primary)
                                if !selectedAirlines.isEmpty {
                                    Text(airlinesLabel)
                                        .font(.palatino(.caption)).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
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
                    trip.tripAirlines = selectedAirlines
                    trip.hasLayover = hasLayover
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
        .sheet(isPresented: $showRoutePicker) {
            RouteWizardSheet(airports: $selectedAirports, airlines: $selectedAirlines,
                             hasLayover: $hasLayover, onDone: {})
        }
        .appColorScheme()
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
    private var zoneCounter: String {
        let mode = countingMode
        let codes = selectedZone.isoCodes
        let visited = visitedCountries.filter { codes.contains($0.isoCode) && mode.counts($0.isoCode) }.count
        let total = codes.filter { mode.counts($0) }.count
        return "\(visited)/\(total)"
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var renderedImage: UIImage? = nil
    @State private var isRendering: Bool = true
    @State private var isSaving: Bool = false
    @State private var savedToast: Bool = false
    @State private var selectedZone: ExportZone = .europa
    @State private var showAddQuadrant: Bool = false
    @State private var selectedQuadrant: MapQuadrant? = nil
    @State private var quadrantToEdit: MapQuadrant? = nil
    @State private var isEditingQuadrants: Bool = false
    @State private var quadrantToDelete: MapQuadrant? = nil
    @AppStorage("mapQuadrantsData") private var mapQuadrantsData: String = "{}"

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
        var id: String { rawValue }

        var region: MKCoordinateRegion {
            switch self {
            case .europa: return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 54, longitude: 15), span: MKCoordinateSpan(latitudeDelta: 36, longitudeDelta: 50))
            case .asia: return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 35, longitude: 95), span: MKCoordinateSpan(latitudeDelta: 60, longitudeDelta: 90))
            case .medioOriente: return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 27, longitude: 42), span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 36))
            case .africa: return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 2, longitude: 20), span: MKCoordinateSpan(latitudeDelta: 72, longitudeDelta: 60))
            case .america: return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 15, longitude: -80), span: MKCoordinateSpan(latitudeDelta: 100, longitudeDelta: 100))
            case .oceania: return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: -20, longitude: 150), span: MKCoordinateSpan(latitudeDelta: 60, longitudeDelta: 70))
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
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(Array(ExportZone.allCases.prefix(3))) { zone in
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
                        ForEach(Array(ExportZone.allCases.suffix(3))) { zone in
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
                        RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)).aspectRatio(1, contentMode: .fit)
                            .overlay { VStack(spacing: 12) { ProgressView(); Text("Generando mapa…").font(.palatino(.caption)).foregroundStyle(.secondary) } }
                    }
                }
                .padding(.horizontal, 16)
                .onAppear { renderMap() }
                .onChange(of: selectedZone) { _, _ in renderMap() }

                Spacer()

                // ── Cuadrantes (grid fijo 2×2) ──
                quadrantGrid()
                    .padding(.horizontal, 16)

                Spacer()

                Button {
                    guard let img = renderedImage else { return }
                    isSaving = true
                    UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isSaving = false; savedToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { savedToast = false }
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
                .padding(.horizontal, 24).padding(.bottom, 24).disabled(renderedImage == nil)
                .animation(.easeInOut(duration: 0.2), value: savedToast)
            }
            .padding(.top, 8)
            .navigationTitle("Pasaporte").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { isEditingQuadrants.toggle() } label: {
                        Image(systemName: isEditingQuadrants ? "checkmark" : "pencil")
                    }
                }
            }
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
                QuadrantDetailSheet(quadrant: q, features: features, visitedIsoCodes: visitedSet, countingModeRaw: countingModeRaw)
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
        }
        .appColorScheme()
    }

    @ViewBuilder
    private func quadrantSlot(index: Int) -> some View {
        let slots = currentQuadrantSlots
        let visitedSet = Set(visitedCountries.map { $0.isoCode })
        let currentMode = CountingMode(rawValue: countingModeRaw) ?? .all
        if let q = slots[index] {
            let activeCodes = q.candidateIsoCodes.filter { currentMode.counts($0) }
            let cnt = activeCodes.filter { visitedSet.contains($0) }.count
            ZStack(alignment: .topTrailing) {
                Button { if !isEditingQuadrants { selectedQuadrant = q } } label: {
                    VStack(spacing: 4) {
                        Text(q.title)
                            .font(.palatino(.caption, weight: .bold))
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

    private func renderMap() {
        isRendering = true
        let size = CGSize(width: 800, height: 800)
        let options = MKMapSnapshotter.Options()
        options.region = selectedZone.region
        options.size = size
        options.scale = displayScale
        options.mapType = .mutedStandard
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false
        let style: UIUserInterfaceStyle = ColorThemeManager.shared.isDarkMode ? .dark : .light
        options.traitCollection = UITraitCollection(userInterfaceStyle: style)

        let visitedIsoCodes = Set(visitedCountries.map { $0.isoCode })
        let visitedFeatures = features.filter { visitedIsoCodes.contains($0.isoCode) }
        let fillUIColor = UIColor(visitedColor)
        let counterStr = zoneCounter

        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { snapshot, _ in
            guard let snapshot else { return }
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { _ in
                // 1. Mapa base
                snapshot.image.draw(at: .zero)

                // 2. Polígonos de países visitados encima
                for feature in visitedFeatures {
                    for polygon in feature.polygons {
                        guard polygon.pointCount >= 3 else { continue }
                        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: polygon.pointCount)
                        polygon.getCoordinates(&coords, range: NSRange(location: 0, length: polygon.pointCount))
                        let pts = coords.map { snapshot.point(for: $0) }
                        let m: CGFloat = 50
                        guard pts.contains(where: { $0.x > -m && $0.x < size.width + m && $0.y > -m && $0.y < size.height + m }) else { continue }

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
                            let hpts = hc.map { snapshot.point(for: $0) }
                            hp.move(to: hpts[0]); hpts.dropFirst().forEach { hp.addLine(to: $0) }; hp.close()
                            path.append(hp)
                        }

                        fillUIColor.setFill()
                        path.fill()
                    }
                }

                // Contador por zona, centrado en la parte inferior
                let text = counterStr as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont(name: "Palatino-Bold", size: 20) ?? .boldSystemFont(ofSize: 20),
                    .foregroundColor: UIColor.white
                ]
                let ts = text.size(withAttributes: attrs)
                let pad: CGFloat = 10
                let bgW = ts.width + pad * 2
                let bgRect = CGRect(x: (size.width - bgW) / 2, y: size.height - ts.height - pad * 2 - 14, width: bgW, height: ts.height + pad * 2)
                UIColor.black.withAlphaComponent(0.55).setFill()
                UIBezierPath(roundedRect: bgRect, cornerRadius: 8).fill()
                text.draw(at: CGPoint(x: bgRect.minX + pad, y: bgRect.minY + pad), withAttributes: attrs)
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

    private var flaggedFeatures: [CountryFeature] {
        features.filter {
            $0.flagEmoji != nil &&
            zone.isoCodes.contains($0.isoCode) &&
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
                                Text(feature.flagEmoji ?? "")
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }.font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Guardar") { saveAndDismiss() }
                        .disabled(title.isEmpty || selectedIsoCodes.isEmpty)
                        .font(.palatino(.body, weight: .bold))
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
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

    @Environment(\.dismiss) private var dismiss

    private var countingMode: CountingMode { CountingMode(rawValue: countingModeRaw) ?? .all }

    // Solo los candidatos que el modo de conteo activo reconoce
    private var activeCandidates: [String] {
        quadrant.candidateIsoCodes.filter { countingMode.counts($0) }
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
                                Text(feature.flagEmoji ?? "").font(.title2)
                                Text(feature.localizedName).font(.palatino(.body))
                            }
                        }
                    }
                }
                if !notVisited.isEmpty {
                    Section {
                        ForEach(notVisited, id: \.isoCode) { feature in
                            HStack(spacing: 12) {
                                Text(feature.flagEmoji ?? "").font(.title2).opacity(0.4)
                                Text(feature.localizedName)
                                    .font(.palatino(.body))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("\(quadrant.title) · \(visited.count)/\(activeCandidates.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
    @AppStorage("countingMode") private var countingModeRaw: String = CountingMode.all.rawValue

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
                                                    Text(emoji).font(.system(size: 34))
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
                // ── Premios personales ──
                VStack(spacing: 10) {
                    ForEach(personalAwards) { award in
                        Button { editingAward = award } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(award.title.isEmpty ? "Premio personal" : award.title)
                                        .font(.palatino(.body, weight: .bold))
                                        .foregroundStyle(.primary)
                                    HStack(spacing: 6) {
                                        Text("🥇").font(.caption)
                                        Text(award.gold.isEmpty ? "—" : award.gold)
                                            .font(.palatino(.caption)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    HStack(spacing: 6) {
                                        Text("🥈").font(.caption)
                                        Text(award.silver.isEmpty ? "—" : award.silver)
                                            .font(.palatino(.caption)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    HStack(spacing: 6) {
                                        Text("🥉").font(.caption)
                                        Text(award.bronze.isEmpty ? "—" : award.bronze)
                                            .font(.palatino(.caption)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    ForEach(award.extras.indices, id: \.self) { i in
                                        Text("· \(award.extras[i])")
                                            .font(.palatino(.caption)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 12)
                    }
                    if personalAwards.count < 3 {
                        Button {
                            let newAward = PersonalAwardModel(sortOrder: personalAwards.count)
                            modelContext.insert(newAward)
                            editingAward = newAward
                        } label: {
                            Label("Añadir premio personal", systemImage: "plus.circle")
                                .font(.palatino(.body))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 24)
                .padding(.top, 4)
                }
                .padding(.top, 16)
            }
            .navigationTitle("Premios")
            .navigationBarTitleDisplayMode(.inline)
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
        .appColorScheme()
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
                Section(header: Text("Otras opciones").font(.palatino(.caption))) {
                    ForEach(extras.indices, id: \.self) { i in
                        HStack {
                            TextField("Opción \(i + 1)", text: Binding(
                                get: { extras[i] },
                                set: { extras[i] = $0 }
                            ))
                            .font(.palatino(.body))
                            Button {
                                extras.remove(at: i)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if extras.count < maxExtras {
                        Button {
                            extras.append("")
                        } label: {
                            Label("Añadir opción", systemImage: "plus.circle")
                                .font(.palatino(.body))
                                .foregroundStyle(.blue)
                        }
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
            .confirmationDialog("¿Eliminar este premio?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Eliminar", role: .destructive) { onDelete() }
                Button("Cancelar", role: .cancel) {}
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
                                            Text(item.flag).font(.title2)
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
            }
            .navigationTitle("Banderas visitadas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
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
            VStack {
                Spacer()
                VStack(spacing: 0) {
                    ForEach(multiContinentEntries) { entry in
                        HStack(spacing: 12) {
                            Text(entry.flag).font(.title2)
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
                Spacer()
            }
            .navigationTitle("Países pluricontinentales")
            .navigationBarTitleDisplayMode(.inline)
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

// MARK: - Route wizard (multi-step)
struct RouteWizardSheet: View {
    @Binding var airports: [TripAirport]
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
    }

    @State private var step: Step = .departure
    @State private var departureIata = ""
    @State private var layoverStops: [(iata: String, airline: String)] = []
    @State private var pendingLayoverIata = ""
    @State private var finalIata = ""
    @State private var finalAirline = ""
    @State private var returnAirlineDraft = ""
    @State private var returnDepartureIata = ""
    @State private var returnLayoverStops: [(iata: String, airline: String)] = []
    @State private var returnPendingLayoverIata = ""
    @State private var returnFinalIata = ""
    @State private var returnFinalAirline = ""
    @State private var query = ""
    @State private var didPrepopulate = false

    private static let allAirports = RoutePickerSheet.allAirports
    private static var allAirlines: [AirlineData] { AirlinePickerSheet.airlines }

    private var filteredAirports: [AirportData] {
        if query.isEmpty { return Array(Self.allAirports.prefix(80)) }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return Self.allAirports.filter {
            $0.iata.range(of: query, options: opts) != nil ||
            $0.name.range(of: query, options: opts) != nil ||
            $0.city.range(of: query, options: opts) != nil
        }
    }

    private var filteredAirlines: [AirlineData] {
        if query.isEmpty { return Array(Self.allAirlines.prefix(80)) }
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
        }
    }

    private func buildAndSave(isReturn: Bool, differentReturnAirline: String? = nil) {
        let route = [departureIata] + layoverStops.map(\.iata) + [finalIata]
        let mult = (isReturn && differentReturnAirline == nil) ? 2 : 1
        var apCounts: [String: Int] = [:]
        for iata in route { apCounts[iata, default: 0] += (isReturn ? 2 : 1) }
        var seen = Set<String>()
        airports = route.compactMap { iata -> TripAirport? in
            guard !seen.contains(iata) else { return nil }
            seen.insert(iata); return TripAirport(iata: iata, count: apCounts[iata]!)
        }
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
        var apCounts: [String: Int] = [:]
        for iata in outbound { apCounts[iata, default: 0] += 1 }
        for iata in returning { apCounts[iata, default: 0] += 1 }
        var seen = Set<String>()
        airports = (outbound + returning).compactMap { iata -> TripAirport? in
            guard !seen.contains(iata) else { return nil }
            seen.insert(iata); return TripAirport(iata: iata, count: apCounts[iata]!)
        }
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }.font(.palatino(.body))
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
            departureIata = aps[0].iata
            finalIata = aps[aps.count - 1].iata
            let middle = Array(aps[1..<max(1, aps.count - 1)])
            layoverStops = middle.enumerated().map { i, ap in
                (iata: ap.iata, airline: i < als.count ? als[i].name : "")
            }
            let lastIdx = middle.count
            finalAirline = lastIdx < als.count ? als[lastIdx].name : (als.last?.name ?? "")
        }
        .appColorScheme()
    }

    @ViewBuilder private var stepView: some View {
        switch step {
        case .departure:
            airportSearch(hint: "Ciudad, aeropuerto o IATA") { iata in
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
            airportSearch(hint: "Ciudad, aeropuerto o IATA") { iata in
                returnFinalIata = iata; query = ""; step = .returnFinalAirline
            }
        case .returnFinalAirline:
            airlineSearch(hint: "Aerolínea") { name in
                returnFinalAirline = name; query = ""
                buildAndSaveWithReturnRoute()
            }
        }
    }

    // ── Return airline choice ──
    private var returnAirlineChoiceView: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("¿Misma aerolínea a la vuelta?")
                .font(.palatino(.title3, weight: .bold)).multilineTextAlignment(.center)
            if !finalAirline.isEmpty {
                Text(finalAirline).font(.palatino(.subheadline)).foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                Button { buildAndSave(isReturn: true) } label: {
                    Text("Sí, la misma")
                        .font(.palatino(.body, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                Button { query = ""; step = .returnAirline } label: {
                    Text("No, diferente aerolínea")
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
    private func airportSearch(hint: String, onSelect: @escaping (String) -> Void) -> some View {
        VStack(spacing: 0) {
            searchBar(placeholder: hint)
            Divider()
            List(filteredAirports, id: \.iata) { ap in
                Button { onSelect(ap.iata) } label: {
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
                Button { query = ""; step = .layoverAddAirport } label: {
                    Text("🔄  Con escala(s)")
                        .font(.palatino(.body, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                Button { query = ""; step = .finalDest } label: {
                    Text("✈️  Vuelo directo")
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
                            Text(ap?.flagEmoji ?? "🌐").font(.title3)
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
                    if layoverStops.isEmpty {
                        query = ""; step = .returnAirlineChoice
                    } else {
                        buildAndSave(isReturn: true)
                    }
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
                    returnDepartureIata = ""
                    returnFinalIata = ""
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
                Button { query = ""; step = .returnLayoverAddAirport } label: {
                    Text("🔄  Con escala(s)")
                        .font(.palatino(.body, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                Button { query = ""; step = .returnFinalDest } label: {
                    Text("✈️  Vuelo directo")
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
                            Text(ap?.flagEmoji ?? "🌐").font(.title3)
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
                                Text(apData?.flagEmoji ?? "🌐").font(.title3)
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
                            Text(ap.flagEmoji).font(.title3)
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
