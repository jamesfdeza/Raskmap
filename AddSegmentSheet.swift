//
//  AddSegmentSheet.swift
//  Raskmap
//
//  Wizard de 3 pasos para añadir un tramo de transporte a un viaje.
//

import SwiftUI

struct LayoverChoice: Identifiable {
    let id: String  // ISO code
    let flag: String?
    let name: String
    var checked: Bool
}

struct AddSegmentSheet: View {
    let features: [CountryFeature]
    let isForFuture: Bool
    let onAdd: (TripSegment) -> Void

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
    @State private var layoverChoices: [LayoverChoice] = []
    @State private var destinationIso: String? = nil  // auto-marked unless return flight

    // When editing an existing segment
    @State private var didSetupInitial = false
    private let initialSegment: TripSegment?

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var tomorrow: Date { Calendar.current.date(byAdding: .day, value: 1, to: today)! }

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.locale = Locale(identifier: "es_ES"); return f
    }()

    init(features: [CountryFeature], isForFuture: Bool, initialSegment: TripSegment? = nil, onAdd: @escaping (TripSegment) -> Void) {
        self.features = features
        self.isForFuture = isForFuture
        self.initialSegment = initialSegment
        self.onAdd = onAdd
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
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
            } else {
                _selectedIsoCodes = State(initialValue: Set(seg.isoCodes))
            }
        } else {
            _dateFrom = State(initialValue: isForFuture ? tomorrow : today)
        }
    }

    private var filteredFeatures: [CountryFeature] {
        let sorted = features.sorted { $0.localizedName < $1.localizedName }
        guard !searchQuery.isEmpty else { return sorted }
        return sorted.filter {
            $0.localizedName.localizedCaseInsensitiveContains(searchQuery) ||
            $0.isoCode.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    // Final isoCodes to use when creating the segment
    private var finalIsoCodes: Set<String> {
        if selectedTransport == "✈️" {
            var result = Set<String>()
            if let dest = destinationIso { result.insert(dest) }
            for choice in layoverChoices where choice.checked { result.insert(choice.id) }
            return result
        }
        return selectedIsoCodes
    }

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
                    if step > 1 {
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

        // Auto-include destination unless it's a return to the same country as departure
        if let destF = destinationFeature, destF.isoCode != departureFeature?.isoCode {
            destinationIso = destF.isoCode  // A3 code
        } else {
            destinationIso = nil
        }

        // Layover countries: intermediate airports from BOTH outbound and return legs
        layoverChoices = []
        var seen: Set<String> = Set([departureFeature?.isoCode, destinationIso].compactMap { $0 })

        // Outbound intermediates (e.g. AMS)
        if segmentAirports.count > 2 {
            for ap in segmentAirports.dropFirst().dropLast() {
                guard let a2 = allAps.first(where: { $0.iata == ap.iata })?.country,
                      let f = featureByA2(a2),
                      seen.insert(f.isoCode).inserted else { continue }
                layoverChoices.append(LayoverChoice(id: f.isoCode, flag: f.flagEmoji, name: f.localizedName, checked: false))
            }
        }

        // Return intermediates (e.g. CDG)
        if segmentReturnAirports.count > 2 {
            for ap in segmentReturnAirports.dropFirst().dropLast() {
                guard let a2 = allAps.first(where: { $0.iata == ap.iata })?.country,
                      let f = featureByA2(a2),
                      seen.insert(f.isoCode).inserted else { continue }
                layoverChoices.append(LayoverChoice(id: f.isoCode, flag: f.flagEmoji, name: f.localizedName, checked: false))
            }
        }
    }

    private var stepTitle: String {
        switch step {
        case 1: return "Tipo de transporte"
        case 2: return "Países del tramo"
        default: return "Fecha del tramo"
        }
    }

    // MARK: - Step 1: Transport
    @ViewBuilder
    private func transportStep() -> some View {
        VStack(spacing: 20) {
            Text("¿Con qué transporte?")
                .font(.palatino(.subheadline))
                .foregroundStyle(.secondary)
                .padding(.top, 20)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(PlannedDatePickerSheet.transports, id: \.emoji) { t in
                    let isSelected = selectedTransport == t.emoji
                    Button {
                        selectedTransport = t.emoji
                        if t.emoji == "✈️" {
                            showRoutePicker = true
                        } else {
                            step = 2
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text(t.emoji).font(.title)
                            Text(t.label)
                                .font(.system(size: 10))
                                .foregroundStyle(isSelected ? .white : .secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(
                            isSelected ? Color.blue : Color(.systemGray5),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    // MARK: - Step 2: Countries
    @ViewBuilder
    private func countriesStep() -> some View {
        VStack(spacing: 0) {
            let transport = selectedTransport ?? "🚌"
            Text("Selecciona los países con \(transport)")
                .font(.palatino(.subheadline))
                .foregroundStyle(.secondary)
                .padding(.vertical, 12)

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.subheadline)
                TextField("Buscar país", text: $searchQuery)
                    .font(.palatino(.body))
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16).padding(.bottom, 8)

            if !selectedIsoCodes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(selectedIsoCodes), id: \.self) { iso in
                            let f = features.first { $0.isoCode == iso }
                            HStack(spacing: 4) {
                                Text(f?.flagEmoji ?? "🌐").font(.caption)
                                Text(f?.localizedName ?? iso).font(.palatino(.caption))
                                Button { selectedIsoCodes.remove(iso) } label: {
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 6)
            }

            List(filteredFeatures, id: \.isoCode) { feature in
                Button {
                    if selectedIsoCodes.contains(feature.isoCode) {
                        selectedIsoCodes.remove(feature.isoCode)
                    } else {
                        selectedIsoCodes.insert(feature.isoCode)
                    }
                } label: {
                    HStack {
                        Text(feature.flagEmoji ?? "🌐").font(.title3)
                        Text(feature.localizedName).font(.palatino(.body)).foregroundStyle(.primary)
                        Spacer()
                        if selectedIsoCodes.contains(feature.isoCode) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                        }
                    }
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
                Text("Fecha del tramo \(transport)")
                    .font(.palatino(.subheadline))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12).padding(.bottom, 16)

                // Show route summary for airplane segments
                if transport == "✈️" && !segmentAirports.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(segmentAirports.map { $0.iata }.joined(separator: " → "))
                            .font(.palatino(.caption, weight: .bold)).foregroundStyle(.blue)
                        if !segmentReturnAirports.isEmpty {
                            Text(segmentReturnAirports.map { $0.iata }.joined(separator: " → "))
                                .font(.palatino(.caption, weight: .bold)).foregroundStyle(.blue.opacity(0.65))
                        }
                        if !segmentAirlines.isEmpty {
                            Text(segmentAirlines.map { $0.name }.joined(separator: ", "))
                                .font(.palatino(.caption)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 12)

                    // Destination auto-mark label
                    if let destIso = destinationIso,
                       let destFeature = features.first(where: { $0.isoCode == destIso }) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.subheadline)
                            Text(destFeature.flagEmoji ?? "🌐")
                            Text("\(destFeature.localizedName) se añade como visitado")
                                .font(.palatino(.caption)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16).padding(.bottom, 8)
                    }

                    // Layover visit prompts
                    if !layoverChoices.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(isForFuture ? "¿Harás parada en...?" : "¿Visitaste alguna escala?")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                            ForEach(layoverChoices) { choice in
                                let idx = layoverChoices.firstIndex(where: { $0.id == choice.id })!
                                Button {
                                    layoverChoices[idx].checked.toggle()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: layoverChoices[idx].checked ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(layoverChoices[idx].checked ? .blue : .secondary)
                                        Text(choice.flag ?? "🌐")
                                        Text(choice.name)
                                            .font(.palatino(.body)).foregroundStyle(.primary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 12)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 16).padding(.bottom, 12)
                    }
                }

                HStack(spacing: 0) {
                    dateTab(isFrom: true,  label: "DESDE", value: Self.fmt.string(from: dateFrom))
                    dateTab(isFrom: false, label: "HASTA",
                            value: dateTo.map { Self.fmt.string(from: $0) } ?? "Sin vuelta")
                }
                .padding(.horizontal, 16).padding(.bottom, 12)

                RangeDatePicker(
                    dateFrom: $dateFrom, dateTo: $dateTo, pickingFrom: $pickingFrom,
                    minDate: isForFuture ? tomorrow : nil,
                    maxDate: isForFuture ? nil : today
                )
                .padding(.horizontal, 8)
                .frame(height: 340)
                .padding(.bottom, 16)

                Button {
                    let isos = finalIsoCodes
                    let segment = TripSegment(
                        transport: selectedTransport ?? "🌍",
                        isoCodes: Array(isos),
                        dateFrom: dateFrom,
                        dateTo: dateTo,
                        airports: segmentAirports.isEmpty ? nil : segmentAirports,
                        returnAirports: segmentReturnAirports.isEmpty ? nil : segmentReturnAirports,
                        airlines: segmentAirlines.isEmpty ? nil : segmentAirlines,
                        hasLayover: (segmentHasLayover || segmentAirports.count > 2 || segmentReturnAirports.count > 2) ? true : nil
                    )
                    onAdd(segment)
                    dismiss()
                } label: {
                    Text("Añadir transporte")
                        .font(.palatino(.body, weight: .bold)).frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private func dateTab(isFrom: Bool, label: String, value: String) -> some View {
        let active = pickingFrom == isFrom
        let color: Color = active ? .blue : (isFrom ? .primary : (dateTo == nil ? .secondary : .primary))
        Button { pickingFrom = isFrom } label: {
            VStack(spacing: 2) {
                Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Text(value).font(.palatino(.subheadline, weight: .bold)).foregroundStyle(color)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(active ? Color.blue.opacity(0.08) : Color.clear)
            .overlay(alignment: .bottom) {
                if active { Rectangle().fill(Color.blue).frame(height: 2) }
            }
        }.buttonStyle(.plain)
    }
}
