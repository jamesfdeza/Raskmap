//
//  PlannedDatePickerSheet.swift
//  Raskmap
//
//  Selector de fecha para "Próximos viajes". Wizard que permite elegir
//  fechas (desde/hasta), transporte, título, aeropuertos (si vuelo),
//  aerolíneas y detalles de vuelo (asiento/clase/booking).
//  Devuelve los datos al caller via onSave para que cree el Trip.
//
//  Extraído de ContentView.swift durante Fase D.
//

import SwiftUI
import UIKit

// MARK: - Selector de fecha para Próximos
struct PlannedDatePickerSheet: View {
    let countryName: String
    let flagEmoji: String
    let existingDate: Date?
    let existingDateTo: Date?
    let existingTransport: String?
    let existingTitle: String?
    var isEditing: Bool = false
    let onSave: (Date, Date?, String?, String?, [TripAirport], [TripAirline], FlightInfo?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var dateFrom: Date
    @State private var dateTo: Date?
    @State private var pickingFrom: Bool = true
    @State private var selectedTransport: String?
    @State private var tripTitle: String
    @State private var selectedAirports: [TripAirport] = []
    @State private var selectedReturnAirports: [TripAirport] = []
    @State private var selectedAirlines: [TripAirline] = []
    @State private var hasLayover: Bool = false
    @State private var flightInfo = FlightInfo()
    @State private var showRoutePicker = false
    @State private var showConfirmation = false
    @State private var confirmVisits: [VisitEntry] = []
    @State private var confirmAirports: [AirportConfirmEntry] = []
    @State private var confirmAirlines: [AirlineConfirmEntry] = []

    static let transports: [(emoji: String, label: String)] = [
        ("✈️", "Avión"), ("🚗", "Coche"), ("🚂", "Tren"), ("🚌", "Bus"), ("🚢", "Barco"), ("🚶🏻", "Andando")
    ]
    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.locale = Locale(identifier: "es_ES"); return f
    }()
    private var tomorrow: Date {
        let cal = Calendar.current
        let nextDay = cal.date(byAdding: .day, value: 1, to: Date())
                    ?? Date().addingTimeInterval(86_400)
        return cal.startOfDay(for: nextDay)
    }

    init(countryName: String, flagEmoji: String,
         existingDate: Date?, existingDateTo: Date?, existingTransport: String?,
         existingTitle: String? = nil, isEditing: Bool = false,
         onSave: @escaping (Date, Date?, String?, String?, [TripAirport], [TripAirline], FlightInfo?) -> Void) {
        self.countryName = countryName
        self.flagEmoji = flagEmoji
        self.existingDate = existingDate
        self.existingDateTo = existingDateTo
        self.existingTransport = existingTransport
        self.existingTitle = existingTitle
        self.isEditing = isEditing
        self.onSave = onSave
        let cal = Calendar.current
        let tomorrowRaw = cal.date(byAdding: .day, value: 1, to: Date())
                        ?? Date().addingTimeInterval(86_400)
        let tomorrow = cal.startOfDay(for: tomorrowRaw)
        let initial = existingDate ?? tomorrow
        let from = max(initial, tomorrow)
        _dateFrom = State(initialValue: from)
        // Sin fecha de vuelta por defecto. Si ya existía una al editar, se respeta.
        _dateTo = State(initialValue: existingDateTo)
        _selectedTransport = State(initialValue: existingTransport)
        _tripTitle = State(initialValue: existingTitle ?? "")
    }

    private var rutaLabel: String {
        if selectedAirports.isEmpty { return "Aeropuertos y aerolíneas" }
        return selectedAirports.map { "\($0.iata) (\($0.count)x)" }.joined(separator: " → ")
    }
    private var airlinesLabel: String {
        selectedAirlines.map { "\($0.name) \($0.count)x" }.joined(separator: ", ")
    }

    private let accent = BrandColor.accent

    @ViewBuilder
    private func transportRow() -> some View {
        HStack(spacing: 8) {
            ForEach(Self.transports, id: \.emoji) { t in
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
        .padding(.horizontal, 24).padding(.bottom, 10)
    }

    @ViewBuilder
    private func dateTabsRow() -> some View {
        let fromLabel = Self.fmt.string(from: dateFrom)
        let toLabel = dateTo.map { Self.fmt.string(from: $0) } ?? "Sin vuelta"
        HStack(spacing: 12) {
            dateTab(isFrom: true, label: "DESDE", value: fromLabel)
            dateTab(isFrom: false, label: "HASTA", value: toLabel)
        }
        .padding(.horizontal, 24)
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

    var body: some View {
        ZStack {
        NavigationStack {
            ScrollView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 6) {
                    FlagLabel(emoji: flagEmoji, size: 52)
                    Text(countryName)
                        .font(.custom("Satoshi-Bold", size: 24))
                    Text(isEditing ? "Editar fecha de viaje" : "Añadir a Próximos")
                        .font(.palatino(.subheadline))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 28).padding(.bottom, 24)

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
                .padding(.bottom, 20)

                VStack(alignment: .leading, spacing: 8) {
                    Text("TRANSPORTE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary).tracking(1.0)
                        .padding(.horizontal, 24)
                    transportRow()
                }
                .padding(.bottom, 8)

                if selectedTransport == "✈️" {
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
                                    Text(rutaLabel)
                                        .font(.palatino(.body))
                                        .foregroundStyle(selectedAirports.isEmpty ? .secondary : .primary)
                                    if !selectedAirlines.isEmpty {
                                        Text(airlinesLabel)
                                            .font(.palatino(.caption)).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.card))
                            .padding(.horizontal, 24)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 12)

                    FlightInfoSection(info: $flightInfo,
                                      outboundRoute: selectedAirports.map { $0.iata },
                                      returnRoute: selectedReturnAirports.map { $0.iata })
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("FECHAS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary).tracking(1.0)
                        .padding(.horizontal, 24)
                    dateTabsRow().padding(.bottom, 8)
                    RangeDatePicker(dateFrom: $dateFrom, dateTo: $dateTo, pickingFrom: $pickingFrom,
                                    minDate: tomorrow)
                        .padding(.horizontal, 8).frame(height: 340)
                }
                .padding(.bottom, 24)

                let canSave = selectedTransport != nil
                Button { prepareConfirmation() } label: {
                    Text(isEditing ? "Guardar cambios" : "Añadir a Próximos")
                        .font(.custom("Satoshi-Bold", size: 16))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(canSave ? accent : Color(.systemGray4), in: RoundedRectangle(cornerRadius: Radius.card))
                        .foregroundStyle(.white)
                        .shadow(color: canSave ? accent.opacity(0.3) : .clear, radius: 12, y: 4)
                }
                .disabled(!canSave)
                .padding(.horizontal, 24).padding(.bottom, 36)
            }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .presentationDetents([.large])
        .sheet(isPresented: $showRoutePicker) {
            RouteWizardSheet(airports: $selectedAirports, returnAirports: $selectedReturnAirports,
                             airlines: $selectedAirlines, hasLayover: $hasLayover, onDone: {})
        }

        if showConfirmation {
            plannedConfirmCard(
                onSave: {
                    showConfirmation = false
                    let title: String? = tripTitle.trimmingCharacters(in: .whitespaces).isEmpty ? nil
                        : tripTitle.trimmingCharacters(in: .whitespaces)
                    let airports = confirmAirports.map { TripAirport(iata: $0.iata, count: $0.count) }
                    let airlines = confirmAirlines.map { TripAirline(name: $0.name, count: $0.count) }
                    onSave(dateFrom, dateTo, selectedTransport, title, airports, airlines, flightInfo.hasAnyData ? flightInfo : nil)
                    dismiss()
                },
                onCancel: { showConfirmation = false }
            )
        }
        }
    }

    private func prepareConfirmation() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        confirmVisits = [VisitEntry(isoCode: "", flagEmoji: flagEmoji, name: countryName, count: 1)]
        if selectedTransport == "✈️" {
            var apC: [String: Int] = [:]
            for ap in selectedAirports { apC[ap.iata, default: 0] += ap.count }
            for ap in selectedReturnAirports { apC[ap.iata, default: 0] += ap.count }
            confirmAirports = apC.map { AirportConfirmEntry(iata: $0.key, count: $0.value) }.sorted { $0.iata < $1.iata }
            confirmAirlines = selectedAirlines.map { AirlineConfirmEntry(name: $0.name, count: $0.count) }
        } else {
            confirmAirports = []
            confirmAirlines = []
        }
        showConfirmation = true
    }

    @ViewBuilder
    private func plannedConfirmCard(onSave: @escaping () -> Void, onCancel: @escaping () -> Void) -> some View {
        confirmCardContent(
            confirmVisits: $confirmVisits, confirmAirports: $confirmAirports, confirmAirlines: $confirmAirlines,
            accent: accent, onSave: onSave, onCancel: onCancel
        )
    }
}

// `internal` (default) para que ContentView pueda usarlo desde AddTripSheet
// y EditTripSheet (ambos hasta que se extraigan) — antes era `private` al
// archivo cuando estaba en ContentView.swift, ahora cross-file.
struct confirmCardContent: View {
    @Binding var confirmVisits: [VisitEntry]
    @Binding var confirmAirports: [AirportConfirmEntry]
    @Binding var confirmAirlines: [AirlineConfirmEntry]
    let accent: Color
    let onSave: () -> Void
    let onCancel: () -> Void
    @State private var isSaving: Bool = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    ZStack {
                        Circle().fill(accent.opacity(0.12)).frame(width: 44, height: 44)
                        Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundStyle(accent)
                    }
                    Text("Confirmar viaje")
                        .font(.custom("Satoshi-Bold", size: 18))
                    Text("Ajusta los conteos si es necesario")
                        .font(.palatino(.caption))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20).padding(.bottom, 16)

                Rectangle().fill(Color(.systemGray5)).frame(height: 0.5)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if !confirmVisits.isEmpty {
                            sectionHeader("PAÍSES")
                            ForEach($confirmVisits) { $entry in
                                counterRow(leading: {
                                    HStack(spacing: 10) {
                                        if !entry.flagEmoji.isEmpty { FlagLabel(emoji: entry.flagEmoji, size: 22) }
                                        Text(entry.name).font(.palatino(.body)).lineLimit(1)
                                    }
                                }, count: $entry.count, accent: accent)
                            }
                        }
                        if !confirmAirports.isEmpty {
                            sectionHeader("AEROPUERTOS")
                            ForEach($confirmAirports) { $ap in
                                counterRow(leading: {
                                    HStack(spacing: 8) {
                                        Text("✈️").font(.system(size: 18))
                                        Text(ap.iata).font(.custom("Satoshi-Bold", size: 15))
                                    }
                                }, count: $ap.count, accent: accent)
                            }
                        }
                        if !confirmAirlines.isEmpty {
                            sectionHeader("AEROLÍNEAS")
                            ForEach($confirmAirlines) { $al in
                                counterRow(leading: {
                                    Text(al.name).font(.palatino(.body)).lineLimit(1)
                                }, count: $al.count, accent: accent)
                            }
                        }
                    }
                }
                .frame(maxHeight: 280)

                Rectangle().fill(Color(.systemGray5)).frame(height: 0.5)

                HStack(spacing: 10) {
                    Button { if !isSaving { onCancel() } } label: {
                        Text("Cancelar")
                            .font(.custom("Satoshi-Medium", size: 15))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: Radius.cell))
                            .foregroundStyle(.primary)
                    }.buttonStyle(.plain).disabled(isSaving)
                    Button {
                        guard !isSaving else { return }
                        isSaving = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            onSave()
                        }
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Text("Guardar").font(.custom("Satoshi-Bold", size: 15))
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(accent, in: RoundedRectangle(cornerRadius: Radius.cell))
                        .foregroundStyle(.white)
                    }.buttonStyle(.plain).disabled(isSaving)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: Radius.sheet))
            .padding(.horizontal, 18)
            .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
        }
        .presentationBackground(.clear)
        .interactiveDismissDisabled(true)
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary).tracking(0.8)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
    }

    @ViewBuilder
    private func counterRow<L: View>(leading: () -> L, count: Binding<Int>, accent: Color) -> some View {
        HStack(spacing: 10) {
            leading()
            Spacer()
            HStack(spacing: 14) {
                Button { if count.wrappedValue > 0 { count.wrappedValue -= 1 } } label: {
                    Text("−").font(.system(size: 18, weight: .medium))
                        .frame(width: 34, height: 34)
                        .background(Color(.systemGray5), in: Circle())
                        .foregroundStyle(.primary)
                        // Hit area expandida a 44pt mínimo (Apple HIG) sin
                        // cambiar el círculo visual de 34pt.
                        .frame(minWidth: TapTarget.min, minHeight: TapTarget.min)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                Text("\(count.wrappedValue)")
                    .font(.custom("Satoshi-Bold", size: 16))
                    .frame(minWidth: 28, alignment: .center)
                Button { count.wrappedValue += 1 } label: {
                    Text("+").font(.system(size: 18, weight: .medium))
                        .frame(width: 34, height: 34)
                        .background(accent, in: Circle())
                        .foregroundStyle(.white)
                        .frame(minWidth: TapTarget.min, minHeight: TapTarget.min)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        Rectangle().fill(Color(.systemGray6)).frame(height: 1).padding(.leading, 16)
    }
}
