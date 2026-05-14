//
//  YearTravelView.swift
//  Raskmap
//
//  Vista del año en perfil — heatmap mensual, comparativa vs año anterior,
//  contador total de vuelos. Pasada como subview en ProfileSheet.
//  Self-contained: recibe countries/features/trips/year como props.
//
//  Extraído de ContentView.swift durante Fase D.
//

import SwiftUI

// MARK: - Vista de años de viaje en perfil
struct YearTravelView: View {
    let countries: [Country]
    let features: [CountryFeature]
    let trips: [Trip]
    var onProximosTap: (() -> Void)? = nil
    var onFinalizadosTap: ((Int) -> Void)? = nil

    @EnvironmentObject private var colorTheme: ColorThemeManager
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    /// Modo de conteo activo (ONU / ONU+OBS / Todos). Afecta SOLO al
    /// recuento de la card "vs <año anterior>" y al label
    /// (Países / Territorios). El resto del perfil sigue mostrando las
    /// banderas todas independientemente del modo.
    // ⚠️ La clave de AppStorage debe ser "countingMode" (no "countingModeRaw")
    // — es la que usa el resto de la app (ContentView, AwardsSheets, etc.).
    // Antes esta vista leía un key huérfano que NUNCA se escribía desde
    // Ajustes, así que la comparativa "vs año anterior" siempre se quedaba
    // en modo "all" (contando Hong Kong / Macao / etc.) aunque el usuario
    // tuviese ONU o ONU+obs activo. Mantenemos el nombre de variable local
    // `countingModeRaw` por consistencia con el resto de callers.
    @AppStorage("countingMode") private var countingModeRaw: String = CountingMode.all.rawValue
    private var countingMode: CountingMode { CountingMode(rawValue: countingModeRaw) ?? .all }

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

    /// Cuenta trips primarios y países únicos visitados en un año concreto.
    /// La lógica de países se alinea con `WrappedStats.compute()` para que
    /// la comparativa de perfil coincida con el Wrapped:
    /// · Incluimos `segmentChild` trips (escalas guardadas como child).
    /// · Para segments de trips primarios:
    ///   - ✈️: endpoints (primer/último isoCode) + escalas marcadas como
    ///     visitadas vía `visitedLayoverISOs` (checkbox en AddSegmentSheet).
    ///   - Terrestre/marítimo: TODOS los isoCodes (cruzar frontera = visita).
    /// · Dedupe por país (Set).
    /// · **Filtrado por `countingMode`**: en modo `.un` solo cuentan los 193
    ///   miembros ONU; en `.unPlus` los 195 (ONU + observadores); en `.all`
    ///   cualquier territorio. Las banderas siguen mostrándose todas en el
    ///   resto del perfil — este filtro solo afecta este recuento numérico
    ///   de la card "vs <año anterior>".
    private func yearStats(_ year: Int) -> (trips: Int, countries: Int) {
        let cal = Calendar.current
        // Trips count: solo primarios — la convención del proyecto es que
        // un viaje multi-segmento cuenta como 1 trip, no N.
        let primaries = trips.filter { trip in
            !trip.isSegmentChild && cal.component(.year, from: trip.dateFrom) == year
        }
        // Countries: incluye children + segments embebidos del primario.
        var isos = Set<String>()
        // 1) Cualquier trip del año (incluye children) aporta su isoCode.
        for trip in trips where cal.component(.year, from: trip.dateFrom) == year {
            if !trip.isoCode.isEmpty { isos.insert(trip.isoCode) }
        }
        // 2) Segments de trips primarios — capturan ISOs adicionales no
        //    presentes como child trips.
        for trip in primaries {
            for seg in trip.tripSegments {
                let segIsos = seg.isoCodes.filter { !$0.isEmpty }
                guard !segIsos.isEmpty else { continue }
                if seg.transport == "✈️" {
                    // Endpoints
                    if let first = segIsos.first { isos.insert(first) }
                    if segIsos.count > 1, let last = segIsos.last { isos.insert(last) }
                    // Escalas marcadas como visitadas por el usuario
                    for iso in seg.visitedLayoverISOs ?? [] where !iso.isEmpty {
                        isos.insert(iso)
                    }
                } else {
                    // Terrestre/marítimo: todos cuentan (cruzar = visita)
                    for iso in segIsos { isos.insert(iso) }
                }
            }
        }
        // 3) Filtrar por countingMode. Las banderas en el resto de la UI
        //    siguen viéndose todas (Hong Kong, Macao, etc.), pero aquí
        //    el conteo numérico debe respetar la elección del usuario.
        let filtered = isos.filter { countingMode.counts($0) }
        return (primaries.count, filtered.count)
    }

    /// Label de la card "vs año anterior" para el conteo de regiones:
    /// "Países" en modos ONU / ONU+OBS, "Territorios" en modo "Todos".
    /// Coherente con la nomenclatura que usa el resto de la app
    /// (`mode.visitedLabel` ya distingue "Países visitados" vs
    /// "Territorios visitados").
    private var regionLabel: String {
        countingMode == .all ? "Territorios" : "Países"
    }

    @ViewBuilder
    private var yearComparison: some View {
        let prevYear = selectedYear - 1
        if availableYears.contains(prevYear) {
            let cur = yearStats(selectedYear)
            let prev = yearStats(prevYear)
            if cur.trips > 0 || prev.trips > 0 {
                HStack(spacing: 12) {
                    comparisonStat(
                        label: "Viajes",
                        current: cur.trips,
                        previous: prev.trips
                    )
                    Divider().frame(height: 36)
                    comparisonStat(
                        label: regionLabel,
                        current: cur.countries,
                        previous: prev.countries
                    )
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
            }
        }
    }

    @ViewBuilder
    private func comparisonStat(label: String, current: Int, previous: Int) -> some View {
        let delta = current - previous
        let arrow = delta > 0 ? "arrow.up" : (delta < 0 ? "arrow.down" : "minus")
        let arrowColor: Color = delta > 0 ? .green : (delta < 0 ? .red : .secondary)
        VStack(alignment: .center, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(current)")
                    .font(.custom("Satoshi-Bold", size: 16))
                Image(systemName: arrow)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(arrowColor)
                if delta != 0 {
                    Text("\(abs(delta))")
                        .font(.custom("Satoshi-Bold", size: 11))
                        .foregroundStyle(arrowColor)
                }
            }
            Text("vs \(String(selectedYear - 1))")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
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

            // Comparativa con el año anterior si está disponible.
            yearComparison
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
