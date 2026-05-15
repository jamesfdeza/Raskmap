//
//  AddTripSheet.swift
//  Raskmap
//
//  Sheet de añadir viaje (pasado o próximo). Wizard de tramos con
//  modal de confirmación de visitas/aeropuertos/aerolíneas antes
//  de guardar el Trip. Usa AddSegmentSheet (en su propio archivo)
//  y confirmCardContent (en PlannedDatePickerSheet.swift, internal).
//
//  Extraído de ContentView.swift durante Fase D.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Añadir viaje
struct AddTripSheet: View {
    let isoCode: String
    let displayName: String
    let flagEmoji: String
    let features: [CountryFeature]
    var isForFuture: Bool = false
    let onSave: (Trip, [String]) -> Void  // trip + newly visited country names
    var onCancel: (() -> Void)? = nil

    @State private var didSave = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var tripTitle: String = ""
    @State private var tripSegments: [TripSegment] = []
    @State private var showAddSegment = false
    @State private var showSaveConfirmation = false
    @State private var confirmVisits: [VisitEntry] = []
    @State private var confirmAirports: [AirportConfirmEntry] = []
    @State private var confirmAirlines: [AirlineConfirmEntry] = []
    /// Conteo de transportes no-✈️ (tren, coche, bus, etc.). 1 por tramo
    /// sin `dateTo`, 2 por tramo con `dateTo` (incluido mismo día → ida + vuelta).
    @State private var confirmTransports: [TransportConfirmEntry] = []
    @State private var sheetDetent: PresentationDetent = .medium

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.locale = Locale(identifier: "es_ES"); return f
    }()

    // Calculated date range from all segments
    private var calculatedDateFrom: Date {
        tripSegments.map(\.dateFrom).min() ?? Calendar.current.startOfDay(for: Date())
    }
    private var calculatedDateTo: Date? {
        // Fecha explícita si existe; si no, la dateFrom más tardía que supere la de inicio
        let explicit = tripSegments.compactMap(\.dateTo).max()
        if let e = explicit { return e }
        let latestFrom = tripSegments.map(\.dateFrom).max()
        guard let latest = latestFrom, latest > calculatedDateFrom else { return nil }
        return latest
    }

    private func segmentCountryNames(_ seg: TripSegment) -> String {
        if seg.transport == "✈️", let aps = seg.airports, !aps.isEmpty {
            var route = aps.map { $0.iata }.joined(separator: " → ")
            if let retAps = seg.returnAirports, !retAps.isEmpty {
                route += "  /  " + retAps.map { $0.iata }.joined(separator: " → ")
            }
            return route
        }
        return seg.isoCodes.compactMap { iso in features.first { $0.isoCode == iso }?.localizedName }.joined(separator: ", ")
    }

    private func prepareSaveConfirmation() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        guard !tripSegments.isEmpty else { saveTrip(); return }
        var visitCounts: [String: Int] = [:]
        for seg in tripSegments {
            for iso in seg.isoCodes { visitCounts[iso, default: 0] += 1 }
        }
        visitCounts[isoCode] = max(visitCounts[isoCode, default: 0], 1)
        confirmVisits = visitCounts.map { (iso, count) in
            let feat = features.first { $0.isoCode == iso }
            return VisitEntry(isoCode: iso, flagEmoji: feat?.flagEmoji ?? "", name: feat?.localizedName ?? iso, count: count)
        }.sorted { a, b in
            if a.isoCode == isoCode { return true }
            if b.isoCode == isoCode { return false }
            return a.name < b.name
        }
        let apSegs = tripSegments.filter { $0.transport == "✈️" && $0.airports?.isEmpty == false }
        var apC: [String: Int] = [:]
        var alC: [String: Int] = [:]
        var alOrder: [String] = []
        for seg in apSegs {
            let vlISOs = Set(seg.visitedLayoverISOs ?? [])
            // Toques naturales por leg: cada aparición del IATA cuenta una vez.
            for ap in (seg.airports ?? [])       { apC[ap.iata, default: 0] += ap.count }
            for ap in (seg.returnAirports ?? []) { apC[ap.iata, default: 0] += ap.count }
            // Bonus +1 por cada IATA de escala cuyo país esté marcado como
            // visitado. Un solo bonus por IATA (no doblamos si aparece en ida
            // y vuelta — ya tiene 2 toques + 1 bonus = 3, que es lo que pidió
            // el usuario para MAD-SAW-KWI / KWI-SAW-MAD con SAW visitado).
            let outIntermediate = (seg.airports ?? []).dropFirst().dropLast().map { $0.iata }
            let retIntermediate = (seg.returnAirports ?? []).dropFirst().dropLast().map { $0.iata }
            var bonusedIATAs: Set<String> = []
            for iata in outIntermediate + retIntermediate where bonusedIATAs.insert(iata).inserted {
                let a2 = RoutePickerSheet.allAirports.first { $0.iata == iata }?.country ?? ""
                guard let iso = features.first(where: { $0.isoA2 == a2 })?.isoCode,
                      vlISOs.contains(iso) else { continue }
                apC[iata, default: 0] += 1
            }
            for al in (seg.airlines ?? []) {
                if alC[al.name] == nil { alOrder.append(al.name) }
                alC[al.name, default: 0] += al.count
            }
        }
        confirmAirports = apC.map { AirportConfirmEntry(iata: $0.key, count: $0.value) }.sorted { $0.iata < $1.iata }
        confirmAirlines = alOrder.map { AirlineConfirmEntry(name: $0, count: alC[$0] ?? 0) }
        // Conteo de transportes no-✈️. Por cada tramo del mismo emoji:
        //   · sin dateTo → +1.
        //   · con dateTo (mismo día o multi-día) → +2 (ida + vuelta).
        // Preservamos el orden de aparición de cada transporte en los segments
        // para que la card no salte de orden en cada re-render.
        var trC: [String: Int] = [:]
        var trOrder: [String] = []
        let nonFlightSegs = tripSegments.filter { $0.transport != "✈️" && !$0.transport.isEmpty }
        for seg in nonFlightSegs {
            let delta = seg.dateTo != nil ? 2 : 1
            if trC[seg.transport] == nil { trOrder.append(seg.transport) }
            trC[seg.transport, default: 0] += delta
        }
        let labelByEmoji = Dictionary(uniqueKeysWithValues:
            PlannedDatePickerSheet.transports.map { ($0.emoji, $0.label) })
        confirmTransports = trOrder.map { emoji in
            TransportConfirmEntry(emoji: emoji,
                                  label: labelByEmoji[emoji] ?? emoji,
                                  count: trC[emoji] ?? 0)
        }
        withAnimation { sheetDetent = .large }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.25))
            withAnimation { showSaveConfirmation = true }
        }
    }

    private func saveTrip() {
        let trimmed = tripTitle.trimmingCharacters(in: .whitespaces)
        let transport = tripSegments.first?.transport ?? "🌍"
        let airplaneSeg = tripSegments.first(where: { $0.transport == "✈️" && ($0.airports?.isEmpty == false) })
        let finalAirports: [TripAirport]
        let finalAirlines: [TripAirline]
        // Orden cronológico: iteramos segmentos por dateFrom y dentro de cada
        // uno respetamos el orden ida → vuelta. El primer aeropuerto visto
        // gana — así `trip.tripAirports` queda en el orden real del viaje
        // (MAD → KWI → DXB) y NO en orden alfabético del Dictionary o de
        // `confirmAirports.sorted`. Es lo que rendea `legacyAirportRoute`
        // y otros paths que leen `trip.tripAirports`.
        var apOrder: [String] = []
        var seenIatas: Set<String> = []
        for seg in tripSegments.sorted(by: { $0.dateFrom < $1.dateFrom }) where seg.transport == "✈️" {
            for ap in seg.airports ?? [] where seenIatas.insert(ap.iata).inserted { apOrder.append(ap.iata) }
            for ap in seg.returnAirports ?? [] where seenIatas.insert(ap.iata).inserted { apOrder.append(ap.iata) }
        }
        if !confirmAirports.isEmpty || !confirmAirlines.isEmpty {
            // Counts vienen del confirm-dialog; orden cronológico de apOrder.
            let countsByIata = Dictionary(confirmAirports.map { ($0.iata, $0.count) }, uniquingKeysWith: +)
            var ordered: [TripAirport] = apOrder.compactMap { iata in
                guard let count = countsByIata[iata], count > 0 else { return nil }
                return TripAirport(iata: iata, count: count)
            }
            // Defensiva: incluye iatas que el user añadiera en el dialog.
            for entry in confirmAirports where !seenIatas.contains(entry.iata) && entry.count > 0 {
                ordered.append(TripAirport(iata: entry.iata, count: entry.count))
            }
            finalAirports = ordered
            finalAirlines = confirmAirlines.map { TripAirline(name: $0.name, count: $0.count) }
        } else {
            // No hubo confirm-dialog → counts naturales del segmento, mismo orden.
            var apC: [String: Int] = [:]
            for ap in airplaneSeg?.airports ?? [] { apC[ap.iata, default: 0] += 1 }
            for ap in airplaneSeg?.returnAirports ?? [] { apC[ap.iata, default: 0] += 1 }
            finalAirports = apOrder.compactMap { iata in
                guard let count = apC[iata], count > 0 else { return nil }
                return TripAirport(iata: iata, count: count)
            }
            finalAirlines = airplaneSeg?.airlines ?? []
        }
        let trip = Trip(isoCode: isoCode, title: trimmed.isEmpty ? nil : trimmed,
                        dateFrom: calculatedDateFrom, dateTo: calculatedDateTo, transport: transport,
                        tripAirports: finalAirports, tripAirlines: finalAirlines)
        trip.hasLayover = airplaneSeg?.hasLayover ?? false
        trip.tripSegments = tripSegments
        var newlyVisitedNames: [String] = []
        if !tripSegments.isEmpty {
            let groupID = UUID().uuidString
            trip.segmentGroupID = groupID
            let today = Calendar.current.startOfDay(for: Date())
            var countForIso: [String: Int] = [:]
            if !confirmVisits.isEmpty {
                for entry in confirmVisits { countForIso[entry.isoCode] = entry.count }
            } else {
                for seg in tripSegments { for iso in seg.isoCodes { countForIso[iso, default: 0] += 1 } }
                countForIso[isoCode] = max(countForIso[isoCode, default: 0], 1)
            }
            // Extra visits for main country (main trip = 1, extras = count-1)
            let segsForMain = tripSegments.filter { $0.isoCodes.contains(isoCode) }
            let mainCount = countForIso[isoCode] ?? 1
            for i in 0..<(mainCount - 1) {
                let extraSeg = (i + 1) < segsForMain.count ? segsForMain[i + 1] : segsForMain.last
                let extraTransport = extraSeg?.transport ?? transport
                var extraAps: [TripAirport] = []
                var extraAls: [TripAirline] = []
                if extraSeg?.transport == "✈️" {
                    var apC3: [String: Int] = [:]
                    for ap in extraSeg?.airports ?? [] { apC3[ap.iata, default: 0] += 1 }
                    for ap in extraSeg?.returnAirports ?? [] { apC3[ap.iata, default: 0] += 1 }
                    extraAps = apC3.map { TripAirport(iata: $0.key, count: $0.value) }
                    extraAls = extraSeg?.airlines ?? []
                }
                let extra = Trip(isoCode: isoCode, title: trimmed.isEmpty ? nil : trimmed,
                                dateFrom: extraSeg?.dateFrom ?? calculatedDateFrom,
                                dateTo: extraSeg?.dateTo ?? calculatedDateTo,
                                transport: extraTransport, tripAirports: extraAps, tripAirlines: extraAls)
                extra.hasLayover = extraSeg?.hasLayover ?? false
                extra.segmentGroupID = groupID
                extra.isSegmentChild = true
                if let seg = extraSeg { extra.tripSegments = [seg] }
                modelContext.insert(extra)
            }
            // Children for other countries, one per confirmed visit using the matching segment
            for (iso, confirmedCount) in countForIso where iso != isoCode && confirmedCount > 0 {
                let segsWithIso = tripSegments.filter { $0.isoCodes.contains(iso) }
                let firstDate = segsWithIso.first?.dateFrom ?? calculatedDateFrom
                for i in 0..<confirmedCount {
                    let seg = i < segsWithIso.count ? segsWithIso[i] : segsWithIso.last
                    let d = seg?.dateFrom ?? calculatedDateFrom
                    let dTo = seg?.dateTo
                    let t = seg?.transport ?? transport
                    var apC2: [String: Int] = [:]
                    if seg?.transport == "✈️" {
                        for ap in seg?.airports ?? [] { apC2[ap.iata, default: 0] += 1 }
                        for ap in seg?.returnAirports ?? [] { apC2[ap.iata, default: 0] += 1 }
                    }
                    let sAps = seg?.transport == "✈️" ? apC2.map { TripAirport(iata: $0.key, count: $0.value) } : []
                    let sAls = seg?.transport == "✈️" ? (seg?.airlines ?? []) : []
                    let child = Trip(isoCode: iso, title: trimmed.isEmpty ? nil : trimmed,
                                    dateFrom: d, dateTo: dTo, transport: t,
                                    tripAirports: sAps, tripAirlines: sAls)
                    child.hasLayover = seg?.hasLayover ?? false
                    child.segmentGroupID = groupID
                    child.isSegmentChild = true
                    if let seg { child.tripSegments = [seg] }
                    modelContext.insert(child)
                }
                // Mark visited + toast (use first segment's date)
                if Calendar.current.startOfDay(for: firstDate) <= today {
                    let countryIso = iso
                    let desc = FetchDescriptor<Country>(predicate: #Predicate { $0.isoCode == countryIso })
                    if let countryRecord = modelContext.fetchFirstOrWarn(desc) {
                        if countryRecord.status != .visited {
                            countryRecord.status = .visited
                            countryRecord.plannedDate = nil
                            countryRecord.plannedDateTo = nil
                            countryRecord.transport = nil
                        }
                        let feat = features.first { $0.isoCode == iso }
                        let flag = feat?.flagEmoji ?? ""
                        let name = feat?.localizedName ?? iso
                        newlyVisitedNames.append("\(flag) \(name)".trimmingCharacters(in: .whitespaces))
                    }
                } else {
                    // Future trip: promociona child country a wantToVisit y registra plannedDate.
                    let countryIso = iso
                    let desc = FetchDescriptor<Country>(predicate: #Predicate { $0.isoCode == countryIso })
                    let segTransport = segsWithIso.first?.transport
                    let segDateTo = segsWithIso.first?.dateTo
                    if let countryRecord = modelContext.fetchFirstOrWarn(desc) {
                        if countryRecord.status != .visited && countryRecord.status != .lived {
                            countryRecord.status = .wantToVisit
                            if countryRecord.plannedDate.map({ firstDate < $0 }) ?? true {
                                countryRecord.plannedDate = firstDate
                                countryRecord.plannedDateTo = segDateTo
                                countryRecord.transport = segTransport
                            }
                        }
                    } else {
                        let feat = features.first { $0.isoCode == iso }
                        let newCountry = Country(
                            name: feat?.localizedName ?? iso,
                            isoCode: iso,
                            status: .wantToVisit
                        )
                        newCountry.plannedDate = firstDate
                        newCountry.plannedDateTo = segDateTo
                        newCountry.transport = segTransport
                        modelContext.insert(newCountry)
                    }
                }
            }
        }
        didSave = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSave(trip, newlyVisitedNames)
        dismiss()
    }

    var body: some View {
        ZStack {
        NavigationStack {
            ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    FlagLabel(emoji: flagEmoji, size: 20)
                    Text(displayName)
                        .font(.palatino(.title3, weight: .bold))
                }
                .padding(.top, 12).padding(.bottom, 4)

                TextField("Título del viaje", text: $tripTitle)
                    .font(.palatino(.body))
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
                    .padding(.horizontal, 16).padding(.bottom, 8)

                Divider().padding(.horizontal, 16).padding(.vertical, 4)

                // MARK: Tramos adicionales
                VStack(alignment: .leading, spacing: 6) {
                    if !tripSegments.isEmpty {
                        Text("Tramos adicionales")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                        // Orden cronológico (ida → vuelta) independientemente del orden de inserción.
                        ForEach(tripSegments.sorted { $0.dateFrom < $1.dateFrom }) { seg in
                            HStack(spacing: 8) {
                                Text(seg.transport).font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(segmentCountryNames(seg))
                                        .font(.palatino(.caption)).lineLimit(1)
                                    Text(Self.fmt.string(from: seg.dateFrom))
                                        .font(.palatino(.caption)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { tripSegments.removeAll { $0.id == seg.id } } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red.opacity(0.7))
                                }.buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
                            .padding(.horizontal, 16)
                        }
                    }
                    Button { showAddSegment = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill").foregroundStyle(.blue)
                            Text("Añadir transporte").font(.palatino(.body)).foregroundStyle(.blue)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)

                // Auto-calculated date range from segments
                if !tripSegments.isEmpty {
                    HStack(spacing: 16) {
                        VStack(spacing: 2) {
                            Text("DESDE").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            Text(Self.fmt.string(from: calculatedDateFrom))
                                .font(.palatino(.subheadline, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        if let to = calculatedDateTo {
                            VStack(spacing: 2) {
                                Text("HASTA").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                                Text(Self.fmt.string(from: to))
                                    .font(.palatino(.subheadline, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }

                Divider().padding(.horizontal, 16).padding(.top, 4)

                Button { prepareSaveConfirmation() } label: {
                    Text(isForFuture ? "Añadir a Próximos" : "Guardar viaje")
                        .font(.palatino(.body, weight: .bold)).frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: Radius.cell))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24).padding(.vertical, 14)
            } // end VStack
            } // end ScrollView
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle(isForFuture ? "Añadir a Próximos" : "Añadir viaje")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        onCancel?()
                        dismiss()
                    }.font(.palatino(.body))
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $sheetDetent)
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(showSaveConfirmation)
        .onDisappear {
            if !didSave { onCancel?() }
        }
        .sheet(isPresented: $showAddSegment) {
            // `baseIsoCode: isoCode` preselecciona el país del trip en step 2
            // de AddSegmentSheet para transportes no-✈️. El usuario llegó aquí
            // tappeando un país concreto, así que tiene sentido que aparezca
            // ya marcado en la lista de países del tramo.
            AddSegmentSheet(features: features, isForFuture: isForFuture, existingSegments: tripSegments, baseIsoCode: isoCode) { seg in
                tripSegments.append(seg)
                // Mantener el array siempre ordenado por fecha de vuelo,
                // no por orden de inserción — el del 29 aparece antes del 30
                // aunque se añada después.
                tripSegments.sort { $0.dateFrom < $1.dateFrom }
            }
        }
        .appColorScheme()

        if showSaveConfirmation {
            visitConfirmCard(onSave: { showSaveConfirmation = false; saveTrip() },
                             onCancel: { showSaveConfirmation = false })
        }
        } // ZStack
    }

    @ViewBuilder
    private func visitConfirmCard(onSave: @escaping () -> Void, onCancel: @escaping () -> Void) -> some View {
        confirmCardContent(
            confirmVisits: $confirmVisits,
            confirmAirports: $confirmAirports,
            confirmAirlines: $confirmAirlines,
            confirmTransports: $confirmTransports,
            accent: BrandColor.accent,
            onSave: onSave,
            onCancel: onCancel
        )
    }
}
