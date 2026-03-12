//
//  ContentView.swift
//  Raskmap
//

import SwiftUI
import SwiftData
import Combine

class MapStore: ObservableObject {
    var centerOnCountry: ((String) -> Void)?
}

struct ContentView: View {
    var onContentReady: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Query private var countries: [Country]

    @State private var selectedCountry: Country? = nil
    @State private var showSheet: Bool = false
    @State private var features: [CountryFeature] = []
    @State private var showSearch: Bool = false
    @State private var searchText: String = ""
    @StateObject private var mapStore = MapStore()
    @AppStorage("username") private var username: String = ""
    @State private var showOnboarding: Bool = false
    @State private var usernameInput: String = ""
    @State private var isLoadingFeatures: Bool = true

    private var visitedCount: Int { countries.filter { $0.status == .visited }.count }
    private var wantCount: Int    { countries.filter { $0.status == .wantToVisit }.count }
    private var livedCount: Int   { countries.filter { $0.status == .lived }.count }

    private var sortedFeatures: [CountryFeature] {
        features.sorted { $0.localizedName < $1.localizedName }
    }

    private var countryStatusMap: [String: CountryStatus] {
        Dictionary(uniqueKeysWithValues: countries.map { ($0.isoCode, $0.status) })
    }

    private var searchResults: [CountryFeature] {
        guard !searchText.isEmpty else { return sortedFeatures }
        return sortedFeatures.filter {
            $0.localizedName.localizedCaseInsensitiveContains(searchText)
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

    var body: some View {
        ZStack(alignment: .top) {
            
            // MARK: - Mapa
            RaskMapView(
                countries: .constant(countries),
                features: features,
                onCountryTapped: { country in
                    handleCountryTap(country)
                },
                onReady: { centerFn in
                    mapStore.centerOnCountry = centerFn
                }
            )
            .ignoresSafeArea()

            // MARK: - Header
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Raskmap")
                            .font(.palatino(.headline))
                            .fontWeight(.bold)
                        Text("@\(username)")
                            .font(.palatino(.caption))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Spacer()
                        StatBadge(value: visitedCount, label: "Visitado",  color: .red)
                        StatBadge(value: wantCount,    label: "Próximo",   color: .blue)
                        StatBadge(value: livedCount,   label: "He vivido", color: .green)
                        
                    }             }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 12)
                .padding(.top, 8)
                
                // Contador + lupa
                ZStack {
                    Text("\(visitedCount + livedCount) / \(features.count) países")
                        .font(.palatino(.caption))
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    
                    HStack {
                        Spacer()
                        Button(action: { showSearch = true }) {
                            Image(systemName: "magnifyingglass")
                                .font(.palatino(.title3))
                                .padding(8)
                                .background(Color(.systemGray5), in: Circle())
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 12)
                .padding(.top, 6)
            }
        }
        // MARK: - Sheet país
        .sheet(isPresented: $showSheet) {
            if let country = selectedCountry {
                CountryBottomSheet(
                    country: country,
                    displayName: localizedName(for: country),
                    onStatusChange: { newStatus in
                        updateCountryStatus(country: country, newStatus: newStatus)
                        showSheet = false
                    },
                    onDismiss: { showSheet = false }
                )
                .presentationDetents([.fraction(0.40)])
                .presentationDragIndicator(.visible)
            }
        }

        // MARK: - Sheet búsqueda
        .sheet(isPresented: $showSearch) {
            NavigationStack {
                List {
                    ForEach(groupedSearchResults, id: \.letter) { section in
                        Section(header: searchText.isEmpty ? Text(section.letter) : nil) {
                            ForEach(section.features, id: \.isoCode) { feature in
                                Button(action: {
                                    let isoCode = feature.isoCode
                                    if let existing = countries.first(where: { $0.isoCode == isoCode }) {
                                        selectedCountry = existing
                                    } else {
                                        let newCountry = Country(name: feature.name, isoCode: isoCode)
                                        modelContext.insert(newCountry)
                                        selectedCountry = newCountry
                                    }
                                    showSearch = false
                                    showSheet = true
                                }) {
                                    HStack {
                                        Text(feature.flagEmoji ?? "⚠️")
                                        Text(feature.localizedName)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if let status = countryStatusMap[feature.isoCode], status != .none {
                                            Text(status.label)
                                                .font(.palatino(.caption))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "Buscar país...")
                .navigationTitle("Buscar país")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") {
                            showSearch = false
                            searchText = ""
                        }
                    }
                }
            }
        }

        // MARK: - Sheet onboarding
        .sheet(isPresented: $showOnboarding) {
            VStack(spacing: 24) {
                Spacer()
                Text("👋 Bienvenido a Raskmap")
                    .font(.palatino(.title2, weight: .bold))
                Text("¿Cómo quieres que te llamemos?")
                    .font(.palatino(.subheadline))
                    .foregroundStyle(.secondary)
                TextField("Tu nombre de usuario", text: $usernameInput)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 32)
                    .onChange(of: usernameInput) {
                        usernameInput = String(usernameInput
                            .filter { $0.isLetter || $0.isNumber }
                            .prefix(15))
                    }
                Button(action: {
                    let clean = String(usernameInput
                        .filter { $0.isLetter || $0.isNumber }
                        .prefix(15))
                    if !clean.isEmpty {
                        username = clean
                        showOnboarding = false
                    }
                }) {
                    Text("Empezar")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 32)
                Spacer()
            }
            .interactiveDismissDisabled(true)
        }

        // MARK: - Carga inicial
        .task {
            if features.isEmpty {
                GeoJSONLoader.loadCountriesAsync { countries in
                    self.features = countries
                    self.isLoadingFeatures = false
                    self.onContentReady?()
                }
            } else {
                isLoadingFeatures = false
                onContentReady?()
            }

            if username.isEmpty {
                showOnboarding = true
            }
        }
    }

    // MARK: - Lógica de negocio

    private func centerMap(on isoCode: String) {
        mapStore.centerOnCountry?(isoCode)
    }

    private func handleCountryTap(_ country: Country) {
        guard !isLoadingFeatures else { return }
        if let existing = countries.first(where: { $0.isoCode == country.isoCode }) {
            selectedCountry = existing
        } else {
            modelContext.insert(country)
            selectedCountry = country
        }
        showSheet = true
    }

    private func localizedName(for country: Country) -> String {
        features.first(where: { $0.isoCode == country.isoCode })?.localizedName ?? country.name
    }
    
    private func updateCountryStatus(country: Country, newStatus: CountryStatus) {
        country.status = newStatus
        if newStatus != .none {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                centerMap(on: country.isoCode)
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
        .padding(.horizontal, 10)
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
    let onStatusChange: (CountryStatus) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text(displayName)
                    .font(.palatino(.title2, weight: .bold))
                Text("Estado actual: \(country.status.label)")
                    .font(.palatino(.subheadline))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 0)

            VStack(spacing: 10) {
                ActionButton(
                    label: "✅ Visitado",
                    color: .red,
                    isSelected: country.status == .visited,
                    action: { onStatusChange(.visited) }
                )
                ActionButton(
                    label: "🔵 Próximo",
                    color: .blue,
                    isSelected: country.status == .wantToVisit,
                    action: { onStatusChange(.wantToVisit) }
                )
                ActionButton(
                    label: "🏠 He vivido aquí",
                    color: .green,
                    isSelected: country.status == .lived,
                    action: { onStatusChange(.lived) }
                )
                if country.status != .none {
                    Button("✕  Desmarcar") {
                        onStatusChange(.none)
                    }
                    .font(.palatino(.subheadline))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.top, 24)
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
