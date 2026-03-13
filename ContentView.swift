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
    @State private var statusListFilter: CountryStatus? = nil
    @State private var showSheet: Bool = false
    @State private var features: [CountryFeature] = []
    @State private var showSearch: Bool = false
    @State private var showAllCountries: Bool = false
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
    @AppStorage("menuPosition") private var menuPositionRaw: String = "bottom"
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
    private var livedCountAll: Int   { countries.filter { $0.status == .lived }.count }

    // Conteos filtrados según modo activo (para badges y contador)
    private var visitedCount: Int {
        countingMode == .all ? visitedCountAll :
        countries.filter { $0.status == .visited && countingMode.counts($0.isoCode) }.count
    }
    private var wantCount: Int {
        countingMode == .all ? wantCountAll :
        countries.filter { $0.status == .wantToVisit && countingMode.counts($0.isoCode) }.count
    }
    private var livedCount: Int {
        countingMode == .all ? livedCountAll :
        countries.filter { $0.status == .lived && countingMode.counts($0.isoCode) }.count
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

    var body: some View {
        ZStack(alignment: menuPositionIsTop ? .top : .bottom) {
            
            // MARK: - Mapa
            RaskMapView(
                countries: countries,
                features: features,
                onCountryTapped: { country in
                    handleCountryTap(country)
                },
                highlightedIsoCode: highlightedIsoCode,
                onReady: { centerFn in
                    mapStore.centerOnCountry = centerFn
                }
            )
            .ignoresSafeArea()

            // MARK: - UI (posición arriba o abajo)
            if menuPositionIsTop {
                // ── ARRIBA ──
                VStack(spacing: 0) {
                    // Contenedor principal: avatar/título + badges
                    HStack(spacing: 12) {
                        Button { showProfile = true } label: {
                            HStack(spacing: 8) {
                                ProfileAvatarView(image: profileImage, size: 34)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Raskmap")
                                        .font(.palatino(.headline, weight: .bold))
                                        .foregroundStyle(.primary)
                                    if !username.isEmpty {
                                        Text("@\(username)")
                                            .font(.palatino(.caption))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        
                        HStack(spacing: 4) {
                            StatBadge(value: visitedCount, label: "Visitados",  color: colorTheme.visitedColor)
                                .onTapGesture { statusListFilter = .visited }
                            StatBadge(value: wantCount,    label: "Próximos",  color: colorTheme.wantToVisitColor)
                                .onTapGesture { statusListFilter = .wantToVisit }
                            StatBadge(value: livedCount,   label: "Vivido",    color: colorTheme.livedColor)
                                .onTapGesture { statusListFilter = .lived }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    // Fila: contador izquierda + lupa derecha
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(visitedCount + livedCount) / \(countingMode.denominator)")
                            .font(.palatino(.title3, weight: .bold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .onTapGesture { showAllCountries = true }
                        Spacer()
                        Button(action: { showSearch = true }) {
                            Image(systemName: "magnifyingglass")
                                .font(.palatino(.title3))
                                .padding(10)
                                .background(.regularMaterial, in: Circle())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                }
            } else {
                // ── ABAJO ──
                VStack(spacing: 6) {
                    // Fila intermedia: contador países (izq) + lupa (der)
                    HStack(alignment: .bottom, spacing: 8) {
                        Text("\(visitedCount + livedCount) / \(countingMode.denominator)")
                            .font(.palatino(.title3, weight: .bold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .onTapGesture { showAllCountries = true }
                        Spacer()
                        Button(action: { showSearch = true }) {
                            Image(systemName: "magnifyingglass")
                                .font(.palatino(.title3))
                                .padding(10)
                                .background(.regularMaterial, in: Circle())
                        }
                    }
                    .padding(.horizontal, 12)

                    // Contenedor principal: avatar/título + badges
                    HStack(spacing: 12) {
                        Button { showProfile = true } label: {
                            HStack(spacing: 8) {
                                ProfileAvatarView(image: profileImage, size: 34)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Raskmap")
                                        .font(.palatino(.headline, weight: .bold))
                                        .foregroundStyle(.primary)
                                    if !username.isEmpty {
                                        Text("@\(username)")
                                            .font(.palatino(.caption))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        HStack(spacing: 4) {
                            StatBadge(value: visitedCount, label: "Visitados",  color: colorTheme.visitedColor)
                                .onTapGesture { statusListFilter = .visited }
                            StatBadge(value: wantCount,    label: "Próximos",  color: colorTheme.wantToVisitColor)
                                .onTapGesture { statusListFilter = .wantToVisit }
                            StatBadge(value: livedCount,   label: "Vivido",    color: colorTheme.livedColor)
                                .onTapGesture { statusListFilter = .lived }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 6)
                    .padding(.bottom, 32)
                }
            }
        }
        // MARK: - Sheet país
        .sheet(item: $selectedCountry, onDismiss: {
            // Si se cierra sin asignar estado, quitar el borde negro
            highlightedIsoCode = nil
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
                }
            )
            .presentationDetents([.fraction(0.40)])
            .presentationDragIndicator(.visible)
        }

        // MARK: - Sheet búsqueda
        .sheet(isPresented: $showSearch, onDismiss: {
            if pendingShowSheet {
                pendingShowSheet = false
                showSheet = true
            }
        }) {
            NavigationStack {
                List {
                    ForEach(groupedSearchResults, id: \.letter) { section in
                        Section(header: searchText.isEmpty ? Text(section.letter) : nil) {
                            ForEach(section.features, id: \.isoCode) { feature in
                                // contentShape hace que TODO el ancho de la fila sea tappable
                                HStack {
                                    Text(feature.flagEmoji ?? "🌐")
                                    Text(feature.localizedName)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if let status = countryStatusMap[feature.isoCode], status != .none {
                                        Text(status.label)
                                            .font(.palatino(.caption))
                                            .foregroundStyle(.secondary)
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

        // MARK: - Sheet todos los territorios
        .sheet(isPresented: $showAllCountries) {
            AllCountriesSheet(features: features, mode: countingMode)
        }

        // MARK: - Sheet lista por estado
        .sheet(item: $statusListFilter) { filter in
            StatusListSheet(
                filter: filter,
                countries: countries,
                features: features,
                onRemove: { country in
                    country.status = .none
                    try? modelContext.save()
                }
            )
        }

        // MARK: - Sheet perfil
        .sheet(isPresented: $showProfile) {
            let visitedFlags: Set<String> = Set(
                countries
                    .filter { $0.status == .visited || $0.status == .lived }
                    .compactMap { country in
                        features.first(where: { $0.isoCode == country.isoCode })?.flagEmoji
                    }
            )
            ProfileSheet(
                username: $username,
                profileImage: $profileImage,
                countingModeRaw: $countingModeRaw,
                menuPositionRaw: $menuPositionRaw,
                topGold: $topGold,
                topSilver: $topSilver,
                topBronze: $topBronze,
                topTable: $topTable,
                visitedFlags: visitedFlags,
                allFeatures: features,
                visitedIsoCodes: Set(countries.filter { $0.status == .visited || $0.status == .lived }.map { $0.isoCode })
            )
        }
        .onChange(of: profileImage) {
            if let img = profileImage, let data = img.jpegData(compressionQuality: 0.8) {
                UserDefaults.standard.set(data, forKey: "profileImageData")
            }
        }

        // MARK: - Carga inicial
        .task {
            if features.isEmpty {
                GeoJSONLoader.loadCountriesAsync { loadedFeatures in
                    self.features = loadedFeatures
                    // Pre-insertar todos los países que aún no existen en SwiftData.
                    // Así el primer tap siempre encuentra el objeto en @Query
                    // y nunca hay race condition → pantalla blanca eliminada.
                    let existingCodes = Set(self.countries.map { $0.isoCode })
                    for feature in loadedFeatures {
                        if !existingCodes.contains(feature.isoCode) {
                            let country = Country(name: feature.adminName, isoCode: feature.isoCode)
                            self.modelContext.insert(country)
                        }
                    }
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
        country.status = newStatus
        // Quitar el borde negro al asignar estado
        highlightedIsoCode = nil
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
            .padding(.top, 36)

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
                ActionButton(
                    label: "🏠 He vivido aquí",
                    color: colorTheme.livedColor,
                    isSelected: country.status == .lived,
                    action: {
                        if country.status == .lived { showRemoveConfirm = true }
                        else { onStatusChange(.lived) }
                    }
                )
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
    let onRemove: (Country) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var countryToRemove: Country? = nil

    private var filtered: [Country] {
        countries.filter { $0.status == filter }
    }

    private func displayName(for country: Country) -> String {
        features.first(where: { $0.isoCode == country.isoCode })?.localizedName ?? country.name
    }

    private func flagEmoji(for country: Country) -> String {
        features.first(where: { $0.isoCode == country.isoCode })?.flagEmoji ?? "🌐"
    }

    // Agrupados por primera letra, igual que la búsqueda
    private var grouped: [(letter: String, items: [Country])] {
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
                                        Text(displayName(for: country))
                                            .font(.palatino(.body))
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
    @Binding var topGold: String
    @Binding var topSilver: String
    @Binding var topBronze: String
    @Binding var topTable: String
    let visitedFlags: Set<String>
    let allFeatures: [CountryFeature]
    let visitedIsoCodes: Set<String>

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
                        "SWE","CHE","UKR","GBR","VAT","KOS","XKX"]
            case .asia:
                return ["AFG","ARM","AZE","BGD","BTN","BRN","KHM","CHN","GEO","IND",
                        "IDN","JPN","KAZ","PRK","KOR","KGZ","LAO","MYS","MDV","MNG",
                        "MMR","NPL","PAK","PHL","SGP","LKA","TWN","TJK","THA","TLS",
                        "TKM","UZB","VNM"]
            case .medioOriente:
                return ["BHR","IRN","IRQ","ISR","JOR","KWT","LBN","OMN","PSE",
                        "QAT","SAU","SYR","TUR","ARE","YEM"]
            case .africa:
                return ["DZA","AGO","BEN","BWA","BFA","BDI","CPV","CMR","CAF","TCD",
                        "COM","COD","COG","CIV","DJI","EGY","GNQ","ERI","ETH","GAB",
                        "GMB","GHA","GIN","GNB","KEN","LSO","LBR","LBY","MDG","MWI",
                        "MLI","MRT","MUS","MAR","MOZ","NAM","NER","NGA","RWA","STP",
                        "SEN","SYC","SLE","SOM","ZAF","SSD","SDN","SWZ","TZA","TGO",
                        "TUN","UGA","ZMB","ZWE"]
            case .america:
                return ["ATG","ARG","BHS","BRB","BLZ","BOL","BRA","CAN","CHL","COL",
                        "CRI","CUB","DMA","DOM","ECU","SLV","GRD","GTM","GUY","HTI",
                        "HND","JAM","MEX","NIC","PAN","PRY","PER","KNA","LCA","VCT",
                        "SUR","TTO","USA","URY","VEN"]
            case .oceania:
                return ["AUS","FJI","KIR","MHL","FSM","NRU","NZL","PLW","PNG","WSM",
                        "SLB","TON","TUV","VUT"]
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
                VStack(spacing: 24) {

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

                    // ── Mi top — tabla región × medalla ──
                    VStack(spacing: 12) {
                        Text("Mi top")
                            .font(.palatino(.title2, weight: .bold))
                            .frame(maxWidth: .infinity, alignment: .center)

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
                            .font(.body)
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
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                countingModeRaw: $countingModeRaw,
                menuPositionRaw: $menuPositionRaw
            )
            .environmentObject(colorTheme)
        }
    }
}

// MARK: - Pantalla de ajustes
struct SettingsSheet: View {
    @Binding var countingModeRaw: String
    @Binding var menuPositionRaw: String

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

                    // Colores
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Colores")
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)

                        VStack(spacing: 0) {
                            ColorPickerRow(label: "Visitado",  color: $colorTheme.visitedColor)
                            Divider().padding(.leading, 56)
                            ColorPickerRow(label: "Próximo",   color: $colorTheme.wantToVisitColor)
                            Divider().padding(.leading, 56)
                            ColorPickerRow(label: "He vivido", color: $colorTheme.livedColor)
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


// MARK: - Lista de todos los territorios (solo lectura)
struct AllCountriesSheet: View {
    let features: [CountryFeature]
    let mode: CountingMode
    @Environment(\.dismiss) private var dismiss

    private var filtered: [CountryFeature] {
        switch mode {
        case .all:    return features
        case .un:     return features.filter { CountingMode.unMembers.contains($0.isoCode) }
        case .unPlus: return features.filter { CountingMode.unMembers.contains($0.isoCode) || CountingMode.unObservers.contains($0.isoCode) }
        }
    }

    private var grouped: [(letter: String, items: [CountryFeature])] {
        let sorted = filtered.sorted { $0.localizedName < $1.localizedName }
        var result: [(letter: String, items: [CountryFeature])] = []
        for feature in sorted {
            let letter = String(
                feature.localizedName
                    .folding(options: .diacriticInsensitive, locale: .current)
                    .prefix(1).uppercased()
            )
            if let idx = result.firstIndex(where: { $0.letter == letter }) {
                result[idx].items.append(feature)
            } else {
                result.append((letter: letter, items: [feature]))
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped, id: \.letter) { section in
                    Section(header: Text(section.letter)
                        .font(.palatino(.caption, weight: .bold))) {
                        ForEach(section.items, id: \.isoCode) { feature in
                            HStack(spacing: 10) {
                                Text(feature.flagEmoji ?? "🌐")
                                    .font(.title3)
                                Text(feature.localizedName)
                                    .font(.palatino(.body))
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("\(mode.label) (\(filtered.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                        .font(.palatino(.body))
                }
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
        VStack(spacing: 10) {
            if isEditing {
                // Fila centrada: @ + campo + ✓
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
                                    .prefix(15)
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
            } else {
                // Modo lectura: @nombre + lápiz estilo igual que el del avatar
                HStack(spacing: 6) {
                    Text(username.isEmpty ? "usuario" : "@ \(username)")
                        .font(.palatino(.title3))
                        .foregroundStyle(username.isEmpty ? .secondary : .primary)
                    ZStack {
                        Circle()
                            .fill(Color(.systemBackground))
                            .frame(width: 30, height: 30)
                        Image(systemName: "pencil.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    .onTapGesture {
                        draft = username
                        isEditing = true
                        focused = true
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
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

