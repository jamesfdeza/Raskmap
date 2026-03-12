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
    @State private var profileImage: UIImage? = {
        guard let data = UserDefaults.standard.data(forKey: "profileImageData") else { return nil }
        return UIImage(data: data)
    }()

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
                    // Avatar + título tappable → abre perfil
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

                    HStack(spacing: 8) {
                        StatBadge(value: visitedCount, label: "Visitado",  color: colorTheme.visitedColor)
                            .onTapGesture { statusListFilter = .visited }
                        StatBadge(value: wantCount,    label: "Próximo",   color: colorTheme.wantToVisitColor)
                            .onTapGesture { statusListFilter = .wantToVisit }
                        StatBadge(value: livedCount,   label: "Vivido", color: colorTheme.livedColor)
                            .onTapGesture { statusListFilter = .lived }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 12)
                .padding(.top, 8)
                
                // Contador + lupa
                ZStack {
                    Text("\(visitedCount + livedCount) / \(countingMode.denominator)")
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
        .sheet(item: $selectedCountry) { country in
            CountryBottomSheet(
                country: country,
                displayName: localizedName(for: country),
                onStatusChange: { newStatus in
                    updateCountryStatus(country: country, newStatus: newStatus)
                    selectedCountry = nil
                },
                onDismiss: { selectedCountry = nil }
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
            ProfileSheet(
                username: $username,
                profileImage: $profileImage,
                countingModeRaw: $countingModeRaw
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

        // Caso normal: país ya en SwiftData (segunda apertura o ya visitado antes)
        if let existing = countries.first(where: { $0.isoCode == isoCode }) {
            selectedCountry = existing
            return
        }

        // Primera vez viendo este país: insertar + save + esperar a @Query
        modelContext.insert(tapped)
        try? modelContext.save()

        // @Query se actualiza en el próximo ciclo del RunLoop tras el save.
        // DispatchQueue.main.async garantiza que esperamos ese ciclo completo.
        DispatchQueue.main.async {
            if let saved = self.countries.first(where: { $0.isoCode == isoCode }) {
                self.selectedCountry = saved
            }
        }
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

    @EnvironmentObject private var colorTheme: ColorThemeManager
    @State private var showRemoveConfirm = false

    var body: some View {
        VStack(spacing: 20) {
            Text(displayName)
                .font(.palatino(.title2, weight: .bold))
                .padding(.top, 36)

            VStack(spacing: 10) {
                ActionButton(
                    label: "✅ Visitado",
                    color: colorTheme.visitedColor,
                    isSelected: country.status == .visited,
                    action: {
                        if country.status == .visited { showRemoveConfirm = true }
                        else { onStatusChange(.visited) }
                    }
                )
                ActionButton(
                    label: "🔵 Próximo",
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
                Button("✕  Desmarcar") {
                    if country.status != .none { showRemoveConfirm = true }
                }
                .font(.palatino(.subheadline))
                .foregroundStyle(country.status == .none ? .tertiary : .secondary)
                .padding(.top, 2)
                .disabled(country.status == .none)
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

    @EnvironmentObject private var colorTheme: ColorThemeManager
    @Environment(\.dismiss) private var dismiss
    @State private var usernameInput: String = ""
    @State private var showImagePicker: Bool = false
    @State private var usernameError: String? = nil
    @State private var showSavedToast: Bool = false
    @State private var showCountingToast: Bool = false

    private var countingMode: CountingMode { CountingMode(rawValue: countingModeRaw) ?? .all }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
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

                    // Campo de nombre de usuario
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nombre de usuario")
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            HStack {
                                Text("@")
                                    .font(.palatino(.body))
                                    .foregroundStyle(.secondary)
                                TextField("usuario", text: $usernameInput)
                                    .font(.palatino(.body))
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .onChange(of: usernameInput) {
                                        usernameInput = String(
                                            usernameInput
                                                .lowercased()
                                                .filter { $0.isLetter || $0.isNumber || $0 == "_" }
                                                .prefix(15)
                                        )
                                        usernameError = nil
                                    }
                            }
                            .padding(12)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))

                            Button {
                                let clean = usernameInput.trimmingCharacters(in: .whitespaces)
                                if clean.isEmpty {
                                    usernameError = "El nombre no puede estar vacío."
                                } else {
                                    username = clean
                                    showSavedToast = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                        dismiss()
                                    }
                                }
                            } label: {
                                Text("Guardar")
                                    .font(.palatino(.footnote, weight: .bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 12)
                                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(.white)
                            }
                        }

                        if let err = usernameError {
                            Text(err)
                                .font(.palatino(.caption))
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 24)

                    // Sección de conteo
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Conteo de territorios/países:")
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            ForEach(CountingMode.allCases, id: \.self) { mode in
                                Button {
                                    countingModeRaw = mode.rawValue
                                    showCountingToast = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                        showCountingToast = false
                                    }
                                } label: {
                                    Text(mode.label)
                                        .font(.palatino(.footnote, weight: countingMode == mode ? .bold : .regular))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            countingMode == mode
                                                ? Color.blue
                                                : Color(.systemGray5),
                                            in: RoundedRectangle(cornerRadius: 10)
                                        )
                                        .foregroundStyle(countingMode == mode ? .white : .primary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    // Colores por categoría
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Colores")
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)

                        VStack(spacing: 0) {
                            ColorPickerRow(label: "Viajado",   color: $colorTheme.visitedColor)
                            Divider().padding(.leading, 56)
                            ColorPickerRow(label: "Próximo",   color: $colorTheme.wantToVisitColor)
                            Divider().padding(.leading, 56)
                            ColorPickerRow(label: "He vivido", color: $colorTheme.livedColor)
                        }
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 24)
                    }

                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                        .font(.palatino(.body))
                }
            }
            .onAppear { usernameInput = username }
            .overlay {
                if showSavedToast || showCountingToast {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white)
                        Text(showSavedToast ? "Nombre actualizado" : "Se ha actualizado el conteo")
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
            .animation(.easeInOut(duration: 0.2), value: showCountingToast)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(image: $profileImage)
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
