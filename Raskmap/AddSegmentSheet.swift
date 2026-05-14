//
//  AddSegmentSheet.swift
//  Raskmap
//
//  Wizard de 3 pasos para añadir un tramo de transporte a un viaje.
//

import SwiftUI

/// Una opción de "escala" en el wizard de añadir/editar tramo.
///
/// `id` es único por aparición (combina dirección + ISO) para permitir que el
/// MISMO país pueda aparecer una vez en la sección IDA y otra en VUELTA cuando
/// la ruta lo lleva por ese país en ambos sentidos. El flag de "visitado" se
/// guarda en un único `Set<String>` de ISOs (binario por país), de modo que
/// toggle de una sección actualice ambas representaciones — visitar es por
/// país, no por dirección.
struct LayoverChoice: Identifiable {
    let id: String  // "out_<ISO3>" o "ret_<ISO3>"
    let isoA3: String
    let flag: String?
    let name: String
}

struct AddSegmentSheet: View {
    let features: [CountryFeature]
    let isForFuture: Bool
    let onAdd: (TripSegment) -> Void

    // Pre-sorted once at init; normalized names for fast diacritic-insensitive search
    private let sortedFeatures: [CountryFeature]
    private let normalizedNames: [String: String]  // isoCode → folded name

    @Environment(\.dismiss) private var dismiss
    @State private var step: Int = 1
    @State private var selectedTransport: String? = nil
    @State private var selectedIsoCodes: Set<String> = []
    @State private var searchQuery: String = ""
    @State private var dateFrom: Date
    @State private var dateTo: Date? = nil
    @State private var pickingFrom: Bool = true

    // For ✈️ segments
    @State private var segmentAirports: [TripAirport] = []        // outbound route (ordered)
    @State private var segmentReturnAirports: [TripAirport] = []  // return route (ordered, empty = one-way)
    @State private var segmentAirlines: [TripAirline] = []
    @State private var segmentHasLayover: Bool = false
    @State private var showRoutePicker: Bool = false

    // Layover / destination prompts (✈️ only)
    // Dos listas separadas, una por dirección, sin deduplicar entre ellas:
    // si DXB es escala de ida Y de vuelta, aparece como toggle en ambas.
    @State private var outboundLayoverChoices: [LayoverChoice] = []
    @State private var returnLayoverChoices: [LayoverChoice] = []
    /// Set único (binario por país) de ISOs marcados como visitados. Si DXB
    /// está en ida y vuelta, ambos toggles reflejan el mismo valor del Set.
    @State private var visitedLayoverISOs: Set<String> = []
    @State private var destinationIso: String? = nil  // auto-marked unless return flight
    @State private var segmentFlightInfo = FlightInfo()

    // When editing an existing segment
    @State private var didSetupInitial = false
    private let initialSegment: TripSegment?

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: today)
            ?? today.addingTimeInterval(86_400)
    }

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.locale = Locale(identifier: "es_ES"); return f
    }()

    init(features: [CountryFeature], isForFuture: Bool, initialSegment: TripSegment? = nil,
         existingSegments: [TripSegment] = [],
         baseIsoCode: String? = nil,
         onAdd: @escaping (TripSegment) -> Void) {
        self.features = features
        self.isForFuture = isForFuture
        self.initialSegment = initialSegment
        self.onAdd = onAdd
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let sorted = features.sorted { $0.localizedName.compare($1.localizedName, options: opts) == .orderedAscending }
        self.sortedFeatures = sorted
        var names = [String: String](minimumCapacity: sorted.count)
        for f in sorted {
            names[f.isoCode] = f.localizedName.folding(options: opts, locale: .current)
        }
        self.normalizedNames = names
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)
                     ?? today.addingTimeInterval(86_400)
        if let seg = initialSegment {
            _selectedTransport = State(initialValue: seg.transport)
            _dateFrom = State(initialValue: seg.dateFrom)
            _dateTo = State(initialValue: seg.dateTo)
            _step = State(initialValue: 3)
            if seg.transport == "✈️" {
                _segmentAirports = State(initialValue: seg.airports ?? [])
                _segmentReturnAirports = State(initialValue: seg.returnAirports ?? [])
                _segmentAirlines = State(initialValue: seg.airlines ?? [])
                _segmentHasLayover = State(initialValue: seg.hasLayover ?? false)
                _segmentFlightInfo = State(initialValue: seg.flightInfo ?? FlightInfo())
            } else {
                _selectedIsoCodes = State(initialValue: Set(seg.isoCodes))
            }
        } else if !existingSegments.isEmpty {
            // Smart default: el nuevo tramo arranca justo después del último
            // tramo existente (by chronology). Si el último seg tiene `dateTo`,
            // el nuevo arranca ese mismo día (transit shared); si no, día siguiente.
            // Si el destino del último seg es distinto a la base del trip, lo
            // usamos como "país de origen" inferido para el nuevo tramo.
            let sorted = existingSegments.sorted(by: { $0.dateFrom < $1.dateFrom })
            let last = sorted.last!
            let lastEnd = cal.startOfDay(for: last.dateTo ?? last.dateFrom)
            let nextDay = cal.date(byAdding: .day, value: 1, to: lastEnd) ?? lastEnd
            // Si lastEnd > tFrom (no es realista), defaulteamos a lastEnd para
            // permitir transit shared. Si no, day-after-last.
            let suggested = (last.dateTo != nil) ? lastEnd : nextDay
            _dateFrom = State(initialValue: suggested)
            _dateTo = State(initialValue: nil)
        } else {
            // Primer tramo del viaje: arranca hoy/mañana sin vuelta.
            let from = isForFuture ? tomorrow : today
            _dateFrom = State(initialValue: from)
            _dateTo = State(initialValue: nil)
        }
        // Preseleccionar el país base del viaje (el que el usuario tappeó en
        // el mapa para iniciar la creación) en step 2. Solo aplica si no
        // estamos editando un segmento existente — al editar, `seg.isoCodes` ya
        // trae las selecciones reales y `_selectedIsoCodes` se setea arriba.
        // Esta asignación se hace DESPUÉS de inicializar todos los stored props
        // sin default (p.ej. `_dateFrom`) para no violar el orden de init.
        if initialSegment == nil, let base = baseIsoCode, !base.isEmpty {
            _selectedIsoCodes = State(initialValue: [base])
        }
    }

    private var filteredFeatures: [CountryFeature] {
        guard !searchQuery.isEmpty else { return sortedFeatures }
        let q = searchQuery.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return sortedFeatures.filter {
            (normalizedNames[$0.isoCode] ?? "").contains(q) ||
            $0.isoCode.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    // Final isoCodes to use when creating the segment.
    // Incluye destino + cualquier escala marcada (ida o vuelta) — el set
    // visitedLayoverISOs es ya binario por país, así que da igual si está
    // marcada por la ida, por la vuelta, o por ambas.
    private var finalIsoCodes: Set<String> {
        if selectedTransport == "✈️" {
            var result = Set<String>()
            if let dest = destinationIso { result.insert(dest) }
            result.formUnion(visitedLayoverISOs)
            return result
        }
        return selectedIsoCodes
    }

    /// Edición = abrimos directamente en step 3 con datos rellenos. En ese caso el
    /// botón izquierdo siempre es "Cancelar" (no hay step anterior real al que volver).
    private var isEditing: Bool { initialSegment != nil }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 1: transportStep()
                case 2: countriesStep()
                default: dateStep()
                }
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isEditing {
                        // En modo edición no hay flujo creación al que volver.
                        Button("Cancelar") { dismiss() }.font(.palatino(.body))
                    } else if step > 1 {
                        Button("Atrás") { step -= 1 }.font(.palatino(.body))
                    } else {
                        Button("Cancelar") { dismiss() }.font(.palatino(.body))
                    }
                }
                if step == 2 {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Siguiente") { step += 1 }
                            .font(.palatino(.body, weight: .bold))
                            .disabled(selectedIsoCodes.isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            guard !didSetupInitial, initialSegment?.transport == "✈️", !segmentAirports.isEmpty else {
                didSetupInitial = true; return
            }
            didSetupInitial = true
            deriveFlightCountries()
        }
        .sheet(isPresented: $showRoutePicker) {
            RouteWizardSheet(airports: $segmentAirports, returnAirports: $segmentReturnAirports,
                             airlines: $segmentAirlines, hasLayover: $segmentHasLayover) {
                deriveFlightCountries()
                step = 3
            }
        }
        .appColorScheme()
    }

    // Derives destination + layover countries after RouteWizardSheet completes.
    // segmentAirports = ordered outbound route (e.g. MAD→AMS→HKG)
    // segmentReturnAirports = ordered return route (e.g. HKG→CDG→MAD), empty if one-way
    // AirportData.country is ISO A2; CountryFeature.isoCode is ISO A3 — use isoA2 to match
    private func deriveFlightCountries() {
        let allAps = RoutePickerSheet.allAirports

        func featureByA2(_ a2: String?) -> CountryFeature? {
            guard let a2 else { return nil }
            return features.first { $0.isoA2 == a2 }
        }

        let departureA2 = allAps.first(where: { $0.iata == segmentAirports.first?.iata })?.country
        // Destination is the LAST airport of the OUTBOUND leg (e.g. HKG, not CDG)
        let destinationA2 = allAps.first(where: { $0.iata == segmentAirports.last?.iata })?.country

        let departureFeature = featureByA2(departureA2)
        let destinationFeature = featureByA2(destinationA2)
        let departureISO = departureFeature?.isoCode
        let destinationISO = destinationFeature?.isoCode

        // Auto-include destination unless it's a return to the same country as departure
        if let dISO = destinationISO, dISO != departureISO {
            destinationIso = dISO   // A3 code
        } else {
            destinationIso = nil
        }

        // Escalas: UN SOLO toggle por país (binario). Si el mismo país aparece
        // como escala en ida y vuelta, se cuenta una sola vez — visitar es por
        // país, no por dirección. Esto evita la confusión de "dos toggles para
        // el mismo país" que reportaba el usuario.
        outboundLayoverChoices = []
        returnLayoverChoices = []

        // País de origen y destino se excluyen — no son "escalas" por
        // definición, ya cuentan como parte del propio tramo. Usamos los
        // valores LOCALES (no `destinationIso` @State) para evitar reads
        // stale dentro del mismo render pass.
        let excludedISOs: Set<String> = Set([departureISO, destinationISO].compactMap { $0 })

        // Recolecta intermedios de IDA + VUELTA en un solo set deduplicado,
        // preservando orden de primera aparición (ida → vuelta).
        var seen = excludedISOs
        var combined: [LayoverChoice] = []

        func addIntermediates(_ aps: [TripAirport]) {
            guard aps.count > 2 else { return }
            for ap in aps.dropFirst().dropLast() {
                guard let a2 = allAps.first(where: { $0.iata == ap.iata })?.country,
                      let f = featureByA2(a2),
                      seen.insert(f.isoCode).inserted else { continue }
                combined.append(
                    LayoverChoice(id: "lay_\(f.isoCode)", isoA3: f.isoCode,
                                  flag: f.flagEmoji, name: f.localizedName)
                )
            }
        }
        addIntermediates(segmentAirports)
        addIntermediates(segmentReturnAirports)

        // El UI consume `outboundLayoverChoices` como lista única (renombrar
        // sería más invasivo, así que conservamos la `@State` y dejamos
        // `returnLayoverChoices` siempre vacío para no romper call-sites).
        outboundLayoverChoices = combined

        // Restore visited state when editing — el set es binario por país.
        if let visitedISOs = initialSegment?.visitedLayoverISOs {
            visitedLayoverISOs = Set(visitedISOs)
        } else {
            visitedLayoverISOs = []
        }
    }

    private let accent = BrandColor.accent

    private var stepTitle: String {
        switch step {
        case 1: return "Nuevo tramo"
        case 2: return "Países"
        default: return "Fechas"
        }
    }

    // MARK: - Step 1: Transport
    @ViewBuilder
    private func transportStep() -> some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Transporte")
                        .font(.custom("Satoshi-Bold", size: 28))
                    Text(isForFuture ? "¿Cómo vas a viajar?" : "¿Cómo viajaste?")
                        .font(.palatino(.subheadline))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 28)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(PlannedDatePickerSheet.transports, id: \.emoji) { t in
                        let isSelected = selectedTransport == t.emoji
                        Button {
                            selectedTransport = t.emoji
                            if t.emoji == "✈️" { showRoutePicker = true } else { step = 2 }
                        } label: {
                            VStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(isSelected ? accent : Color(.systemGray5))
                                        .frame(width: 56, height: 56)
                                    Text(t.emoji).font(.system(size: 26))
                                }
                                Text(t.label)
                                    .font(.custom("Satoshi-Medium", size: 13))
                                    .foregroundStyle(isSelected ? accent : .primary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                            .background(isSelected ? accent.opacity(0.08) : Color(.systemGray6),
                                        in: RoundedRectangle(cornerRadius: Radius.section))
                            .overlay(RoundedRectangle(cornerRadius: Radius.section)
                                .stroke(isSelected ? accent.opacity(0.35) : Color.clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                Spacer(minLength: 32)
            }
        }
    }

    // MARK: - Step 2: Countries
    @ViewBuilder
    private func countriesStep() -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(selectedTransport ?? "🌍").font(.system(size: 22))
                Text("Países del tramo")
                    .font(.custom("Satoshi-Bold", size: 22))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 14)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14, weight: .medium))
                TextField("Buscar país...", text: $searchQuery)
                    .font(.palatino(.body))
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color(.systemGray3))
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
            .padding(.horizontal, 24)
            .padding(.bottom, 10)

            if !selectedIsoCodes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(selectedIsoCodes.sorted()), id: \.self) { iso in
                            let f = features.first { $0.isoCode == iso }
                            HStack(spacing: 4) {
                                Text(f?.flagEmoji ?? "🌐").font(.caption)
                                Text(f?.localizedName ?? iso).font(.custom("Satoshi-Medium", size: 12))
                                Button { selectedIsoCodes.remove(iso) } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(accent.opacity(0.1), in: Capsule())
                            .overlay(Capsule().stroke(accent.opacity(0.2), lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 8)
            }

            List(filteredFeatures, id: \.isoCode) { feature in
                Button {
                    if selectedIsoCodes.contains(feature.isoCode) {
                        selectedIsoCodes.remove(feature.isoCode)
                    } else {
                        selectedIsoCodes.insert(feature.isoCode)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(feature.flagEmoji ?? "🌐").font(.system(size: 22)).frame(width: 32)
                        Text(feature.localizedName).font(.palatino(.body)).foregroundStyle(.primary)
                        Spacer()
                        if selectedIsoCodes.contains(feature.isoCode) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(accent).font(.system(size: 20))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Step 3: Dates
    @ViewBuilder
    private func dateStep() -> some View {
        let transport = selectedTransport ?? "🌍"
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(transport).font(.system(size: 22))
                    Text("Fecha del tramo")
                        .font(.custom("Satoshi-Bold", size: 22))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20)

                if transport == "✈️" && !segmentAirports.isEmpty {
                    // Card de ruta tappable: re-abre `RouteWizardSheet` para que el
                    // usuario pueda cambiar la ruta o añadir/eliminar escalas en un
                    // segmento ya creado. Al cerrar el wizard `deriveFlightCountries()`
                    // recalcula los toggles IDA/VUELTA debajo.
                    Button { showRoutePicker = true } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(segmentAirports.map { $0.iata }.joined(separator: " → "))
                                        .font(.custom("Satoshi-Bold", size: 15)).foregroundStyle(accent)
                                    if !segmentReturnAirports.isEmpty {
                                        Text(segmentReturnAirports.map { $0.iata }.joined(separator: " → "))
                                            .font(.custom("Satoshi-Regular", size: 13))
                                            .foregroundStyle(accent.opacity(0.65))
                                    }
                                    if !segmentAirlines.isEmpty {
                                        Text(segmentAirlines.map { $0.name }.joined(separator: ", "))
                                            .font(.palatino(.caption)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                                VStack(spacing: 4) {
                                    Text("✈️").font(.system(size: 28))
                                    Text("Editar")
                                        .font(.custom("Satoshi-Medium", size: 10))
                                        .foregroundStyle(accent)
                                }
                            }
                        }
                        .padding(16)
                        .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.card))
                        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(accent.opacity(0.15), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24).padding(.bottom, 12)

                    if let destIso = destinationIso,
                       let destFeature = features.first(where: { $0.isoCode == destIso }) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green).font(.system(size: 14))
                            Text(destFeature.flagEmoji ?? "🌐")
                            Text("\(destFeature.localizedName) se añade como visitado")
                                .font(.palatino(.caption)).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 24).padding(.bottom, 10)
                    }

                    // UNA sola sección de toggles — un país escala (en cualquier
                    // dirección) se marca una sola vez como visitado. La lista
                    // `outboundLayoverChoices` ya viene deduplicada en
                    // `deriveFlightCountries()`.
                    if !outboundLayoverChoices.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(isForFuture ? "¿HARÁS PARADA EN...?" : "¿VISITASTE ALGUNA ESCALA?")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary).tracking(0.8)
                            layoverSection(title: nil, choices: outboundLayoverChoices)
                        }
                        .padding(16)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.card))
                        .padding(.horizontal, 24).padding(.bottom, 12)
                    }
                }

                if transport == "✈️" {
                    FlightInfoSection(info: $segmentFlightInfo,
                                      outboundRoute: segmentAirports.map { $0.iata },
                                      returnRoute: segmentReturnAirports.map { $0.iata })
                }

                let isOneWayFlight = transport == "✈️" && !segmentAirports.isEmpty && segmentReturnAirports.isEmpty

                HStack(spacing: 0) {
                    dateTab(isFrom: true,  label: "DESDE", value: Self.fmt.string(from: dateFrom))
                    if !isOneWayFlight {
                        dateTab(isFrom: false, label: "HASTA",
                                value: dateTo.map { Self.fmt.string(from: $0) } ?? "Sin vuelta")
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 6)

                // Link "Sin vuelta" — solo si hay dateTo y NO es one-way flight
                // (los vuelos one-way ya tienen su toggle automático arriba).
                // Permite al usuario quitar explícitamente la fecha de vuelta
                // sin tener que tappear la misma fecha que DESDE (ese gesto
                // ahora se interpreta como "ida y vuelta mismo día").
                if !isOneWayFlight && dateTo != nil {
                    HStack {
                        Spacer()
                        Button {
                            dateTo = nil
                            pickingFrom = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                Text("Quitar fecha de vuelta")
                                    .font(.palatino(.caption, weight: .bold))
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.bottom, 10)
                }

                // Quick chips de fecha — atajan al usuario en casos comunes.
                quickDateChips(isOneWayFlight: isOneWayFlight)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)

                RangeDatePicker(
                    dateFrom: $dateFrom, dateTo: $dateTo, pickingFrom: $pickingFrom,
                    minDate: isForFuture ? tomorrow : nil,
                    maxDate: isForFuture ? nil : today
                )
                .padding(.horizontal, 8)
                .frame(height: 340)
                .padding(.bottom, 16)
                .onChange(of: isOneWayFlight) { _, newValue in
                    if newValue {
                        dateTo = nil
                        pickingFrom = true
                    }
                }
                .onAppear {
                    if isOneWayFlight {
                        dateTo = nil
                        pickingFrom = true
                    }
                }

                Button {
                    let isos = finalIsoCodes
                    // Sólo guardamos como visitadas las escalas que realmente
                    // existen en la ruta — evita ISOs huérfanas si el usuario
                    // cambia la ruta tras marcar.
                    let realLayoverISOs: Set<String> = Set(outboundLayoverChoices.map(\.isoA3))
                    let visitedISOs = Array(visitedLayoverISOs.intersection(realLayoverISOs))
                    // Edición: preserva el id original del segmento para reemplazo por id en el caller.
                    var segment = TripSegment(
                        id: initialSegment?.id ?? UUID(),
                        transport: selectedTransport ?? "🌍",
                        isoCodes: Array(isos),
                        dateFrom: dateFrom,
                        dateTo: dateTo,
                        airports: segmentAirports.isEmpty ? nil : segmentAirports,
                        returnAirports: segmentReturnAirports.isEmpty ? nil : segmentReturnAirports,
                        airlines: segmentAirlines.isEmpty ? nil : segmentAirlines,
                        hasLayover: (segmentHasLayover || segmentAirports.count > 2 || segmentReturnAirports.count > 2) ? true : nil,
                        visitedLayoverISOs: visitedISOs.isEmpty ? nil : visitedISOs
                    )
                    if segmentFlightInfo.hasAnyData { segment.flightInfo = segmentFlightInfo }
                    onAdd(segment)
                    dismiss()
                } label: {
                    Text(isEditing ? "Guardar cambios" : "Añadir tramo")
                        .font(.custom("Satoshi-Bold", size: 16))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(accent, in: RoundedRectangle(cornerRadius: Radius.card))
                        .foregroundStyle(.white)
                        .shadow(color: accent.opacity(0.3), radius: 12, y: 4)
                }
                .padding(.horizontal, 24).padding(.bottom, 36)
            }
        }
    }

    /// Sección de toggles de escalas (IDA o VUELTA). Cada fila refleja el
    /// estado de `visitedLayoverISOs` (Set binario por país); pulsar el toggle
    /// añade/quita el ISO del set, sincronizando ambas secciones automáticamente
    /// si el mismo país aparece en ida y vuelta.
    @ViewBuilder
    private func layoverSection(title: String?, choices: [LayoverChoice]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.85))
                    .tracking(0.8)
            }
            ForEach(choices) { choice in
                let checked = visitedLayoverISOs.contains(choice.isoA3)
                Button {
                    if checked { visitedLayoverISOs.remove(choice.isoA3) }
                    else       { visitedLayoverISOs.insert(choice.isoA3) }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(checked ? accent : Color(.systemGray5))
                                .frame(width: 24, height: 24)
                            if checked {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                            }
                        }
                        FlagLabel(emoji: choice.flag ?? "🌐", size: 22)
                        Text(choice.name).font(.palatino(.body)).foregroundStyle(.primary)
                        Spacer()
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func dateTab(isFrom: Bool, label: String, value: String) -> some View {
        let active = pickingFrom == isFrom
        let color: Color = active ? accent : (isFrom ? .primary : (dateTo == nil ? .secondary : .primary))
        Button { pickingFrom = isFrom } label: {
            VStack(spacing: 4) {
                Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).tracking(0.8)
                Text(value).font(.custom("Satoshi-Bold", size: 15)).foregroundStyle(color)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(active ? accent.opacity(0.08) : Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
            .overlay(RoundedRectangle(cornerRadius: Radius.cell).stroke(active ? accent.opacity(0.3) : Color.clear, lineWidth: 1.5))
        }.buttonStyle(.plain)
    }

    /// Chips rápidos para fechas comunes — saltan el scroll del calendario.
    /// Para `isForFuture`: Mañana / +1 sem / +2 sem.
    /// Para pasado: Hoy / Ayer / -1 sem.
    @ViewBuilder
    private func quickDateChips(isOneWayFlight: Bool) -> some View {
        let cal = Calendar.current
        let now = cal.startOfDay(for: Date())
        let chips: [(label: String, value: Date)] = {
            if isForFuture {
                let plus1d = cal.date(byAdding: .day, value: 1, to: now) ?? now
                let plus1w = cal.date(byAdding: .day, value: 7, to: now) ?? now
                let plus2w = cal.date(byAdding: .day, value: 14, to: now) ?? now
                return [("Mañana", plus1d), ("Próx. semana", plus1w), ("En 2 sem.", plus2w)]
            } else {
                let minus1d = cal.date(byAdding: .day, value: -1, to: now) ?? now
                let minus1w = cal.date(byAdding: .day, value: -7, to: now) ?? now
                return [("Hoy", now), ("Ayer", minus1d), ("Hace 1 sem.", minus1w)]
            }
        }()
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                    Button {
                        if pickingFrom {
                            dateFrom = chip.value
                            if let to = dateTo, chip.value > to { dateTo = nil }
                        } else if !isOneWayFlight {
                            dateTo = chip.value < dateFrom ? nil : chip.value
                        }
                    } label: {
                        Text(chip.label)
                            .font(.custom("Satoshi-Bold", size: 12))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Color(.systemGray5), in: Capsule())
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
