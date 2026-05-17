//
//  ListSheets.swift
//  Raskmap
//
//  Sheets de listas filtradas por estado de país y viajes finalizados:
//  · StatusListSheet — lista de países por estado (visitado, próximo,
//    quiero ir, vivido). Incluye filtrado por transporte para próximos.
//  · FinalizadosListSheet — lista de viajes finalizados de un año,
//    agrupados por mes. Swipe actions de eliminar y duplicar.
//  · FinalizadoTripDetailSheet — detalle de un viaje finalizado.
//
//  Acceden a `[Country]` / `[Trip]` y `ModelContext` vía Environment.
//  Self-contained tras la extracción.
//
//  Extraído de ContentView.swift durante Fase D.
//

import SwiftUI
import SwiftData
import UIKit

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
                                        .accessibilityLabel("Eliminar de la lista")
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
                                        .accessibilityLabel("Eliminar de la lista")
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
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
                        .accessibilityLabel("Borrar lista completa")
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
                .background(active ? BrandColor.accent : Color(.systemGray5),
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
                                        .accessibilityLabel("Eliminar de la lista")
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
            .scrollBounceBehavior(.basedOnSize)
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
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.card))
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

        // Render rich preview: imagen 1080×1080 (cuadrada, óptima para Instagram /
        // WhatsApp / Mensajes) con título + fechas + banderas + días por país.
        // Si el render falla, fallback al share solo con texto.
        var items: [Any] = [text]
        if let preview = renderShareImage() {
            items.insert(preview, at: 0)
        }

        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let key = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else { return }
        var top = key.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        top?.present(av, animated: true)
    }

    /// Renderiza una imagen 1080×1080 con la info principal del viaje para
    /// share enriquecido (preview en Mensajes, Instagram, WhatsApp).
    @MainActor
    private func renderShareImage() -> UIImage? {
        let card = TripShareCard(
            title: headerTitle,
            dateRange: dateRangeText,
            daysByCountry: daysByCountry.map { (
                flag: flagEmoji(for: $0.iso),
                name: displayName(for: $0.iso),
                days: $0.days
            )}
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 1080)
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

// MARK: - Trip share card (rich preview 1:1)
//
// Vista 1080×1080 que se renderiza a UIImage con ImageRenderer para
// compartir junto al texto. Diseño minimalista: fondo gradient azul →
// purpura, título grande, fechas, lista de banderas con días, footer
// Raskmap. Adaptado del estilo del Wrapped pero simplificado.
private struct TripShareCard: View {
    let title: String
    let dateRange: String?
    let daysByCountry: [(flag: String, name: String, days: Int)]

    private static let bgGradient = LinearGradient(
        colors: [
            Color(red: 0x04/255, green: 0x07/255, blue: 0x1F/255),
            Color(red: 0x1C/255, green: 0x10/255, blue: 0x48/255),
            Color(red: 0x52/255, green: 0x20/255, blue: 0x9A/255)
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            Self.bgGradient.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer(minLength: 60)
                Text("✈️")
                    .font(.system(size: 84))
                Text(title)
                    .font(.custom("Satoshi-Bold", size: 56))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                if let dateRange {
                    Text(dateRange)
                        .font(.custom("Satoshi-Medium", size: 22))
                        .foregroundStyle(.white.opacity(0.75))
                }
                if !daysByCountry.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(daysByCountry.prefix(8), id: \.name) { entry in
                            HStack(spacing: 14) {
                                Text(entry.flag).font(.system(size: 36))
                                Text(entry.name)
                                    .font(.custom("Satoshi-Bold", size: 24))
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("\(entry.days) \(entry.days == 1 ? "día" : "días")")
                                    .font(.custom("Satoshi-Medium", size: 20))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                    .padding(.horizontal, 80)
                }
                Spacer()
                VStack(spacing: 4) {
                    Rectangle().fill(Color.white.opacity(0.25))
                        .frame(width: 140, height: 0.8)
                    Text("Raskmap")
                        .font(.custom("Satoshi-Bold", size: 28))
                        .foregroundStyle(.white)
                    Text("Tu mapa personal")
                        .font(.custom("Satoshi-Regular", size: 16))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.bottom, 60)
            }
        }
        .frame(width: 1080, height: 1080)
        .environment(\.colorScheme, .dark)
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
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.card))
        .padding(.horizontal, 20)
    }
}
