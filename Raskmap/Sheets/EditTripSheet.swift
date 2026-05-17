//
//  EditTripSheet.swift
//  Raskmap
//
//  Sheet de editar un viaje existente. Permite editar título, transporte,
//  fechas, aeropuertos/aerolíneas (✈️), escalas (legacy + segments) y
//  detalles de vuelo por leg. Reusa confirmCardContent al guardar.
//
//  Extraído de ContentView.swift durante Fase D.
//

import SwiftUI
import SwiftData
import UIKit
import PhotosUI

// MARK: - Editar viaje existente (desde lista Próximos)
struct EditTripSheet: View {
    @Bindable var trip: Trip
    let isForFuture: Bool
    let features: [CountryFeature]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTransport: String?
    @State private var tripTitle: String
    /// Notas largas — espejo del campo `trip.notes`. Se inicializa en init
    /// con el valor actual y se persiste en `performEditSave()`.
    @State private var tripNotes: String
    /// Fotos del trip — array de JPEG Data. Espejo de `trip.photos`.
    @State private var tripPhotos: [Data]
    /// Selección actual del PhotosPicker, transitorio.
    @State private var photosPickerItems: [PhotosPickerItem] = []
    /// Tags del viaje — string libre separado por comas (espejo de trip.tags).
    @State private var tripTagsText: String
    @State private var localDateFrom: Date
    @State private var localDateTo: Date?
    @State private var tripSegments: [TripSegment] = []
    @State private var showAddSegment = false
    @State private var editingSegment: TripSegment? = nil
    @State private var showSaveConfirmation = false
    @State private var confirmVisits: [VisitEntry] = []
    @State private var confirmAirports: [AirportConfirmEntry] = []
    @State private var confirmAirlines: [AirlineConfirmEntry] = []
    /// Conteos por emoji de transportes no-✈️ para la card de confirmación.
    /// Regla por tramo: `dateTo == nil` → +1; `dateTo != nil` → +2 (ida + vuelta,
    /// incluyendo mismo-día). N tramos del mismo emoji se acumulan.
    @State private var confirmTransports: [TransportConfirmEntry] = []
    @State private var localAirports: [TripAirport] = []
    @State private var localReturnAirports: [TripAirport] = []
    @State private var localAirlines: [TripAirline] = []
    @State private var localHasLayover: Bool = false
    @State private var showRoutePicker: Bool = false
    @State private var localFlightInfo: FlightInfo = FlightInfo()
    /// IDs de segmentos cuyo panel "Detalles del vuelo" (asiento, posición, clase) está
    /// desplegado inline dentro de TRAMOS. Sólo aplica a segmentos ✈️.
    @State private var expandedSegmentIDs: Set<UUID> = []
    /// Toggles de escalas IDA/VUELTA para trips ✈️ legacy SIN segmentos. Se
    /// reconstruyen tras cada paso por `RouteWizardSheet` y se persisten en
    /// `trip.visitedLayoverISOs` al guardar. Para trips segment-based esto
    /// queda vacío — la edición pasa por AddSegmentSheet.
    @State private var legacyOutboundLayovers: [LayoverChoice] = []
    @State private var legacyReturnLayovers: [LayoverChoice] = []
    @State private var legacyVisitedLayoverISOs: Set<String> = []

    /// Binding que apunta al `flightInfo` del segmento con el id dado, materializando
    /// `nil` como `FlightInfo()` para edición y volviendo a `nil` cuando queda vacío.
    /// Usado por los `FlightInfoSection` inline en TRAMOS.
    private func segmentFlightInfoBinding(for segmentID: UUID) -> Binding<FlightInfo> {
        Binding(
            get: {
                tripSegments.first(where: { $0.id == segmentID })?.flightInfo ?? FlightInfo()
            },
            set: { newValue in
                guard let idx = tripSegments.firstIndex(where: { $0.id == segmentID }) else { return }
                tripSegments[idx].flightInfo = newValue.hasAnyData ? newValue : nil
            }
        )
    }

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.locale = Locale.current; return f
    }()

    private static let segFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.locale = Locale.current; return f
    }()

    /// Sección visual de toggles de escalas en el flujo legacy. Replica la
    /// estética de `AddSegmentSheet.layoverSection` pero usa
    /// `legacyVisitedLayoverISOs` como single source of truth. Title opcional
    /// (ya no separamos por dirección — un solo toggle por país).
    @ViewBuilder
    private func legacyLayoverSection(title: String?, choices: [LayoverChoice]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.85))
                    .tracking(0.8)
            }
            ForEach(choices) { choice in
                let checked = legacyVisitedLayoverISOs.contains(choice.isoA3)
                Button {
                    if checked { legacyVisitedLayoverISOs.remove(choice.isoA3) }
                    else       { legacyVisitedLayoverISOs.insert(choice.isoA3) }
                } label: {
                    HStack(spacing: 12) {
                        FlagLabel(emoji: choice.flag ?? "🌐", size: 22)
                        Text(choice.name).font(.palatino(.body)).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(checked ? accent : Color(.systemGray3))
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Reconstruye los toggles de escalas a partir de `localAirports` /
    /// `localReturnAirports`. Excluye país de salida y destino — solo aparecen
    /// los aeropuertos intermedios. Llamada al onAppear y tras cada wizard.
    private func deriveLegacyFlightCountries() {
        let allAps = RoutePickerSheet.allAirports

        func featureByA2(_ a2: String?) -> CountryFeature? {
            guard let a2 else { return nil }
            return features.first { $0.isoA2 == a2 }
        }

        let outRoute = effectiveFlightRoutes.outbound
        let retRoute = effectiveFlightRoutes.returnRt
        let departureA2 = allAps.first(where: { $0.iata == outRoute.first })?.country
        let destinationA2 = allAps.first(where: { $0.iata == outRoute.last })?.country
        let departureFeature = featureByA2(departureA2)
        let destinationFeature = featureByA2(destinationA2)

        let excludedISOs: Set<String> = Set(
            [departureFeature?.isoCode, destinationFeature?.isoCode].compactMap { $0 }
        )

        // Lista única deduplicada — un país aparece una sola vez aunque sea
        // escala en ida y vuelta (visitar es por país, no por dirección).
        // Preserva orden de primera aparición (ida primero, luego vuelta).
        var seen = excludedISOs
        var combined: [LayoverChoice] = []
        func addRoute(_ route: [String]) {
            guard route.count > 2 else { return }
            for iata in route.dropFirst().dropLast() {
                guard let a2 = allAps.first(where: { $0.iata == iata })?.country,
                      let f = featureByA2(a2),
                      seen.insert(f.isoCode).inserted else { continue }
                combined.append(LayoverChoice(
                    id: "lay_\(f.isoCode)", isoA3: f.isoCode,
                    flag: f.flagEmoji, name: f.localizedName))
            }
        }
        addRoute(outRoute)
        addRoute(retRoute)

        legacyOutboundLayovers = combined
        legacyReturnLayovers = []

        // Filtra el set persistido contra las escalas que realmente existen
        // en la ruta actual — evita ISOs huérfanas si el usuario reroutea.
        let realISOs = Set(combined.map(\.isoA3))
        legacyVisitedLayoverISOs = legacyVisitedLayoverISOs.intersection(realISOs)
    }

    /// Rutas efectivas de IDA y VUELTA para los trips ✈️ legacy sin segmentos.
    /// Si `localReturnAirports` viene poblado (segment-based o user añadió la
    /// vuelta vía wizard) lo usamos tal cual. Si está vacío pero `localAirports`
    /// luce como round-trip directo legacy ([MAD(c=2), ARN(c=2)]) sintetizamos
    /// la vuelta como ida invertida — solo para UI: el `FlightInfoSection`
    /// genera entonces N editores ida + N editores vuelta. La sintetización NO
    /// toca el @State, así que el save sigue persistiendo `localAirports` como
    /// estaba (counts=2 each) y no doblamos el conteo de aeropuertos.
    private var effectiveFlightRoutes: (outbound: [String], returnRt: [String]) {
        let outIatas = localAirports.map { $0.iata }
        if !localReturnAirports.isEmpty {
            return (outIatas, localReturnAirports.map { $0.iata })
        }
        // Heurística round-trip legacy: ≥2 aeropuertos y todos con count ≥ 2.
        let isLikelyRoundTrip = localAirports.count >= 2 &&
                                localAirports.allSatisfy { $0.count >= 2 }
        return isLikelyRoundTrip ? (outIatas, Array(outIatas.reversed())) : (outIatas, [])
    }

    // Calculated date range: from segments when present, else from local pickers
    private var calculatedDateFrom: Date {
        tripSegments.map(\.dateFrom).min() ?? localDateFrom
    }
    private var calculatedDateTo: Date? {
        if !tripSegments.isEmpty {
            let explicit = tripSegments.compactMap(\.dateTo).max()
            if let e = explicit { return e }
            let latestFrom = tripSegments.map(\.dateFrom).max()
            guard let latest = latestFrom, latest > calculatedDateFrom else { return nil }
            return latest
        }
        return localDateTo
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

    init(trip: Trip, isForFuture: Bool = false, features: [CountryFeature] = []) {
        self.trip = trip
        self.isForFuture = isForFuture
        self.features = features
        // Estado en memoria siempre ordenado cronológicamente (el getter del
        // modelo ya ordena, pero lo dejamos explícito por claridad).
        _tripSegments = State(initialValue: trip.tripSegments.sorted { $0.dateFrom < $1.dateFrom })
        _selectedTransport = State(initialValue: trip.transport)
        _tripTitle = State(initialValue: trip.title ?? "")
        _tripNotes = State(initialValue: trip.notes ?? "")
        _tripPhotos = State(initialValue: trip.photos)
        _tripTagsText = State(initialValue: trip.tags.joined(separator: ", "))
        _localDateFrom = State(initialValue: trip.dateFrom)
        _localDateTo = State(initialValue: trip.dateTo)
        _localAirports = State(initialValue: trip.tripAirports)
        _localAirlines = State(initialValue: trip.tripAirlines)
        _localHasLayover = State(initialValue: trip.hasLayover)
        _localFlightInfo = State(initialValue: trip.flightDetails ?? FlightInfo())
        _legacyVisitedLayoverISOs = State(initialValue: Set(trip.visitedLayoverISOs ?? []))
    }

    private func prepareEditSaveConfirmation() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        guard !tripSegments.isEmpty else {
            // País de destino (siempre se cuenta como visitado).
            var visits: [VisitEntry] = []
            let mainFeat = features.first { $0.isoCode == trip.isoCode }
            visits.append(VisitEntry(
                isoCode: trip.isoCode,
                flagEmoji: mainFeat?.flagEmoji ?? "",
                name: mainFeat?.localizedName ?? trip.isoCode,
                count: 1))
            // Escalas marcadas como visitadas en el flujo legacy. Se filtran
            // contra las escalas reales para excluir ISOs huérfanas.
            let realISOs = Set(legacyOutboundLayovers.map(\.isoA3))
            for iso in legacyVisitedLayoverISOs.intersection(realISOs) where iso != trip.isoCode {
                let feat = features.first { $0.isoCode == iso }
                visits.append(VisitEntry(
                    isoCode: iso,
                    flagEmoji: feat?.flagEmoji ?? "",
                    name: feat?.localizedName ?? iso,
                    count: 1))
            }
            confirmVisits = visits
            var apCombined: [String: Int] = [:]
            for ap in localAirports { apCombined[ap.iata, default: 0] += ap.count }
            for ap in localReturnAirports { apCombined[ap.iata, default: 0] += ap.count }
            confirmAirports = apCombined.map { AirportConfirmEntry(iata: $0.key, count: $0.value) }.sorted { $0.iata < $1.iata }
            confirmAirlines = localAirlines.map { AirlineConfirmEntry(name: $0.name, count: $0.count) }
            // Path legacy sin segmentos: el trip "es" un único tramo con
            // `selectedTransport` y `localDateFrom`/`localDateTo`. Si es no-✈️
            // (y no vacío), aplicamos la misma regla: dateTo != nil → 2, sino 1.
            confirmTransports = []
            if let tr = selectedTransport, !tr.isEmpty, tr != "✈️" {
                let labelByEmoji = Dictionary(uniqueKeysWithValues:
                    PlannedDatePickerSheet.transports.map { ($0.emoji, $0.label) })
                let delta = localDateTo != nil ? 2 : 1
                confirmTransports = [TransportConfirmEntry(
                    emoji: tr, label: labelByEmoji[tr] ?? tr, count: delta)]
            }
            if confirmAirports.isEmpty && confirmAirlines.isEmpty && confirmTransports.isEmpty { performEditSave(); return }
            showSaveConfirmation = true
            return
        }
        var visitCounts: [String: Int] = [:]
        for seg in tripSegments {
            for iso in seg.isoCodes { visitCounts[iso, default: 0] += 1 }
        }
        visitCounts[trip.isoCode] = max(visitCounts[trip.isoCode, default: 0], 1)
        confirmVisits = visitCounts.map { (iso, count) in
            let feat = features.first { $0.isoCode == iso }
            return VisitEntry(isoCode: iso, flagEmoji: feat?.flagEmoji ?? "", name: feat?.localizedName ?? iso, count: count)
        }.sorted { a, b in
            if a.isoCode == trip.isoCode { return true }
            if b.isoCode == trip.isoCode { return false }
            return a.name < b.name
        }
        let apSegs = tripSegments.filter { $0.transport == "✈️" && $0.airports?.isEmpty == false }
        var apC: [String: Int] = [:]
        var alC: [String: Int] = [:]
        var alOrder: [String] = []
        for seg in apSegs {
            let vlISOs2 = Set(seg.visitedLayoverISOs ?? [])
            // Toques naturales (idéntico a `prepareConfirmation` de AddTrip).
            for ap in (seg.airports ?? [])       { apC[ap.iata, default: 0] += ap.count }
            for ap in (seg.returnAirports ?? []) { apC[ap.iata, default: 0] += ap.count }
            // Bonus +1 por cada IATA de escala cuyo país esté visitado (un
            // solo bonus por IATA aunque aparezca en ida y vuelta).
            let outIntermediate2 = (seg.airports ?? []).dropFirst().dropLast().map { $0.iata }
            let retIntermediate2 = (seg.returnAirports ?? []).dropFirst().dropLast().map { $0.iata }
            var bonusedIATAs: Set<String> = []
            for iata in outIntermediate2 + retIntermediate2 where bonusedIATAs.insert(iata).inserted {
                let a2 = RoutePickerSheet.allAirports.first { $0.iata == iata }?.country ?? ""
                guard let iso = features.first(where: { $0.isoA2 == a2 })?.isoCode,
                      vlISOs2.contains(iso) else { continue }
                apC[iata, default: 0] += 1
            }
            for al in (seg.airlines ?? []) {
                if alC[al.name] == nil { alOrder.append(al.name) }
                alC[al.name, default: 0] += al.count
            }
        }
        confirmAirports = apC.map { AirportConfirmEntry(iata: $0.key, count: $0.value) }.sorted { $0.iata < $1.iata }
        confirmAirlines = alOrder.map { AirlineConfirmEntry(name: $0, count: alC[$0] ?? 0) }
        // fallback: viajes guardados antes del sistema de segmentos
        if confirmAirports.isEmpty {
            confirmAirports = trip.tripAirports.map { AirportConfirmEntry(iata: $0.iata, count: $0.count) }
        }
        if confirmAirlines.isEmpty {
            confirmAirlines = trip.tripAirlines.map { AirlineConfirmEntry(name: $0.name, count: $0.count) }
        }
        // Conteos de transportes no-✈️ (tren, coche, bus, etc.). Aplicamos la
        // regla por tramo: dateTo == nil → +1; dateTo != nil → +2. N tramos del
        // mismo emoji se acumulan. Orden por primera aparición cronológica.
        var trC: [String: Int] = [:]
        var trOrder: [String] = []
        let nonFlightSegs = tripSegments
            .sorted { $0.dateFrom < $1.dateFrom }
            .filter { $0.transport != "✈️" && !$0.transport.isEmpty }
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
        showSaveConfirmation = true
    }

    private func performEditSave() {
        let trimmedTitle = tripTitle.trimmingCharacters(in: .whitespaces)
        trip.title = trimmedTitle.isEmpty ? nil : trimmedTitle
        let trimmedNotes = tripNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        trip.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        trip.photos = tripPhotos
        let parsedTags = tripTagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        trip.tags = Array(NSOrderedSet(array: parsedTags)) as? [String] ?? parsedTags
        if !trip.isSegmentChild {
            trip.dateFrom = calculatedDateFrom
            trip.dateTo = calculatedDateTo
            trip.transport = tripSegments.isEmpty ? selectedTransport : (tripSegments.first?.transport ?? selectedTransport ?? "🌍")
            let airplaneSeg = tripSegments.first(where: { $0.transport == "✈️" && ($0.airports?.isEmpty == false) })
            // Orden cronológico de aeropuertos. Para segment-based: iteramos
            // segmentos por dateFrom, y dentro de cada segmento ida → vuelta.
            // Para legacy: usamos `localAirports` (lo que tipeó el user en el
            // wizard, ya cronológico). El primer iata visto gana — esto evita
            // que el orden alfabético del confirm-dialog (ordenado para la UI)
            // o el orden hash del Dictionary contaminen `trip.tripAirports`,
            // que es lo que rendea `legacyAirportRoute` y otros consumidores.
            var apOrder: [String] = []
            var seenIatas: Set<String> = []
            if tripSegments.isEmpty {
                for ap in localAirports where seenIatas.insert(ap.iata).inserted { apOrder.append(ap.iata) }
                for ap in localReturnAirports where seenIatas.insert(ap.iata).inserted { apOrder.append(ap.iata) }
            } else {
                for seg in tripSegments.sorted(by: { $0.dateFrom < $1.dateFrom }) where seg.transport == "✈️" {
                    for ap in seg.airports ?? [] where seenIatas.insert(ap.iata).inserted { apOrder.append(ap.iata) }
                    for ap in seg.returnAirports ?? [] where seenIatas.insert(ap.iata).inserted { apOrder.append(ap.iata) }
                }
            }
            if !confirmAirports.isEmpty || !confirmAirlines.isEmpty {
                let countsByIata = Dictionary(confirmAirports.map { ($0.iata, $0.count) }, uniquingKeysWith: +)
                var ordered: [TripAirport] = apOrder.compactMap { iata in
                    guard let count = countsByIata[iata], count > 0 else { return nil }
                    return TripAirport(iata: iata, count: count)
                }
                // Defensivo: si el user añadió un iata en el dialog que no
                // estaba en segments/localAirports, lo añadimos al final.
                for entry in confirmAirports where !seenIatas.contains(entry.iata) && entry.count > 0 {
                    ordered.append(TripAirport(iata: entry.iata, count: entry.count))
                }
                trip.tripAirports = ordered
                trip.tripAirlines = confirmAirlines.map { TripAirline(name: $0.name, count: $0.count) }
            } else if tripSegments.isEmpty {
                trip.tripAirports = localAirports
                trip.tripAirlines = localAirlines
                trip.hasLayover = localHasLayover
            } else {
                trip.tripAirports = airplaneSeg?.airports ?? trip.tripAirports
                trip.tripAirlines = airplaneSeg?.airlines ?? trip.tripAirlines
            }
            if !tripSegments.isEmpty { trip.hasLayover = airplaneSeg?.hasLayover ?? trip.hasLayover }
            trip.tripSegments = tripSegments
            // Persistir escalas visitadas a nivel trip y limpiar el legacy
            // cuando el trip se convierte en segment-based.
            let legacyVisitedLayovers: [String]
            if tripSegments.isEmpty {
                trip.flightDetails = localFlightInfo.hasAnyData ? localFlightInfo : nil
                // Filtramos contra las escalas que realmente existen en la
                // ruta actual para no guardar ISOs huérfanas si el usuario
                // re-routea.
                let realISOs = Set(legacyOutboundLayovers.map(\.isoA3))
                legacyVisitedLayovers = Array(legacyVisitedLayoverISOs.intersection(realISOs))
                trip.visitedLayoverISOs = legacyVisitedLayovers.isEmpty ? nil : legacyVisitedLayovers
            } else {
                // Segment-based → escalas viven en seg.visitedLayoverISOs.
                trip.visitedLayoverISOs = nil
                legacyVisitedLayovers = []
            }
            // Delete old children — antes de re-crear arriba/abajo.
            if let groupID = trip.segmentGroupID {
                let desc = FetchDescriptor<Trip>(predicate: #Predicate { $0.segmentGroupID == groupID })
                for t in modelContext.fetchOrWarn(desc) where t.isSegmentChild { modelContext.delete(t) }
            }
            // Children para escalas visitadas en el path legacy non-segment.
            // Cada escala = 1 child trip de 1 día → aparece en lista del país,
            // marca `Country.status = .visited` (si el viaje es pasado) y se
            // refleja en el contador de días vía el stake de prio 50 que hace
            // `daysPerCountry` para `t.visitedLayoverISOs`.
            if tripSegments.isEmpty && !legacyVisitedLayovers.isEmpty {
                let groupID = trip.segmentGroupID ?? UUID().uuidString
                trip.segmentGroupID = groupID
                let today = Calendar.current.startOfDay(for: Date())
                let dayStart = Calendar.current.startOfDay(for: trip.dateFrom)
                let trimmedTitleStr = trip.title?.trimmingCharacters(in: .whitespaces) ?? ""
                for iso in legacyVisitedLayovers where iso != trip.isoCode {
                    let child = Trip(
                        isoCode: iso,
                        title: trimmedTitleStr.isEmpty ? nil : trimmedTitleStr,
                        dateFrom: trip.dateFrom,
                        dateTo: trip.dateFrom,   // 1 día (la escala dura el día del vuelo)
                        transport: "✈️",
                        tripAirports: [], tripAirlines: []
                    )
                    child.segmentGroupID = groupID
                    child.isSegmentChild = true
                    modelContext.insert(child)
                    if dayStart <= today {
                        let isoCopy = iso
                        let dd = FetchDescriptor<Country>(predicate: #Predicate { $0.isoCode == isoCopy })
                        if let country = modelContext.fetchFirstOrWarn(dd), country.status != .visited {
                            country.status = .visited
                            country.plannedDate = nil
                            country.plannedDateTo = nil
                            country.transport = nil
                        }
                    }
                }
            }
            if !tripSegments.isEmpty {
                let groupID = trip.segmentGroupID ?? UUID().uuidString
                trip.segmentGroupID = groupID
                let today = Calendar.current.startOfDay(for: Date())
                var countForIso: [String: Int] = [:]
                if !confirmVisits.isEmpty {
                    for entry in confirmVisits { countForIso[entry.isoCode] = entry.count }
                } else {
                    for seg in tripSegments { for iso in seg.isoCodes { countForIso[iso, default: 0] += 1 } }
                    countForIso[trip.isoCode] = max(countForIso[trip.isoCode, default: 0], 1)
                }
                // Extra visits for main country
                let segsForMain = tripSegments.filter { $0.isoCodes.contains(trip.isoCode) }
                let mainCount = countForIso[trip.isoCode] ?? 1
                for i in 0..<(mainCount - 1) {
                    let extraSeg = (i + 1) < segsForMain.count ? segsForMain[i + 1] : segsForMain.last
                    let extraTransport = extraSeg?.transport ?? trip.transport
                    var extraAps: [TripAirport] = []
                    var extraAls: [TripAirline] = []
                    if extraSeg?.transport == "✈️" {
                        var apC3: [String: Int] = [:]
                        for ap in extraSeg?.airports ?? [] { apC3[ap.iata, default: 0] += 1 }
                        for ap in extraSeg?.returnAirports ?? [] { apC3[ap.iata, default: 0] += 1 }
                        extraAps = apC3.map { TripAirport(iata: $0.key, count: $0.value) }
                        extraAls = extraSeg?.airlines ?? []
                    }
                    let extra = Trip(isoCode: trip.isoCode, title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                                    dateFrom: extraSeg?.dateFrom ?? calculatedDateFrom,
                                    dateTo: extraSeg?.dateTo ?? calculatedDateTo,
                                    transport: extraTransport, tripAirports: extraAps, tripAirlines: extraAls)
                    extra.hasLayover = extraSeg?.hasLayover ?? false
                    extra.segmentGroupID = groupID
                    extra.isSegmentChild = true
                    if let seg = extraSeg { extra.tripSegments = [seg] }
                    modelContext.insert(extra)
                }
                // Children for other countries
                for (iso, confirmedCount) in countForIso where iso != trip.isoCode && confirmedCount > 0 {
                    let segsWithIso = tripSegments.filter { $0.isoCodes.contains(iso) }
                    for i in 0..<confirmedCount {
                        let seg = i < segsWithIso.count ? segsWithIso[i] : segsWithIso.last
                        let d = seg?.dateFrom ?? calculatedDateFrom
                        let dTo = seg?.dateTo
                        let t = seg?.transport ?? "🌍"
                        var apC2: [String: Int] = [:]
                        if seg?.transport == "✈️" {
                            for ap in seg?.airports ?? [] { apC2[ap.iata, default: 0] += 1 }
                            for ap in seg?.returnAirports ?? [] { apC2[ap.iata, default: 0] += 1 }
                        }
                        let sAps = seg?.transport == "✈️" ? apC2.map { TripAirport(iata: $0.key, count: $0.value) } : []
                        let sAls = seg?.transport == "✈️" ? (seg?.airlines ?? []) : []
                        let child = Trip(isoCode: iso, title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                                        dateFrom: d, dateTo: dTo, transport: t,
                                        tripAirports: sAps, tripAirlines: sAls)
                        child.hasLayover = seg?.hasLayover ?? false
                        child.segmentGroupID = groupID
                        child.isSegmentChild = true
                        if let seg { child.tripSegments = [seg] }
                        modelContext.insert(child)
                        if Calendar.current.startOfDay(for: d) <= today {
                            let countryIso = iso
                            let dd = FetchDescriptor<Country>(predicate: #Predicate { $0.isoCode == countryIso })
                            if let country = modelContext.fetchFirstOrWarn(dd), country.status != .visited {
                                country.status = .visited
                                country.plannedDate = nil; country.plannedDateTo = nil; country.transport = nil
                            }
                        } else {
                            let countryIso = iso
                            let dd = FetchDescriptor<Country>(predicate: #Predicate { $0.isoCode == countryIso })
                            if let country = modelContext.fetchFirstOrWarn(dd) {
                                if country.status != .visited && country.status != .lived {
                                    country.status = .wantToVisit
                                    if country.plannedDate.map({ d < $0 }) ?? true {
                                        country.plannedDate = d
                                        country.plannedDateTo = dTo
                                        country.transport = t
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        // Propagate title to siblings
        if let groupID = trip.segmentGroupID {
            let desc = FetchDescriptor<Trip>(predicate: #Predicate { $0.segmentGroupID == groupID })
            if let siblings = try? modelContext.fetch(desc) {
                for sibling in siblings { sibling.title = trimmedTitle.isEmpty ? nil : trimmedTitle }
            }
        }
        modelContext.saveOrWarn()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private let accent = BrandColor.accent

    var body: some View {
        ZStack {
        NavigationStack {
            ScrollView {
            VStack(spacing: 0) {
                // Título
                VStack(alignment: .leading, spacing: 8) {
                    Text("TÍTULO DEL VIAJE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary).tracking(1.0)
                        .padding(.horizontal, 24)
                    TextField("Ej: Vacaciones de verano", text: $tripTitle)
                        .font(.palatino(.body))
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.card))
                        .padding(.horizontal, 24)
                }
                .padding(.top, 24).padding(.bottom, 16)

                // Notas largas — opcional. Misma estética que TÍTULO.
                VStack(alignment: .leading, spacing: 8) {
                    Text("NOTAS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary).tracking(1.0)
                        .padding(.horizontal, 24)
                    TextField("Anécdotas, recomendaciones…", text: $tripNotes, axis: .vertical)
                        .lineLimit(3...8)
                        .font(.palatino(.body))
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.card))
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 16)

                // Tags — string libre separado por comas. Como en AddTripSheet.
                VStack(alignment: .leading, spacing: 8) {
                    Text("TAGS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary).tracking(1.0)
                        .padding(.horizontal, 24)
                    TextField("Ej: verano, familia, luna de miel", text: $tripTagsText)
                        .font(.palatino(.body))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.card))
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 16)

                // Fotos del viaje — selector + thumbnails. Mismo patrón que
                // AddTripSheet pero con `tripPhotos` inicializado desde el
                // trip existente en init().
                VStack(alignment: .leading, spacing: 8) {
                    Text("FOTOS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary).tracking(1.0)
                        .padding(.horizontal, 24)
                    photosSection
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 20)

                // MARK: Transporte + Fechas (solo viajes simples)
                if tripSegments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TRANSPORTE")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary).tracking(1.0)
                            .padding(.horizontal, 24)
                        HStack(spacing: 8) {
                            ForEach(PlannedDatePickerSheet.transports, id: \.emoji) { t in
                                let isSelected = selectedTransport == t.emoji
                                Button { selectedTransport = isSelected ? nil : t.emoji } label: {
                                    VStack(spacing: 4) {
                                        Text(t.emoji).font(.system(size: 20))
                                        Text(t.label).font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(isSelected ? accent : .secondary)
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(isSelected ? accent.opacity(0.1) : Color(.systemGray6),
                                                in: RoundedRectangle(cornerRadius: Radius.cell))
                                    .overlay(RoundedRectangle(cornerRadius: Radius.cell)
                                        .stroke(isSelected ? accent.opacity(0.35) : Color.clear, lineWidth: 1.5))
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 20)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("FECHAS")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary).tracking(1.0)
                            .padding(.horizontal, 24)
                        VStack(spacing: 0) {
                            HStack {
                                Text("Desde").font(.palatino(.body))
                                Spacer()
                                DatePicker("", selection: $localDateFrom, displayedComponents: .date)
                                    .labelsHidden()
                                    .onChange(of: localDateFrom) { _, newVal in
                                        if let to = localDateTo, newVal > to { localDateTo = nil }
                                    }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            Rectangle().fill(Color(.systemGray5)).frame(height: 0.5).padding(.leading, 16)
                            HStack {
                                Text("Hasta (opcional)").font(.palatino(.body))
                                Spacer()
                                if localDateTo != nil {
                                    Button { localDateTo = nil } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.trailing, 4)
                                    .accessibilityLabel("Quitar fecha hasta")
                                    DatePicker("", selection: Binding(
                                        get: { localDateTo ?? localDateFrom },
                                        set: { localDateTo = $0 }
                                    ), in: localDateFrom..., displayedComponents: .date).labelsHidden()
                                } else {
                                    Button {
                                        localDateTo = Calendar.current.date(byAdding: .day, value: 1, to: localDateFrom)
                                    } label: {
                                        Text("Añadir").foregroundStyle(accent).font(.palatino(.body))
                                    }.buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                        }
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.card))
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 20)
                }

                // MARK: Ruta de vuelo
                if (selectedTransport == "✈️" || !localAirports.isEmpty) && tripSegments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("RUTA DE VUELO")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary).tracking(1.0)
                            .padding(.horizontal, 24)
                        Button { showRoutePicker = true } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(accent.opacity(0.1)).frame(width: 36, height: 36)
                                    Image(systemName: "airplane").font(.system(size: 15)).foregroundStyle(accent)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    if localAirports.isEmpty {
                                        Text("Añadir ruta de vuelo").font(.palatino(.body)).foregroundStyle(accent)
                                    } else {
                                        let routes = effectiveFlightRoutes
                                        Text(routes.outbound.joined(separator: " → "))
                                            .font(.palatino(.body)).foregroundStyle(.primary).lineLimit(1)
                                        if !routes.returnRt.isEmpty {
                                            Text(routes.returnRt.joined(separator: " → "))
                                                .font(.palatino(.caption)).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.card))
                            .padding(.horizontal, 24)
                        }.buttonStyle(.plain)
                    }
                    .padding(.bottom, 12)

                    // Para legacy round-trip directo guardado como [MAD(c=2), ARN(c=2)]
                    // sin `returnAirports` separado, sintetizamos la vuelta para que
                    // `FlightInfoSection` genere editores IDA + VUELTA en vez de uno solo.
                    let routes = effectiveFlightRoutes
                    FlightInfoSection(info: $localFlightInfo,
                                      outboundRoute: routes.outbound,
                                      returnRoute: routes.returnRt)
                        .padding(.bottom, 8)

                    // Toggles de "¿Visitaste alguna escala?" para trips legacy
                    // sin segmentos. Solo aparece cuando hay aeropuertos
                    // intermedios en alguna dirección. Misma UX que en
                    // AddSegmentSheet (IDA / VUELTA con set binario por país).
                    // UN solo toggle por país (binario). `legacyOutboundLayovers`
                    // viene ya deduplicada de `deriveLegacyFlightCountries()`.
                    if !legacyOutboundLayovers.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(isForFuture ? "¿HARÁS PARADA EN...?" : "¿VISITASTE ALGUNA ESCALA?")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary).tracking(0.8)
                            legacyLayoverSection(title: nil, choices: legacyOutboundLayovers)
                        }
                        .padding(16)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.card))
                        .padding(.horizontal, 24).padding(.bottom, 12)
                    }
                }

                // MARK: Tramos
                VStack(alignment: .leading, spacing: 10) {
                    Text("TRAMOS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary).tracking(1.0)
                        .padding(.horizontal, 24)

                    if !tripSegments.isEmpty {
                        VStack(spacing: 8) {
                            // Orden cronológico (ida → vuelta) independientemente del orden de inserción.
                            ForEach(tripSegments.sorted { $0.dateFrom < $1.dateFrom }) { seg in
                                let isFlight = seg.transport == "✈️"
                                let isExpanded = expandedSegmentIDs.contains(seg.id)
                                VStack(spacing: 10) {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle().fill(Color(.systemGray5)).frame(width: 40, height: 40)
                                            Text(seg.transport).font(.system(size: 18))
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(segmentCountryNames(seg))
                                                .font(.palatino(.body)).lineLimit(1)
                                            Text(Self.segFmt.string(from: seg.dateFrom))
                                                .font(.custom("Satoshi-Regular", size: 12)).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        // Sólo segmentos ✈️ tienen detalles de vuelo (asiento/clase) por tramo.
                                        if isFlight {
                                            Button {
                                                if isExpanded { expandedSegmentIDs.remove(seg.id) }
                                                else { expandedSegmentIDs.insert(seg.id) }
                                            } label: {
                                                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                                    .font(.system(size: 22)).foregroundStyle(accent.opacity(0.8))
                                            }.buttonStyle(.plain)
                                        }
                                        Button {
                                            // Editar: NO eliminar upfront — si el usuario cancela en
                                            // AddSegmentSheet el segmento se preserva. AddSegmentSheet
                                            // reusa el mismo `id` al guardar, y abajo lo reemplazamos por id.
                                            editingSegment = seg
                                            showAddSegment = true
                                        } label: {
                                            Image(systemName: "pencil.circle.fill")
                                                .font(.system(size: 22)).foregroundStyle(accent.opacity(0.8))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Editar tramo")
                                        Button { tripSegments.removeAll { $0.id == seg.id } } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 22)).foregroundStyle(Color(.systemGray3))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Eliminar tramo")
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 10)
                                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.card))
                                    .padding(.horizontal, 24)

                                    // Asiento / clase / reserva por leg (ida + vuelta separados).
                                    // Inline edit por segmento ✈️ — evita tener que abrir AddSegmentSheet
                                    // sólo para cambiar asientos. El binding escribe en seg.flightInfo.
                                    if isFlight && isExpanded {
                                        FlightInfoSection(
                                            info: segmentFlightInfoBinding(for: seg.id),
                                            outboundRoute: (seg.airports ?? []).map { $0.iata },
                                            returnRoute: (seg.returnAirports ?? []).map { $0.iata }
                                        )
                                    }
                                }
                            }
                        }
                    }

                    Button { showAddSegment = true } label: {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle().fill(accent.opacity(0.1)).frame(width: 32, height: 32)
                                Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(accent)
                            }
                            Text("Añadir transporte").font(.palatino(.body)).foregroundStyle(accent)
                        }
                        .padding(.horizontal, 24).padding(.vertical, 4)
                    }.buttonStyle(.plain)
                }
                .padding(.bottom, 16)

                // Rango de fechas calculado desde segmentos
                if !tripSegments.isEmpty {
                    HStack(spacing: 12) {
                        VStack(spacing: 4) {
                            Text("DESDE").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).tracking(0.8)
                            Text(Self.fmt.string(from: calculatedDateFrom))
                                .font(.custom("Satoshi-Bold", size: 15))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
                        if let to = calculatedDateTo {
                            VStack(spacing: 4) {
                                Text("HASTA").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).tracking(0.8)
                                Text(Self.fmt.string(from: to))
                                    .font(.custom("Satoshi-Bold", size: 15))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
                        }
                    }
                    .padding(.horizontal, 24).padding(.bottom, 16)
                }

                Button { prepareEditSaveConfirmation() } label: {
                    Text("Guardar cambios")
                        .font(.custom("Satoshi-Bold", size: 16))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(accent, in: RoundedRectangle(cornerRadius: Radius.card))
                        .foregroundStyle(.white)
                        .shadow(color: accent.opacity(0.3), radius: 12, y: 4)
                }
                .padding(.horizontal, 24).padding(.bottom, 36)
            }
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Editar viaje")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(showSaveConfirmation)
        .sheet(isPresented: $showAddSegment, onDismiss: { editingSegment = nil }) {
            // `baseIsoCode: trip.isoCode` solo aplica al CREAR un tramo nuevo
            // desde EditTripSheet — al editar uno existente, AddSegmentSheet
            // ya inicializa selectedIsoCodes desde seg.isoCodes y ignora
            // baseIsoCode (lógica gateada en init por `initialSegment == nil`).
            AddSegmentSheet(features: features, isForFuture: isForFuture, initialSegment: editingSegment, existingSegments: tripSegments, baseIsoCode: trip.isoCode) { seg in
                // Reemplaza por id si ya existe (edición), o añade (creación).
                if let idx = tripSegments.firstIndex(where: { $0.id == seg.id }) {
                    tripSegments[idx] = seg
                } else {
                    tripSegments.append(seg)
                }
                // Reordenar por fecha tras cualquier cambio — si el usuario
                // cambia la fecha de un segment desde edición, su posición
                // visual debe reflejar la nueva fecha, no el orden anterior.
                tripSegments.sort { $0.dateFrom < $1.dateFrom }
            }
        }
        .sheet(isPresented: $showRoutePicker) {
            RouteWizardSheet(airports: $localAirports, returnAirports: $localReturnAirports,
                             airlines: $localAirlines, hasLayover: $localHasLayover) {
                // Tras añadir/editar la ruta o cualquier escala, recomputa los
                // toggles IDA/VUELTA (`legacyOutboundLayovers` / `legacyReturnLayovers`)
                // para que aparezca el bloque "¿Visitaste alguna escala?".
                deriveLegacyFlightCountries()
            }
        }
        // Recompute legacy layover toggles cuando aparece la sheet — cubre el
        // caso de un trip ya guardado con escalas + ISOs visitadas que el user
        // re-abre solo para revisar/cambiar.
        .onAppear { deriveLegacyFlightCountries() }
        .appColorScheme()

        if showSaveConfirmation {
            editVisitConfirmCard(onSave: { showSaveConfirmation = false; performEditSave() },
                                 onCancel: { showSaveConfirmation = false })
        }
        } // ZStack
    }

    /// Sección de fotos: PhotosPicker + thumbnails horizontales con botón
    /// ✕ para eliminar. Mismo patrón que AddTripSheet — la única diferencia
    /// es que aquí las fotos vienen ya cargadas del trip existente.
    @ViewBuilder
    private var photosSection: some View {
        let remaining = Trip.maxPhotosPerTrip - tripPhotos.count
        VStack(alignment: .leading, spacing: 8) {
            if !tripPhotos.isEmpty {
                HStack {
                    Spacer()
                    Text("\(tripPhotos.count)/\(Trip.maxPhotosPerTrip)")
                        .font(.palatino(.caption)).foregroundStyle(.tertiary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(tripPhotos.enumerated()), id: \.offset) { idx, data in
                            if let ui = UIImage(data: data) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: ui).resizable().scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    Button {
                                        tripPhotos.remove(at: idx)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .accessibilityLabel("Eliminar foto")
                                    .padding(4)
                                }
                            }
                        }
                    }
                }
            }
            if remaining > 0 {
                PhotosPicker(selection: $photosPickerItems,
                             maxSelectionCount: remaining,
                             matching: .images) {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus")
                        Text(tripPhotos.isEmpty ? "Añadir fotos" : "Añadir más (\(remaining) restantes)")
                            .font(.palatino(.body))
                    }
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.card))
                }
                .onChange(of: photosPickerItems) { _, items in
                    Task {
                        var newPhotos: [Data] = []
                        for item in items {
                            if let data = await TripPhotoProcessor.processPickerItem(item) {
                                newPhotos.append(data)
                            }
                        }
                        await MainActor.run {
                            let combined = (tripPhotos + newPhotos).prefix(Trip.maxPhotosPerTrip)
                            tripPhotos = Array(combined)
                            photosPickerItems = []
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func editVisitConfirmCard(onSave: @escaping () -> Void, onCancel: @escaping () -> Void) -> some View {
        confirmCardContent(
            confirmVisits: $confirmVisits, confirmAirports: $confirmAirports, confirmAirlines: $confirmAirlines,
            confirmTransports: $confirmTransports,
            accent: accent, onSave: onSave, onCancel: onCancel
        )
    }
}
