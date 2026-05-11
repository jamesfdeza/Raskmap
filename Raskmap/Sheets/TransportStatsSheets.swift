//
//  TransportStatsSheets.swift
//  Raskmap
//
//  Estadísticas de transporte y sub-sheets de drill-down:
//  · TransportStatsSheet — pantalla principal "Tus medios" con km
//    volados, top aeropuertos, top aerolíneas, top asientos.
//  · TransportFilter — value type para filtrar por emoji de transporte.
//  · FlightLegsListSheet — drill-down de ✈️ que lista tramos individuales.
//  · TransportTripsListSheet — drill-down de no-✈️ que lista viajes.
//  · CountryTripsSheet — viajes filtrados por país.
//  · TripTitleEditRow — fila inline editable de título de viaje.
//
//  Algunos reciben `[Trip]` como parámetro pero no acceden a state
//  privado de ContentView. Self-contained tras la extracción.
//
//  Extraído de ContentView.swift durante Fase D.
//

import SwiftUI
import SwiftData

// MARK: - Estadísticas de transporte
struct TransportStatsSheet: View {
    let visitedCountries: [Country]
    let trips: [Trip]
    let allFeatures: [CountryFeature]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTransportFilter: (String, String)? = nil
    @State private var showAirportStats = false
    @State private var showAirlineStats = false
    @State private var showSeatStats = false
    @State private var showSeatPositionStats = false
    @State private var showSubscription: Bool = false
    @AppStorage("isRaskmapPro") private var isRaskmapPro: Bool = false

    private let transports = PlannedDatePickerSheet.transports

    private var pastTrips: [Trip] {
        let today = Calendar.current.startOfDay(for: Date())
        return trips.filter { Calendar.current.startOfDay(for: $0.effectiveEndDate) <= today }
    }

    private var counts: [(emoji: String, label: String, count: Int)] {
        // Cuenta TRAMOS (legs), no viajes. Regla clave para el avión:
        //  - 1 vuelo = 1 tramo, es decir 1 despegue + 1 aterrizaje.
        //  - Ida directa MAD→NRT = 1 vuelo.
        //  - Ida con escala MAD→DXB→NRT = 2 vuelos.
        //  - Ida y vuelta directa = 2 vuelos.
        //  - Ida y vuelta ambas con escala = 4 vuelos.
        // Para otros transportes cada `TripSegment` cuenta como 1 uso.
        let today = Calendar.current.startOfDay(for: Date())
        var byKey: [String: Int] = [:]

        func bump(_ emoji: String, _ legs: Int) {
            guard legs > 0 else { return }
            // Normalizamos 🚶 a 🚶🏻 (skin-tone) para agrupar caminatas.
            let key = emoji == "🚶" ? "🚶🏻" : emoji
            byKey[key, default: 0] += legs
        }

        // Recorremos sólo los viajes PRIMARIOS — los `isSegmentChild` son
        // estancias por país, no tramos de transporte (ya cuentan en el
        // primario a través de `tripSegments`).
        for trip in pastTrips where !trip.isSegmentChild {
            let segs = trip.tripSegments
            if segs.isEmpty {
                // Legacy sin segments — nos apoyamos en trip.transport.
                let tr = trip.transport ?? ""
                if tr == "✈️" {
                    // tripAirports es deduplicado con `count` de touches por
                    // aeropuerto (despegue + aterrizaje). legs = sum/2.
                    // Ver comentario detallado en WrappedStats.compute().
                    let totalTouches = trip.tripAirports.reduce(0) { $0 + $1.count }
                    let legs = max(1, totalTouches / 2)
                    bump(tr, legs)
                } else if !tr.isEmpty {
                    bump(tr, 1)
                }
            } else {
                for seg in segs {
                    let tr = seg.transport
                    if tr == "✈️" {
                        let outLegs = max(0, (seg.airports?.count ?? 0) - 1)
                        let retLegs = max(0, (seg.returnAirports?.count ?? 0) - 1)
                        bump(tr, max(1, outLegs + retLegs))
                    } else if !tr.isEmpty {
                        bump(tr, 1)
                    }
                }
            }
        }

        // Países visitados marcados a mano SIN trip asociado (legacy).
        let isoCodesWithPastTrips = Set(pastTrips.map { $0.isoCode })
        for country in visitedCountries {
            guard !isoCodesWithPastTrips.contains(country.isoCode) else { continue }
            let endDate = country.plannedDateTo ?? country.plannedDate
            if let end = endDate, Calendar.current.startOfDay(for: end) > today { continue }
            if let tr = country.transport, !tr.isEmpty {
                bump(tr, 1)
            }
        }

        return transports.compactMap { t -> (emoji: String, label: String, count: Int)? in
            let key = t.emoji == "🚶🏻" ? "🚶🏻" : t.emoji
            let total = byKey[key] ?? 0
            guard total > 0 else { return nil }
            return (t.emoji, t.label, total)
        }.sorted { $0.count > $1.count }
    }

    // Total = suma de los `count` mostrados por transporte (es decir, suma
    // de tramos), para que el "total" cuadre con la lista de barras de la
    // pantalla y no devuelva el nº de Trips primarios.
    private var totalTrips: Int { counts.reduce(0) { $0 + $1.count } }

    // Top airports by count
    private var topAirports: [(iata: String, name: String, country: String, count: Int)] {
        var counts: [String: Int] = [:]
        var lastDate: [String: Date] = [:]

        func add(iata: String, cnt: Int, date: Date) {
            counts[iata, default: 0] += cnt
            if let prev = lastDate[iata] { if date > prev { lastDate[iata] = date } }
            else { lastDate[iata] = date }
        }

        for trip in pastTrips where !trip.isSegmentChild {
            let flightSegs = trip.tripSegments.filter { $0.transport == "✈️" }
            if !flightSegs.isEmpty {
                for seg in flightSegs {
                    var apC: [String: Int] = [:]
                    for ap in seg.airports ?? []       { apC[ap.iata, default: 0] += ap.count }
                    for ap in seg.returnAirports ?? [] { apC[ap.iata, default: 0] += ap.count }
                    for (iata, cnt) in apC { add(iata: iata, cnt: cnt, date: seg.dateFrom) }
                }
            } else if trip.transport == "✈️" {
                for (iata, cnt) in trip.airportCountForStats { add(iata: iata, cnt: cnt, date: trip.dateFrom) }
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

        func add(name: String, cnt: Int, date: Date) {
            counts[name, default: 0] += cnt
            if let prev = lastDate[name] { if date > prev { lastDate[name] = date } }
            else { lastDate[name] = date }
        }

        for trip in pastTrips where !trip.isSegmentChild {
            let flightSegs = trip.tripSegments.filter { $0.transport == "✈️" }
            if !flightSegs.isEmpty {
                for seg in flightSegs {
                    for al in seg.airlines ?? [] { add(name: al.name, cnt: al.count, date: seg.dateFrom) }
                }
            } else if trip.transport == "✈️" {
                for al in trip.tripAirlines where !al.name.isEmpty { add(name: al.name, cnt: al.count, date: trip.dateFrom) }
            }
        }

        return counts.map { ($0.key, $0.value) }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return (lastDate[$0.0] ?? .distantPast) > (lastDate[$1.0] ?? .distantPast)
        }
    }

    private var topSeats: [(seat: String, count: Int)] {
        var counts: [String: Int] = [:]
        for trip in pastTrips where !trip.isSegmentChild {
            let segs = trip.tripSegments
            if segs.isEmpty {
                if trip.transport == "✈️", let info = trip.flightDetails {
                    for leg in info.allLegs where !leg.seatNumber.isEmpty {
                        counts[leg.seatNumber, default: 0] += 1
                    }
                }
            } else {
                for seg in segs where seg.transport == "✈️" {
                    if let info = seg.flightInfo {
                        for leg in info.allLegs where !leg.seatNumber.isEmpty {
                            counts[leg.seatNumber, default: 0] += 1
                        }
                    }
                }
            }
        }
        return counts.map { ($0.key, $0.value) }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0 < $1.0
        }
    }

    private var topSeatPositions: [(position: String, count: Int)] {
        var counts: [String: Int] = [:]
        for trip in pastTrips where !trip.isSegmentChild {
            let segs = trip.tripSegments
            if segs.isEmpty {
                if trip.transport == "✈️", let info = trip.flightDetails {
                    for leg in info.allLegs where !leg.seatPosition.isEmpty {
                        counts[leg.seatPosition, default: 0] += 1
                    }
                }
            } else {
                for seg in segs where seg.transport == "✈️" {
                    if let info = seg.flightInfo {
                        for leg in info.allLegs where !leg.seatPosition.isEmpty {
                            counts[leg.seatPosition, default: 0] += 1
                        }
                    }
                }
            }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    /// Suma de km gran-circular volados en TODOS los segmentos ✈️ (ida + vuelta)
    /// + trips legacy con `tripAirports` consecutivos. Usa `AirportCoordinates`
    /// para resolver IATAs a coordenadas; pares con coords desconocidas se
    /// saltan (no rompen el total).
    private var totalKilometersFlown: Int {
        var total: Double = 0
        func addPair(_ a: String, _ b: String) {
            guard a != b,
                  let ca = AirportCoordinates.coordinate(for: a),
                  let cb = AirportCoordinates.coordinate(for: b) else { return }
            // Haversine en km (R = 6371).
            let lat1 = ca.latitude * .pi / 180, lon1 = ca.longitude * .pi / 180
            let lat2 = cb.latitude * .pi / 180, lon2 = cb.longitude * .pi / 180
            let dLat = lat2 - lat1, dLon = lon2 - lon1
            let h = sin(dLat / 2) * sin(dLat / 2)
                  + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
            let c = 2 * atan2(sqrt(h), sqrt(1 - h))
            total += 6371 * c
        }
        for trip in pastTrips where !trip.isSegmentChild {
            for seg in trip.tripSegments where seg.transport == "✈️" {
                let outs = seg.airports?.map(\.iata) ?? []
                for i in 0..<max(0, outs.count - 1) { addPair(outs[i], outs[i + 1]) }
                let rets = seg.returnAirports?.map(\.iata) ?? []
                for i in 0..<max(0, rets.count - 1) { addPair(rets[i], rets[i + 1]) }
            }
            // Legacy: solo si exactamente 2 aeropuertos (round-trip directo).
            if trip.tripSegments.isEmpty, trip.transport == "✈️", trip.tripAirports.count == 2 {
                addPair(trip.tripAirports[0].iata, trip.tripAirports[1].iata)
                let touches = trip.tripAirports.reduce(0) { $0 + $1.count }
                if touches >= 4 {
                    // Round-trip: cuenta también la vuelta (mismo par).
                    addPair(trip.tripAirports[1].iata, trip.tripAirports[0].iata)
                }
            }
        }
        return Int(total.rounded())
    }

    private static let kmFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.groupingSeparator = "."
        nf.maximumFractionDigits = 0
        return nf
    }()

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

                    // Card de km volados — visible solo si hay vuelos con coordenadas.
                    let km = totalKilometersFlown
                    if km > 0 {
                        HStack(spacing: 12) {
                            Image(systemName: "airplane")
                                .font(.system(size: 22))
                                .foregroundStyle(Color(red: 64/255, green: 114/255, blue: 212/255))
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("KM VOLADOS").font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary).tracking(0.8)
                                Text("\(Self.kmFormatter.string(from: NSNumber(value: km)) ?? "\(km)") km")
                                    .font(.custom("Satoshi-Bold", size: 22))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 18).padding(.vertical, 14)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 24)
                    }

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
                                                    FlagLabel(emoji: flagEmoji(a2), size: 12)
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

                    // ── Cuadrantes asientos / tipo asiento ──
                    HStack(spacing: 12) {
                        Button { showSeatStats = true } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("💺 Asientos").font(.palatino(.caption, weight: .bold)).foregroundStyle(.secondary)
                                if topSeats.isEmpty {
                                    Text("Sin datos").font(.palatino(.caption)).foregroundStyle(.secondary)
                                } else {
                                    ForEach(topSeats.prefix(3), id: \.seat) { s in
                                        HStack {
                                            Text(s.seat).font(.palatino(.caption, weight: .bold))
                                            Spacer()
                                            Text("\(s.count)x").font(.palatino(.caption)).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        Button { showSeatPositionStats = true } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("🪟 Tipo asiento").font(.palatino(.caption, weight: .bold)).foregroundStyle(.secondary)
                                if topSeatPositions.isEmpty {
                                    Text("Sin datos").font(.palatino(.caption)).foregroundStyle(.secondary)
                                } else {
                                    ForEach(topSeatPositions.prefix(3), id: \.position) { p in
                                        HStack {
                                            Text(p.position.capitalized).font(.palatino(.caption)).lineLimit(1)
                                            Spacer()
                                            Text("\(p.count)x").font(.palatino(.caption)).foregroundStyle(.secondary)
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
                .blur(radius: isRaskmapPro ? 0 : 10)
                .allowsHitTesting(isRaskmapPro)
                .overlay {
                    if !isRaskmapPro {
                        Button { showSubscription = true } label: {
                            VStack(spacing: 10) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.purple)
                                Text("Función Pro")
                                    .font(.palatino(.body, weight: .bold))
                                    .foregroundStyle(.purple)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Transporte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
            .sheet(item: Binding(
                get: { selectedTransportFilter.map { TransportFilter(emoji: $0.0, label: $0.1) } },
                set: { _ in selectedTransportFilter = nil }
            )) { filter in
                // Avión → lista de VUELOS (tramos), no trayectos. El resto de
                // transportes siguen mostrando la lista de viajes (1 viaje =
                // 1 fila), que es coherente con cómo `counts` cuenta para
                // esos medios (1 segmento = 1 uso).
                if filter.emoji == "✈️" {
                    FlightLegsListSheet(trips: trips, allFeatures: allFeatures)
                } else {
                    TransportTripsListSheet(transportEmoji: filter.emoji, transportLabel: filter.label, trips: trips, allFeatures: allFeatures)
                }
            }
            .sheet(isPresented: $showAirportStats) {
                AirportStatsSheet(airports: topAirports, allFeatures: allFeatures)
            }
            .sheet(isPresented: $showAirlineStats) {
                AirlineStatsSheet(airlines: topAirlines)
            }
            .sheet(isPresented: $showSeatStats) {
                SeatStatsSheet(seats: topSeats)
            }
            .sheet(isPresented: $showSeatPositionStats) {
                SeatPositionStatsSheet(positions: topSeatPositions)
            }
            .sheet(isPresented: $showSubscription) { SubscriptionSheet() }
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
    var id: String { emoji + label }
    let emoji: String
    let label: String
}

// MARK: - Lista de VUELOS (tramos) — drill-down del ✈️ en "Tus medios"
/// Distinto a `TransportTripsListSheet`: aquí mostramos TRAMOS (legs) de
/// avión, no viajes. Un round-trip con escala = 4 filas (4 vuelos). El usuario
/// pidió expresamente que el drill-down del avión liste vuelos, no trayectos.
struct FlightLegsListSheet: View {
    let trips: [Trip]
    let allFeatures: [CountryFeature]
    @Environment(\.dismiss) private var dismiss

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.locale = Locale(identifier: "es_ES"); return f
    }()

    /// Un tramo de avión = despegue + aterrizaje.
    /// `isSynthetic` marca rows generados por fallback (segmento ✈️ sin
    /// aeropuertos definidos o legacy con datos insuficientes). Sirven para
    /// que `legs.count` coincida con la barra "Avión" de TransportStatsSheet,
    /// que cuenta `max(1, ...)` por segmento — si ocultáramos estos rows el
    /// título mostraría menos vuelos que la barra.
    private struct FlightLeg: Identifiable {
        let id = UUID()
        let originIATA: String
        let destIATA: String
        let date: Date
        let tripTitle: String?
        let tripIsoCode: String
        let airline: String?
        let direction: Direction
        let isSynthetic: Bool
        enum Direction { case outbound, returning }
    }

    /// Filtro alineado con `TransportStatsSheet.pastTrips` (effectiveEndDate <= today)
    /// para que el conteo `legs.count` coincida con la barra "Avión" de la
    /// pantalla anterior.
    private var legs: [FlightLeg] {
        let today = Calendar.current.startOfDay(for: Date())
        var result: [FlightLeg] = []
        for trip in trips where !trip.isSegmentChild {
            guard Calendar.current.startOfDay(for: trip.effectiveEndDate) <= today else { continue }
            let segs = trip.tripSegments.filter { $0.transport == "✈️" }
            if !segs.isEmpty {
                for seg in segs {
                    let airline = seg.airlines?.first?.name
                    let aps = seg.airports ?? []
                    let raps = seg.returnAirports ?? []
                    var addedAny = false
                    // Outbound
                    if aps.count >= 2 {
                        let outDate = seg.dateFrom
                        for i in 0..<(aps.count - 1) {
                            result.append(FlightLeg(
                                originIATA: aps[i].iata,
                                destIATA: aps[i+1].iata,
                                date: outDate,
                                tripTitle: trip.title,
                                tripIsoCode: trip.isoCode,
                                airline: airline,
                                direction: .outbound,
                                isSynthetic: false
                            ))
                            addedAny = true
                        }
                    }
                    // Return
                    if raps.count >= 2 {
                        let retDate = seg.dateTo ?? seg.dateFrom
                        for i in 0..<(raps.count - 1) {
                            result.append(FlightLeg(
                                originIATA: raps[i].iata,
                                destIATA: raps[i+1].iata,
                                date: retDate,
                                tripTitle: trip.title,
                                tripIsoCode: trip.isoCode,
                                airline: airline,
                                direction: .returning,
                                isSynthetic: false
                            ))
                            addedAny = true
                        }
                    }
                    // Fallback: ✈️ sin aeropuertos rellenos. counts.bump usa
                    // max(1, outLegs+retLegs) para estos casos, así que
                    // generamos un row sintético para no perder el conteo.
                    if !addedAny {
                        result.append(FlightLeg(
                            originIATA: "",
                            destIATA: "",
                            date: seg.dateFrom,
                            tripTitle: trip.title,
                            tripIsoCode: trip.isoCode,
                            airline: airline,
                            direction: .outbound,
                            isSynthetic: true
                        ))
                    }
                }
            } else if trip.transport == "✈️" {
                // Legacy sin segments. counts.bump usa max(1, totalTouches/2).
                // Generamos el mismo número de rows aquí.
                let aps = trip.tripAirports
                let totalTouches = aps.reduce(0) { $0 + $1.count }
                let numLegs = max(1, totalTouches / 2)
                let iatas = aps.map { $0.iata }
                if iatas.count == 2 {
                    for i in 0..<numLegs {
                        result.append(FlightLeg(
                            originIATA: i % 2 == 0 ? iatas[0] : iatas[1],
                            destIATA:   i % 2 == 0 ? iatas[1] : iatas[0],
                            date: trip.dateFrom,
                            tripTitle: trip.title,
                            tripIsoCode: trip.isoCode,
                            airline: trip.tripAirlines.first?.name,
                            direction: i % 2 == 0 ? .outbound : .returning,
                            isSynthetic: false
                        ))
                    }
                } else if iatas.count > 2 {
                    // >2 aeropuertos deduplicados sin orden fiable: generamos
                    // numLegs rows alternando consecutivos para que el conteo
                    // coincida con counts.bump(...).
                    for i in 0..<numLegs {
                        let oIdx = i % iatas.count
                        let dIdx = (i + 1) % iatas.count
                        result.append(FlightLeg(
                            originIATA: iatas[oIdx],
                            destIATA: iatas[dIdx],
                            date: trip.dateFrom,
                            tripTitle: trip.title,
                            tripIsoCode: trip.isoCode,
                            airline: trip.tripAirlines.first?.name,
                            direction: i % 2 == 0 ? .outbound : .returning,
                            isSynthetic: false
                        ))
                    }
                } else {
                    // 0 ó 1 aeropuerto: numLegs rows sintéticos.
                    for _ in 0..<numLegs {
                        result.append(FlightLeg(
                            originIATA: iatas.first ?? "",
                            destIATA: "",
                            date: trip.dateFrom,
                            tripTitle: trip.title,
                            tripIsoCode: trip.isoCode,
                            airline: trip.tripAirlines.first?.name,
                            direction: .outbound,
                            isSynthetic: true
                        ))
                    }
                }
            }
        }
        return result.sorted { $0.date > $1.date }
    }

    private func flagEmoji(forIATA iata: String) -> String {
        let a2 = RoutePickerSheet.allAirports.first { $0.iata == iata }?.country ?? ""
        guard a2.count == 2 else { return "🌐" }
        return a2.uppercased().unicodeScalars.compactMap {
            Unicode.Scalar(127397 + $0.value).map { String($0) }
        }.joined()
    }

    var body: some View {
        NavigationStack {
            List {
                if legs.isEmpty {
                    Text("Aún no has registrado vuelos.")
                        .font(.palatino(.body))
                        .foregroundStyle(.secondary)
                        .padding()
                }
                ForEach(legs) { leg in
                    HStack(spacing: 12) {
                        // Banderas origen → destino. En filas sintéticas
                        // (segmento ✈️ sin aeropuertos) caemos al icono ✈️.
                        if leg.isSynthetic {
                            Image(systemName: "airplane")
                                .font(.system(size: 18))
                                .foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .center)
                        } else {
                            HStack(spacing: 4) {
                                FlagLabel(emoji: flagEmoji(forIATA: leg.originIATA), size: 20)
                                Text("→").font(.caption).foregroundStyle(.secondary)
                                FlagLabel(emoji: flagEmoji(forIATA: leg.destIATA), size: 20)
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            if leg.isSynthetic {
                                Text(leg.tripTitle?.isEmpty == false ? (leg.tripTitle ?? "") : "Vuelo sin aeropuertos")
                                    .font(.palatino(.body, weight: .bold))
                                    .lineLimit(1)
                            } else {
                                HStack(spacing: 6) {
                                    Text(leg.originIATA)
                                        .font(.palatino(.body, weight: .bold))
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(leg.destIATA)
                                        .font(.palatino(.body, weight: .bold))
                                }
                            }
                            HStack(spacing: 6) {
                                Text(Self.fmt.string(from: leg.date))
                                    .font(.palatino(.caption))
                                    .foregroundStyle(.secondary)
                                if let airline = leg.airline, !airline.isEmpty {
                                    Text("·")
                                        .font(.palatino(.caption))
                                        .foregroundStyle(.secondary)
                                    Text(airline)
                                        .font(.palatino(.caption))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.plain)
            .navigationTitle("✈️ \(legs.count) \(legs.count == 1 ? "vuelo" : "vuelos")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .presentationDetents([.large])
    }
}


// MARK: - Historial de viajes de un país
struct CountryTripsSheet: View {
    @Bindable var country: Country
    let trips: [Trip]
    let displayName: String
    let flagEmoji: String
    var features: [CountryFeature] = []

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete: Trip? = nil
    @State private var showDeleteConfirm: Bool = false
    @State private var showCounterInfo: Bool = false
    @State private var showLivedHereInfo: Bool = false
    @State private var editingTrip: Trip? = nil
    @State private var sortNewestFirst: Bool = true
    @State private var showSortToast: Bool = false

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.locale = Locale(identifier: "es_ES"); return f
    }()

    private var sortedTrips: [Trip] {
        trips.sorted { a, b in
            sortNewestFirst ? a.dateFrom > b.dateFrom : a.dateFrom < b.dateFrom
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(
                        get: { country.hasLived },
                        set: { country.hasLived = $0; modelContext.saveOrWarn() }
                    )) {
                        HStack(spacing: 6) {
                            Text("He vivido aquí").font(.palatino(.body))
                            Button { showLivedHereInfo = true } label: {
                                Image(systemName: "info.circle")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section(header: Text("Visitas manuales").font(.palatino(.caption, weight: .bold))) {
                    HStack {
                        Text("Contador manual")
                            .font(.palatino(.body))
                        Button {
                            showCounterInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Stepper("\(country.visitCount)", value: Binding(
                            get: { country.visitCount },
                            set: { country.visitCount = $0; modelContext.saveOrWarn() }
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
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        sortNewestFirst.toggle()
                        showSortToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showSortToast = false }
                    } label: {
                        Image(systemName: sortNewestFirst ? "arrow.down.circle" : "arrow.up.circle")
                            .font(.body)
                    }
                }
            }
            .alert("¿Eliminar este viaje?", isPresented: $showDeleteConfirm, presenting: confirmDelete) { trip in
                Button("Eliminar", role: .destructive) {
                    var toDelete: [Trip]
                    if let groupID = trip.segmentGroupID {
                        let desc = FetchDescriptor<Trip>(predicate: #Predicate { $0.segmentGroupID == groupID })
                        toDelete = modelContext.fetchOrWarn(desc, fallback: [trip])
                    } else {
                        toDelete = [trip]
                    }
                    let affectedIsos = Set(toDelete.map { $0.isoCode })
                    for t in toDelete { modelContext.delete(t) }
                    modelContext.saveOrWarn()
                    for iso in affectedIsos {
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
                }
                Button("Cancelar", role: .cancel) {}
            } message: { trip in
                Text("\(Self.fmt.string(from: trip.dateFrom))\(trip.dateTo.map { " → \(Self.fmt.string(from: $0))" } ?? "")")
            }
            .sheet(item: $editingTrip, onDismiss: {
                guard country.status == .wantToVisit else { return }
                let today = Calendar.current.startOfDay(for: Date())
                let iso = country.isoCode
                let desc = FetchDescriptor<Trip>(predicate: #Predicate { $0.isoCode == iso })
                let allTrips = modelContext.fetchOrWarn(desc)
                let futureTrips = allTrips
                    .filter { Calendar.current.startOfDay(for: $0.dateFrom) > today && !$0.isSegmentChild }
                    .sorted { $0.dateFrom < $1.dateFrom }
                if let earliest = futureTrips.first {
                    country.transport = earliest.transport
                    country.plannedDate = earliest.dateFrom
                    country.plannedDateTo = earliest.dateTo
                    country.plannedTitle = earliest.title
                    modelContext.saveOrWarn()
                }
            }) { trip in
                EditTripSheet(trip: trip, features: features)
            }
        }
        .overlay {
            if showCounterInfo {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                        .onTapGesture { showCounterInfo = false }
                    VStack(spacing: 16) {
                        Text("Contador manual")
                            .font(.palatino(.subheadline, weight: .bold))
                        Text("Este contador es para sumar viajes que sabes que has hecho en el pasado a este país o territorio pero no recuerdas los datos para rellenarlo.")
                            .font(.palatino(.body))
                            .multilineTextAlignment(.center)
                        Button {
                            showCounterInfo = false
                        } label: {
                            Text("Cerrar")
                                .font(.palatino(.body, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 32)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showCounterInfo)
        .overlay {
            if showLivedHereInfo {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                        .onTapGesture { showLivedHereInfo = false }
                    VStack(spacing: 16) {
                        Text("He vivido aquí")
                            .font(.palatino(.subheadline, weight: .bold))
                        Text("Marca este país como uno en el que has vivido. Aparecerá una 🏠 junto a su contador en la lista de visitados y se contabiliza como visitado en todas las stats.")
                            .font(.palatino(.body))
                            .multilineTextAlignment(.center)
                        Button {
                            showLivedHereInfo = false
                        } label: {
                            Text("Cerrar")
                                .font(.palatino(.body, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 32)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showLivedHereInfo)
        .overlay {
            if showSortToast {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.white)
                    Text(sortNewestFirst ? "Más recientes primero" : "Más antiguos primero")
                        .font(.palatino(.subheadline, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
                .transition(.opacity.combined(with: .scale))
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSortToast)
        .presentationDetents([.large])
    }

    // Devuelve el trip padre de un child, o nil si no aplica
    private func resolvedParent(for trip: Trip) -> Trip? {
        guard trip.isSegmentChild, let groupID = trip.segmentGroupID else { return nil }
        let desc = FetchDescriptor<Trip>(predicate: #Predicate { t in t.segmentGroupID == groupID && !t.isSegmentChild })
        return modelContext.fetchFirstOrWarn(desc)
    }

    @ViewBuilder
    private func tripRow(_ trip: Trip) -> some View {
        // Para trips hijo (isSegmentChild), mostrar y editar siempre desde el padre
        let display = resolvedParent(for: trip) ?? trip
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(display.transport ?? "🌐").font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    if let t = display.title, !t.isEmpty {
                        Text(t).font(.palatino(.body, weight: .bold))
                    }
                    HStack(spacing: 4) {
                        Text(Self.fmt.string(from: display.dateFrom))
                            .font(.palatino(.caption)).foregroundStyle(.secondary)
                        if let to = display.dateTo {
                            Text("→").font(.palatino(.caption)).foregroundStyle(.secondary)
                            Text(Self.fmt.string(from: to))
                                .font(.palatino(.caption)).foregroundStyle(.secondary)
                        }
                        let tripDay = Calendar.current.startOfDay(for: display.dateFrom)
                        let todayDay = Calendar.current.startOfDay(for: Date())
                        if tripDay > todayDay {
                            let days = Calendar.current.dateComponents([.day], from: todayDay, to: tripDay).day ?? 0
                            Text("\(days)d")
                                .font(.palatino(.caption, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.blue, in: Capsule())
                        }
                    }
                    if display.transport == "✈️" {
                        let flightSeg = display.tripSegments.first(where: { $0.transport == "✈️" && $0.airports?.isEmpty == false })
                        if let seg = flightSeg, let aps = seg.airports, !aps.isEmpty {
                            Text(aps.map(\.iata).joined(separator: " → "))
                                .font(.palatino(.caption, weight: .bold)).foregroundStyle(.blue)
                            if let retAps = seg.returnAirports, !retAps.isEmpty {
                                Text(retAps.map(\.iata).joined(separator: " → "))
                                    .font(.palatino(.caption, weight: .bold)).foregroundStyle(.blue.opacity(0.65))
                            }
                        } else {
                            let aps = display.airports
                            if !aps.isEmpty {
                                Text(aps.joined(separator: " · "))
                                    .font(.palatino(.caption, weight: .bold)).foregroundStyle(.blue)
                            }
                        }
                        let als = display.airlines
                        if !als.isEmpty {
                            Text(als.joined(separator: ", "))
                                .font(.palatino(.caption)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                Spacer()
                Button { confirmDelete = trip; showDeleteConfirm = true } label: {
                    Image(systemName: "trash").foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain).frame(width: 28)
            }
            Button { editingTrip = display } label: {
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
                    modelContext.saveOrWarn()
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
        return trips.filter { trip in
            guard Calendar.current.startOfDay(for: trip.dateFrom) <= today else { return false }
            if trip.isSegmentChild { return matchEmojis.contains(trip.transport ?? "") }
            let segs = trip.tripSegments
            if segs.isEmpty { return matchEmojis.contains(trip.transport ?? "") }
            return segs.contains { seg in matchEmojis.contains(seg.transport) && seg.isoCodes.contains(trip.isoCode) }
        }.sorted { $0.dateFrom > $1.dateFrom }
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
                    FlagLabel(emoji: flagEmoji(for: trip.isoCode), size: 20)
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
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .presentationDetents([.large])
    }
}
