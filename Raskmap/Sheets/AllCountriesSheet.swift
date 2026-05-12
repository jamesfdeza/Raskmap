//
//  AllCountriesSheet.swift
//  Raskmap
//
//  Sheet de "Todos los territorios visitados" con búsqueda, filtros
//  por región, gestos de swipe (eliminar, editar visit count, añadir
//  viaje, ver viajes). Las private extensions con los modificadores
//  @ViewBuilder se mantienen aquí dentro del archivo para que sigan
//  siendo accesibles a la struct.
//
//  Extraído de ContentView.swift durante Fase D.
//

import SwiftUI
import SwiftData

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
                                        .accessibilityLabel("Información sobre la lista")
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
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: Radius.cell))
                                .foregroundStyle(.white)
                        }.buttonStyle(.plain)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.section))
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
                modelContext.saveOrWarn()
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
                    modelContext.saveOrWarn()
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
            .accessibilityLabel("Añadir viaje")
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.callout)
                    .foregroundStyle(.red.opacity(0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Eliminar país")
        }
        .padding(.vertical, 3)
    }
}
