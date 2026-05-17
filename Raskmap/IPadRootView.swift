//
//  IPadRootView.swift
//  Raskmap
//
//  Layout master-detail para iPad y pantallas regular size class.
//  Aprovecha el espacio adicional con una columna lateral de lista
//  de países + viajes, y el mapa + sheets como detail.
//
//  Activación: `ContentView` detecta `horizontalSizeClass == .regular`
//  y delega al `IPadRootView` en lugar del layout vertical del iPhone.
//
//  Por qué un archivo aparte: las decisiones de layout son
//  suficientemente distintas que mezclar ambas vistas en `ContentView`
//  haría ese archivo (ya modular) un spaghetti de `if` per platform.
//
//  Estado: scaffold funcional. Una vez validado en simulador iPad,
//  se enlaza vía `iPadRootIfRegular()` modifier en `ContentView`.
//

import SwiftUI
import SwiftData

struct IPadRootView: View {
    let countries: [Country]
    let trips: [Trip]
    let features: [CountryFeature]

    @State private var selectedTab: SidebarTab = .visited
    @State private var selectedCountryISO: String? = nil
    @State private var searchText: String = ""

    enum SidebarTab: String, CaseIterable, Identifiable {
        case visited      = "Visitados"
        case wantToVisit  = "Próximos"
        case bucketList   = "Quiero"
        case lived        = "Vivido"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .visited:     return "checkmark.circle.fill"
            case .wantToVisit: return "calendar.badge.plus"
            case .bucketList:  return "star.fill"
            case .lived:       return "house.fill"
            }
        }
    }

    private var filteredCountries: [Country] {
        let statusFilter: CountryStatus
        switch selectedTab {
        case .visited:     statusFilter = .visited
        case .wantToVisit: statusFilter = .wantToVisit
        case .bucketList:  statusFilter = .bucketList
        case .lived:       statusFilter = .lived  // hasLived es independiente del status — simplificación
        }
        let byStatus = countries.filter { $0.status == statusFilter }
        guard !searchText.isEmpty else { return byStatus }
        let q = searchText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return byStatus.filter { c in
            let name = features.first(where: { $0.isoCode == c.isoCode })?.localizedName ?? c.name
            return name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(q)
        }
    }

    var body: some View {
        NavigationSplitView {
            // === MASTER (sidebar) ===
            VStack(spacing: 0) {
                // Tabs por estado
                Picker("Filtro", selection: $selectedTab) {
                    ForEach(SidebarTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // Lista filtrable
                List(filteredCountries, id: \.isoCode, selection: $selectedCountryISO) { country in
                    countryRow(country)
                        .tag(country.isoCode)
                }
                .listStyle(.inset)
                .searchable(text: $searchText, prompt: "Buscar país…")
                .overlay {
                    if filteredCountries.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                            Text("Sin países en \(selectedTab.rawValue)")
                                .font(.palatino(.subheadline))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Raskmap")
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        } detail: {
            // === DETAIL ===
            // En iPad portrait, NavigationSplitView muestra el detail
            // a pantalla completa con el master ocultable; en landscape,
            // se ven ambos.
            if let iso = selectedCountryISO,
               let country = countries.first(where: { $0.isoCode == iso }) {
                detailView(for: country)
            } else {
                placeholderDetail
            }
        }
    }

    @ViewBuilder
    private func countryRow(_ country: Country) -> some View {
        let feat = features.first { $0.isoCode == country.isoCode }
        HStack(spacing: 10) {
            FlagLabel(emoji: feat?.flagEmoji ?? "🌐", size: 22)
            Text(feat?.localizedName ?? country.name)
                .font(.palatino(.body))
            Spacer()
            if country.visitCount > 1 {
                Text("×\(country.visitCount)")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func detailView(for country: Country) -> some View {
        let feat = features.first { $0.isoCode == country.isoCode }
        let countryTrips = trips
            .filter { $0.isoCode == country.isoCode }
            .sorted { $0.dateFrom < $1.dateFrom }

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Hero
                HStack(spacing: 18) {
                    FlagLabel(emoji: feat?.flagEmoji ?? "🌐", size: 64)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(feat?.localizedName ?? country.name)
                            .font(.palatino(.largeTitle, weight: .bold))
                        Text(country.status.label)
                            .font(.palatino(.body))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                // Stats simples
                HStack(spacing: 16) {
                    statTile(title: "Visitas",
                             value: "\(country.visitCount + countryTrips.count)")
                    if let date = countryTrips.first?.dateFrom {
                        statTile(title: "Primer viaje",
                                 value: Self.dfmt.string(from: date))
                    }
                    if country.hasLived {
                        statTile(title: "Estado", value: "🏠 Viví aquí")
                    }
                }

                // Lista de viajes
                if !countryTrips.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Viajes")
                            .font(.palatino(.title3, weight: .bold))
                        ForEach(countryTrips) { trip in
                            tripRow(trip)
                        }
                    }
                }

                Spacer()
            }
            .padding(24)
        }
        .navigationTitle(feat?.localizedName ?? country.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private static let dfmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.locale = Locale.current
        return f
    }()

    @ViewBuilder
    private func statTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.palatino(.caption, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
            Text(value)
                .font(.palatino(.title3, weight: .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.card))
    }

    @ViewBuilder
    private func tripRow(_ trip: Trip) -> some View {
        HStack(spacing: 12) {
            if let t = trip.transport, !t.isEmpty {
                Text(t).font(.title2)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let title = trip.title, !title.isEmpty {
                    Text(title).font(.palatino(.body, weight: .bold))
                }
                Text(Self.dfmt.string(from: trip.dateFrom))
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var placeholderDetail: some View {
        VStack(spacing: 14) {
            Image(systemName: "globe.europe.africa")
                .font(.system(size: 64))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("Selecciona un país")
                .font(.palatino(.title3, weight: .bold))
                .foregroundStyle(.secondary)
            Text("Elige un país del listado para ver sus viajes")
                .font(.palatino(.body))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Helper para integración en ContentView

/// Modifier que envuelve la vista del iPhone con el layout iPad si la
/// size class es `.regular`. Uso en `ContentView.body`:
///
///     contentForiPhone
///         .adaptiveRoot(countries: countries, trips: trips, features: features)
///
/// En iPhone (sizeClass compact) devuelve la vista original sin cambios.
/// En iPad (sizeClass regular) devuelve `IPadRootView`.
extension View {
    @ViewBuilder
    func adaptiveRoot(countries: [Country], trips: [Trip], features: [CountryFeature]) -> some View {
        AdaptiveRootContainer(iPhoneRoot: { self },
                              countries: countries, trips: trips, features: features)
    }
}

private struct AdaptiveRootContainer<IPhoneRoot: View>: View {
    @ViewBuilder var iPhoneRoot: () -> IPhoneRoot
    let countries: [Country]
    let trips: [Trip]
    let features: [CountryFeature]
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            IPadRootView(countries: countries, trips: trips, features: features)
        } else {
            iPhoneRoot()
        }
    }
}
