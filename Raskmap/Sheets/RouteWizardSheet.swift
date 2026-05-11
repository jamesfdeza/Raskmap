//
//  RouteWizardSheet.swift
//  Raskmap
//
//  Wizard multi-paso para configurar rutas de vuelo (✈️):
//  · RouteWizardSheet — outbound + return + airlines + layover toggle.
//  · RoutePickerSheet — picker individual de aeropuerto.
//  · AirlinePickerSheet — picker multi-select de aerolíneas con conteo.
//
//  Self-contained — bindings de los arrays se pasan desde el caller
//  (AddSegmentSheet, EditTripSheet, PlannedDatePickerSheet). No accede
//  a state privado de ContentView.
//
//  Extraído de ContentView.swift durante Fase D.
//

import SwiftUI

// MARK: - Route wizard (multi-step)
struct RouteWizardSheet: View {
    @Binding var airports: [TripAirport]        // outbound route (ordered)
    @Binding var returnAirports: [TripAirport]  // return route (ordered), empty = one-way
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
        case returnSameRouteAirline  // aerolínea por tramo para misma ruta de vuelta con escalas
    }

    @State private var step: Step = .departure
    @State private var departureIata = ""
    @State private var layoverStops: [(iata: String, airline: String)] = []
    @State private var pendingLayoverIata = ""
    @State private var finalIata = ""
    @State private var finalAirline = ""
    @State private var returnAirlineDraft = ""
    @State private var returnDepartureIata = ""
    @State private var returnSameRouteAirlineIdx: Int = 0  // índice del tramo de vuelta en curso
    @State private var returnLayoverStops: [(iata: String, airline: String)] = []
    @State private var returnPendingLayoverIata = ""
    @State private var returnFinalIata = ""
    @State private var returnFinalAirline = ""
    @State private var query = ""
    @State private var didPrepopulate = false

    @AppStorage("favoriteAirport") private var favoriteAirport: String = ""

    private static let allAirports = RoutePickerSheet.allAirports
    private static var allAirlines: [AirlineData] { AirlinePickerSheet.airlines }

    // Back-navigation target for each step
    private var backStep: Step? {
        switch step {
        case .departure:              return nil
        case .layoverChoice:          return .departure
        case .layoverList:            return .layoverChoice
        case .layoverAddAirport:      return layoverStops.isEmpty ? .layoverChoice : .layoverList
        case .layoverAddAirline:      return .layoverAddAirport
        case .finalDest:              return layoverStops.isEmpty ? .layoverChoice : .layoverList
        case .finalAirline:           return .finalDest
        case .returnChoice:           return .finalAirline
        case .returnAirlineChoice:    return .returnChoice
        case .returnAirline:          return .returnAirlineChoice
        case .returnDeparture:        return .returnChoice
        case .returnLayoverChoice:    return .returnDeparture
        case .returnLayoverList:      return .returnLayoverChoice
        case .returnLayoverAddAirport: return returnLayoverStops.isEmpty ? .returnLayoverChoice : .returnLayoverList
        case .returnLayoverAddAirline: return .returnLayoverAddAirport
        case .returnFinalDest:        return returnLayoverStops.isEmpty ? .returnLayoverChoice : .returnLayoverList
        case .returnFinalAirline:     return .returnFinalDest
        case .returnSameRouteAirline: return .returnAirlineChoice  // se usa solo si idx==0; goBack() lo gestiona
        }
    }

    private func goBack() {
        if step == .returnSameRouteAirline {
            if returnSameRouteAirlineIdx > 0 {
                returnSameRouteAirlineIdx -= 1
                if returnSameRouteAirlineIdx < returnLayoverStops.count {
                    returnLayoverStops[returnSameRouteAirlineIdx].airline = ""
                } else {
                    returnFinalAirline = ""
                }
                query = ""; return
            } else {
                query = ""; step = .returnAirlineChoice; return
            }
        }
        guard let prev = backStep else { dismiss(); return }
        if step == .layoverAddAirline { pendingLayoverIata = "" }
        if step == .returnLayoverAddAirline { returnPendingLayoverIata = "" }
        query = ""
        step = prev
    }

    private var filteredAirports: [AirportData] {
        if query.isEmpty { return Self.allAirports }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return Self.allAirports.filter {
            $0.iata.range(of: query, options: opts) != nil ||
            $0.name.range(of: query, options: opts) != nil ||
            $0.city.range(of: query, options: opts) != nil ||
            $0.countryName.range(of: query, options: opts) != nil
        }
    }

    private func airportListForStep(showFavorite: Bool) -> [AirportData] {
        var list = filteredAirports
        guard showFavorite && query.isEmpty && !favoriteAirport.isEmpty else { return list }
        list.removeAll { $0.iata == favoriteAirport }
        if let fav = Self.allAirports.first(where: { $0.iata == favoriteAirport }) {
            list.insert(fav, at: 0)
        }
        return list
    }

    private var filteredAirlines: [AirlineData] {
        if query.isEmpty { return Self.allAirlines }
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
        case .returnSameRouteAirline:
            let total = returnLayoverStops.count + 1
            return "Vuelta · Aerolínea \(returnSameRouteAirlineIdx + 1)/\(total)"
        }
    }

    private func buildAndSave(isReturn: Bool, differentReturnAirline: String? = nil) {
        let outbound = [departureIata] + layoverStops.map(\.iata) + [finalIata]
        // Outbound airports stored in order (count=1 each, stats computed later from both legs)
        airports = outbound.map { TripAirport(iata: $0, count: 1) }
        // Return route: outbound reversed (same path back)
        returnAirports = isReturn ? outbound.reversed().map { TripAirport(iata: $0, count: 1) } : []
        let mult = (isReturn && differentReturnAirline == nil) ? 2 : 1
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
        // Store each leg separately in order — destination = outbound.last, layovers = intermediates of each leg
        airports = outbound.map { TripAirport(iata: $0, count: 1) }
        returnAirports = returning.map { TripAirport(iata: $0, count: 1) }
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
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if backStep == nil {
                        Button("Cancelar") { dismiss() }.font(.palatino(.body))
                    } else {
                        Button("Atrás") { goBack() }.font(.palatino(.body))
                    }
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

            // Algunos trips legacy guardan los aeropuertos como ruta expandida
            // tipo [MAD, ARN, MAD] o [MAD, ARN, ARN] (vuelo directo round-trip
            // representado como path completo). Si detectamos que el último
            // aeropuerto duplica al primero o al penúltimo, lo recortamos:
            // tomamos como ruta de IDA la mitad que NO repite y dejamos el
            // resto a `returnAirports` (si lo hay) — la wizard reconstruye
            // la vuelta cuando el usuario lo confirma.
            var trimmed = aps.map { $0.iata }
            // Caso: ruta termina volviendo al origen (round-trip expandido).
            if trimmed.count >= 3, trimmed.first == trimmed.last {
                // Quédate con la mitad de IDA: hasta el "punto medio" (último
                // aeropuerto antes de empezar a volver). Para [MAD, ARN, MAD]
                // → [MAD, ARN]. Para [MAD, FRA, ARN, FRA, MAD] → [MAD, FRA, ARN].
                if trimmed.count % 2 == 1 {
                    let mid = trimmed.count / 2
                    trimmed = Array(trimmed.prefix(mid + 1))
                } else {
                    // Par: ambigüo, recortamos el último para no duplicar.
                    trimmed = Array(trimmed.dropLast())
                }
            }
            // Caso: el último iata aparece dos veces seguidas al final
            // ([MAD, ARN, ARN] — bug histórico). Dedupea consecutivos.
            var dedup: [String] = []
            for iata in trimmed {
                if dedup.last != iata { dedup.append(iata) }
            }
            trimmed = dedup
            guard trimmed.count >= 2 else { return }

            departureIata = trimmed[0]
            finalIata = trimmed[trimmed.count - 1]
            let middle = Array(trimmed[1..<max(1, trimmed.count - 1)])
            layoverStops = middle.enumerated().map { i, iata in
                (iata: iata, airline: i < als.count ? als[i].name : "")
            }
            let lastIdx = middle.count
            finalAirline = lastIdx < als.count ? als[lastIdx].name : (als.last?.name ?? "")
        }
        .appColorScheme()
    }

    @ViewBuilder private var stepView: some View {
        switch step {
        case .departure:
            airportSearch(hint: "Ciudad, aeropuerto o IATA", showFavorite: true) { iata in
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
            airportSearch(hint: "Ciudad, aeropuerto o IATA", showFavorite: true) { iata in
                returnFinalIata = iata; query = ""; step = .returnFinalAirline
            }
        case .returnFinalAirline:
            airlineSearch(hint: "Aerolínea") { name in
                returnFinalAirline = name; query = ""
                buildAndSaveWithReturnRoute()
            }
        case .returnSameRouteAirline:
            // Pide aerolínea para cada tramo de vuelta (misma ruta, aerolíneas distintas)
            airlineSearch(hint: "Aerolínea") { name in
                if returnSameRouteAirlineIdx < returnLayoverStops.count {
                    returnLayoverStops[returnSameRouteAirlineIdx].airline = name
                    returnSameRouteAirlineIdx += 1
                    query = ""
                    // El step no cambia — el índice actualizado re-renderiza el título
                } else {
                    returnFinalAirline = name
                    query = ""
                    buildAndSaveWithReturnRoute()
                }
            }
        }
    }

    // ── Return airline choice ──
    private var returnAirlineChoiceView: some View {
        VStack(spacing: 24) {
            Spacer()
            if layoverStops.isEmpty {
                // Vuelo directo: misma o diferente aerolínea
                Text("¿Misma aerolínea a la vuelta?")
                    .font(.palatino(.title3, weight: .bold)).multilineTextAlignment(.center)
                if !finalAirline.isEmpty {
                    Text(finalAirline).font(.palatino(.subheadline)).foregroundStyle(.secondary)
                }
            } else {
                // Vuelo con escalas: mostrar resumen de tramos de ida
                Text("¿Mismas aerolíneas en todos los tramos?")
                    .font(.palatino(.title3, weight: .bold)).multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(layoverStops.indices, id: \.self) { i in
                        let prev = i == 0 ? departureIata : layoverStops[i - 1].iata
                        let stop = layoverStops[i]
                        HStack(spacing: 4) {
                            Text("\(prev) → \(stop.iata)").font(.palatino(.caption, weight: .bold))
                            if !stop.airline.isEmpty {
                                Text("· \(stop.airline)").font(.palatino(.caption)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    let lastFrom = layoverStops.last?.iata ?? departureIata
                    HStack(spacing: 4) {
                        Text("\(lastFrom) → \(finalIata)").font(.palatino(.caption, weight: .bold))
                        if !finalAirline.isEmpty {
                            Text("· \(finalAirline)").font(.palatino(.caption)).foregroundStyle(.secondary)
                        }
                    }
                }.padding(.horizontal, 32)
            }
            VStack(spacing: 12) {
                Button { buildAndSave(isReturn: true) } label: {
                    Text("Sí, las mismas")
                        .font(.palatino(.body, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                Button {
                    if layoverStops.isEmpty {
                        query = ""; step = .returnAirline
                    } else {
                        // Flujo secuencial: pre-poblar la ruta de vuelta invertida y pedir aerolínea por tramo
                        returnDepartureIata = finalIata
                        returnFinalIata = departureIata
                        returnLayoverStops = layoverStops.reversed().map { (iata: $0.iata, airline: "") }
                        returnSameRouteAirlineIdx = 0
                        query = ""; step = .returnSameRouteAirline
                    }
                } label: {
                    Text(layoverStops.isEmpty ? "No, diferente aerolínea" : "No, introduzco tramo a tramo")
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
    private func airportSearch(hint: String, showFavorite: Bool = false, onSelect: @escaping (String) -> Void) -> some View {
        let airports = airportListForStep(showFavorite: showFavorite)
        let fav = favoriteAirport
        VStack(spacing: 0) {
            searchBar(placeholder: hint)
            Divider()
            List(airports, id: \.iata) { ap in
                Button { onSelect(ap.iata) } label: {
                    HStack(spacing: 10) {
                        FlagLabel(emoji: ap.flagEmoji, size: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                if showFavorite && ap.iata == fav && query.isEmpty {
                                    Text("⭐️").font(.caption2)
                                }
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
                Button {
                    // Vuelo directo = sin escalas. Si veníamos del prepopulate
                    // o de un cambio de modo, limpiamos las escalas para que
                    // no se cuele un layover heredado dentro de la ruta directa
                    // (bug MAD→ARN→ARN cuando airports legacy = [MAD, ARN, MAD/ARN]).
                    layoverStops = []
                    query = ""; step = .finalDest
                } label: {
                    Text("✈️  Vuelo directo")
                        .font(.palatino(.body, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                Button { query = ""; step = .layoverAddAirport } label: {
                    Text("🔄  Con escala(s)")
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
                            FlagLabel(emoji: ap?.flagEmoji ?? "🌐", size: 20)
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
                    // Siempre pasa por returnAirlineChoice para preguntar la aerolínea
                    query = ""; step = .returnAirlineChoice
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
                    // Pre-fill: la salida de la vuelta es típicamente el último
                    // aeropuerto del outbound (auto-detect). El destino de la
                    // vuelta es típicamente el origen (favorito/casa). El usuario
                    // puede sobrescribir si la ruta es asimétrica de verdad.
                    returnDepartureIata = finalIata
                    returnFinalIata = departureIata
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
                Button {
                    // Limpieza simétrica al `layoverChoiceView` — evita que
                    // cualquier escala heredada se cuele en la vuelta directa.
                    returnLayoverStops = []
                    query = ""; step = .returnFinalDest
                } label: {
                    Text("✈️  Vuelo directo")
                        .font(.palatino(.body, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                Button { query = ""; step = .returnLayoverAddAirport } label: {
                    Text("🔄  Con escala(s)")
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
                            FlagLabel(emoji: ap?.flagEmoji ?? "🌐", size: 20)
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
                                FlagLabel(emoji: apData?.flagEmoji ?? "🌐", size: 20)
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
                            FlagLabel(emoji: ap.flagEmoji, size: 20)
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
            .toolbarBackground(.visible, for: .navigationBar)
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
            .toolbarBackground(.visible, for: .navigationBar)
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

