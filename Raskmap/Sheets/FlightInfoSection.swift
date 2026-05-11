//
//  FlightInfoSection.swift
//  Raskmap
//
//  Componentes UI usados desde varias sheets de viaje:
//  · FlightInfoSection — sección editable de FlightInfo (booking ref,
//    asiento, posición, clase) por leg. Aparece en AddSegmentSheet
//    step 3 y EditTripSheet.
//  · TableFlagPickerSheet — picker de bandera para tabla top.
//  · UsernameEditView — edición inline del username en perfil.
//
//  Self-contained tras la extracción.
//

import SwiftUI
import UIKit

// MARK: - FlightInfoSection

struct FlightInfoSection: View {
    @Binding var info: FlightInfo
    /// Aeropuertos IATA de ida (orden). Si tiene N elementos → N-1 tramos.
    var outboundRoute: [String] = []
    /// Aeropuertos IATA de vuelta. Vacío = one-way. Si tiene N elementos → N-1 tramos.
    var returnRoute: [String] = []

    private let seatPositions: [(String, String)] = [("Pasillo", "pasillo"), ("Medio", "medio"), ("Ventana", "ventana")]
    private let classes: [(String, String)] = [("Turista", "turista"), ("Economy+", "economy+"), ("Business", "business"), ("First", "first")]
    private let accent = BrandColor.accent

    private var outboundLegCount: Int { max(0, outboundRoute.count - 1) }
    private var returnLegCount: Int { max(0, returnRoute.count - 1) }
    private var totalLegCount: Int { outboundLegCount + returnLegCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DETALLES DEL VUELO")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1.0)
                .padding(.horizontal, 24)

            // Reserva — compartida (la misma PNR cubre todos los tramos)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 13)).foregroundStyle(accent).frame(width: 20)
                    Text("Reserva").font(.palatino(.body))
                    Spacer()
                    TextField("ABC123", text: $info.bookingRef)
                        .font(.custom("Satoshi-Bold", size: 15))
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .foregroundStyle(accent)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.section))
            .padding(.horizontal, 24)

            if totalLegCount <= 0 {
                // Sin ruta → editor único ligado a los escalares legacy (compat con trips antiguos).
                legEditor(
                    title: nil,
                    seat: $info.seatNumber,
                    pos: $info.seatPosition,
                    cabin: $info.cabinClass
                )
            } else {
                // Cuando hay >1 tramos, ofrecemos un botón rápido "Aplicar a
                // todos" que copia la clase + posición + asiento del primer
                // tramo a TODOS los demás. Asiento exacto rara vez se repite,
                // pero clase/posición sí. El usuario puede luego ajustar
                // tramos individuales que difieran.
                if totalLegCount > 1, info.outboundLegs.first?.hasAnyData == true {
                    Button { applyFirstLegToAll() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Aplicar clase y posición a todos los tramos")
                                .font(.palatino(.caption, weight: .bold))
                        }
                        .foregroundStyle(accent)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(accent.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                }
                // Ida
                if outboundLegCount > 0 {
                    if outboundRoute.count > 2 || returnLegCount > 0 {
                        sectionLabel("IDA")
                    }
                    ForEach(Array(0..<outboundLegCount), id: \.self) { idx in
                        let showTitle = totalLegCount > 1
                        let title: String? = showTitle ? legTitle(route: outboundRoute, idx: idx) : nil
                        legEditor(
                            title: title,
                            seat: outboundBinding(\.seatNumber, idx: idx),
                            pos: outboundBinding(\.seatPosition, idx: idx),
                            cabin: outboundBinding(\.cabinClass, idx: idx)
                        )
                    }
                }
                // Vuelta
                if returnLegCount > 0 {
                    sectionLabel("VUELTA")
                    ForEach(Array(0..<returnLegCount), id: \.self) { idx in
                        let title: String? = legTitle(route: returnRoute, idx: idx)
                        legEditor(
                            title: title,
                            seat: returnBinding(\.seatNumber, idx: idx),
                            pos: returnBinding(\.seatPosition, idx: idx),
                            cabin: returnBinding(\.cabinClass, idx: idx)
                        )
                    }
                }
            }
        }
        .padding(.bottom, 12)
        .onAppear { migrateLegacyAndResize() }
        .onChange(of: outboundRoute) { _, _ in ensureLegsSized() }
        .onChange(of: returnRoute)   { _, _ in ensureLegsSized() }
    }

    // MARK: - Helpers

    private func legTitle(route: [String], idx: Int) -> String {
        guard route.indices.contains(idx), route.indices.contains(idx + 1) else { return "" }
        return "\(route[idx]) → \(route[idx + 1])"
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(accent.opacity(0.85))
            .tracking(0.8)
            .padding(.horizontal, 24)
            .padding(.top, 2)
    }

    /// Garantiza que `outboundLegs.count == outboundLegCount` y lo mismo para return.
    /// Se llama en onAppear y cuando cambia la ruta.
    /// Hace UN solo round-trip por @Binding para evitar que filtros aguas arriba
    /// (p.ej. el `hasAnyData ? newValue : nil` de `segmentFlightInfoBinding`) descarten
    /// estados intermedios donde los tramos están todavía "vacíos".
    private func ensureLegsSized() {
        var current = info
        var changed = false
        while current.outboundLegs.count < outboundLegCount { current.outboundLegs.append(FlightLegInfo()); changed = true }
        if current.outboundLegs.count > outboundLegCount {
            current.outboundLegs = Array(current.outboundLegs.prefix(outboundLegCount)); changed = true
        }
        while current.returnLegs.count < returnLegCount { current.returnLegs.append(FlightLegInfo()); changed = true }
        if current.returnLegs.count > returnLegCount {
            current.returnLegs = Array(current.returnLegs.prefix(returnLegCount)); changed = true
        }
        if changed { info = current }
    }

    /// Migra los escalares legacy al primer tramo disponible y los vacía, idempotente.
    /// Single round-trip a través de `info` para no atravesar el filtro `hasAnyData`
    /// múltiples veces con estados vacíos intermedios.
    private func migrateLegacyAndResize() {
        var current = info
        // ensureLegsSized inline sobre current
        while current.outboundLegs.count < outboundLegCount { current.outboundLegs.append(FlightLegInfo()) }
        if current.outboundLegs.count > outboundLegCount {
            current.outboundLegs = Array(current.outboundLegs.prefix(outboundLegCount))
        }
        while current.returnLegs.count < returnLegCount { current.returnLegs.append(FlightLegInfo()) }
        if current.returnLegs.count > returnLegCount {
            current.returnLegs = Array(current.returnLegs.prefix(returnLegCount))
        }

        if totalLegCount > 0 {
            let legsHaveData = current.outboundLegs.contains(where: { $0.hasAnyData })
                             || current.returnLegs.contains(where: { $0.hasAnyData })
            let hasLegacy = !current.seatNumber.isEmpty || !current.seatPosition.isEmpty || !current.cabinClass.isEmpty
            if !legsHaveData && hasLegacy {
                if outboundLegCount > 0, !current.outboundLegs.isEmpty {
                    current.outboundLegs[0].seatNumber = current.seatNumber
                    current.outboundLegs[0].seatPosition = current.seatPosition
                    current.outboundLegs[0].cabinClass = current.cabinClass
                } else if returnLegCount > 0, !current.returnLegs.isEmpty {
                    current.returnLegs[0].seatNumber = current.seatNumber
                    current.returnLegs[0].seatPosition = current.seatPosition
                    current.returnLegs[0].cabinClass = current.cabinClass
                }
                current.seatNumber = ""
                current.seatPosition = ""
                current.cabinClass = ""
            }
        }

        if current != info { info = current }
    }

    /// Replica la clase y posición del primer tramo de IDA al resto (ida + vuelta).
    /// El asiento concreto NO se replica (siempre es distinto por tramo).
    private func applyFirstLegToAll() {
        guard let first = info.outboundLegs.first else { return }
        var current = info
        for i in current.outboundLegs.indices {
            if i == 0 { continue }
            current.outboundLegs[i].seatPosition = first.seatPosition
            current.outboundLegs[i].cabinClass = first.cabinClass
        }
        for i in current.returnLegs.indices {
            current.returnLegs[i].seatPosition = first.seatPosition
            current.returnLegs[i].cabinClass = first.cabinClass
        }
        info = current
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func outboundBinding(_ kp: WritableKeyPath<FlightLegInfo, String>, idx: Int) -> Binding<String> {
        Binding(
            get: {
                guard info.outboundLegs.indices.contains(idx) else { return "" }
                return info.outboundLegs[idx][keyPath: kp]
            },
            set: { newValue in
                var current = info
                while current.outboundLegs.count <= idx { current.outboundLegs.append(FlightLegInfo()) }
                current.outboundLegs[idx][keyPath: kp] = newValue
                info = current
            }
        )
    }

    private func returnBinding(_ kp: WritableKeyPath<FlightLegInfo, String>, idx: Int) -> Binding<String> {
        Binding(
            get: {
                guard info.returnLegs.indices.contains(idx) else { return "" }
                return info.returnLegs[idx][keyPath: kp]
            },
            set: { newValue in
                var current = info
                while current.returnLegs.count <= idx { current.returnLegs.append(FlightLegInfo()) }
                current.returnLegs[idx][keyPath: kp] = newValue
                info = current
            }
        )
    }

    @ViewBuilder
    private func legEditor(
        title: String?,
        seat: Binding<String>,
        pos: Binding<String>,
        cabin: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = title, !title.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "airplane")
                        .font(.system(size: 11)).foregroundStyle(accent)
                    Text(title)
                        .font(.custom("Satoshi-Bold", size: 13))
                        .foregroundStyle(accent)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 2)
            }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "seat.fill")
                        .font(.system(size: 13)).foregroundStyle(accent).frame(width: 20)
                    Text("Asiento").font(.palatino(.body))
                    Spacer()
                    TextField("19A", text: seat)
                        .font(.custom("Satoshi-Bold", size: 15))
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .foregroundStyle(accent)
                        .frame(width: 72)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)

                Rectangle().fill(Color(.systemGray5)).frame(height: 0.5).padding(.leading, 16)

                HStack(spacing: 6) {
                    ForEach(seatPositions, id: \.1) { label, val in
                        Button {
                            pos.wrappedValue = pos.wrappedValue == val ? "" : val
                        } label: {
                            Text(label).font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(pos.wrappedValue == val ? accent : Color(.systemGray5),
                                            in: RoundedRectangle(cornerRadius: Radius.chip))
                                .foregroundStyle(pos.wrappedValue == val ? .white : .primary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)

                Rectangle().fill(Color(.systemGray5)).frame(height: 0.5).padding(.leading, 16)

                HStack(spacing: 6) {
                    ForEach(classes, id: \.1) { label, val in
                        Button {
                            cabin.wrappedValue = cabin.wrappedValue == val ? "" : val
                        } label: {
                            Text(label).font(.system(size: 11, weight: .medium))
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(cabin.wrappedValue == val ? accent : Color(.systemGray5),
                                            in: RoundedRectangle(cornerRadius: Radius.chip))
                                .foregroundStyle(cabin.wrappedValue == val ? .white : .primary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.section))
            .padding(.horizontal, 24)
        }
    }
}


// MARK: - Fila de medalla con hasta 3 banderas y botón editar
// MARK: - Picker de bandera para tabla top
struct TableFlagPickerSheet: View {
    let spot: ProfileSheet.TopSpot
    let features: [CountryFeature]
    let currentEmoji: String?
    let usedEmojis: Set<String>
    let onSelect: (String) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    private var filtered: [CountryFeature] {
        guard !searchText.isEmpty else { return features }
        let q = searchText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return features.filter {
            $0.localizedName
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .contains(q)
        }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Buscar país…", text: $searchText).autocorrectionDisabled()
                }
                .padding(10)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                ScrollView {
                    if filtered.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "airplane.circle")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("No tienes países visitados en esta región.")
                                .font(.palatino(.subheadline))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 60)
                        .padding(.horizontal, 32)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(filtered, id: \.isoCode) { feature in
                                let emoji   = feature.flagEmoji ?? "🌐"
                                let isChosen = emoji == currentEmoji
                                let isUsed   = usedEmojis.contains(emoji) && !isChosen
                                Button {
                                    guard !isUsed else { return }
                                    onSelect(emoji)
                                    dismiss()
                                } label: {
                                    VStack(spacing: 4) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: Radius.cell)
                                                .fill(isChosen
                                                      ? Color.blue.opacity(0.18)
                                                      : isUsed ? Color(.systemGray6).opacity(0.4)
                                                               : Color(.systemGray6))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: Radius.cell)
                                                        .strokeBorder(isChosen ? Color.blue : Color.clear,
                                                                      lineWidth: 2)
                                                )
                                                .frame(width: 60, height: 60)
                                            FlagLabel(emoji: emoji, size: 36)
                                                .opacity(isUsed ? 0.3 : 1.0)
                                        }
                                        Text(feature.localizedName)
                                            .font(.palatino(.caption2))
                                            .foregroundStyle(isUsed ? .tertiary : .secondary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(isUsed)
                            }
                        }
                        .padding(16)
                    }
                }

                if currentEmoji != nil {
                    Divider()
                    Button(role: .destructive) {
                        onClear()
                        dismiss()
                    } label: {
                        Text("Eliminar selección")
                            .font(.palatino(.body))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("\(spot.medal.emoji) \(spot.region.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
    }
}



// MARK: - Edición de nombre inline en perfil
struct UsernameEditView: View {
    @Binding var username: String
    @State private var isEditing: Bool = false
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        if isEditing {
            // Modo edición: campo centrado con ✓ a la derecha
            HStack(spacing: 0) {
                Text("@")
                    .font(.palatino(.title3))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
                TextField("usuario", text: $draft)
                    .font(.palatino(.title3))
                    .multilineTextAlignment(.leading)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focused)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 6)
                    .onChange(of: draft) {
                        draft = String(
                            draft.lowercased()
                                .filter { $0.isLetter || $0.isNumber || $0 == "_" }
                                .prefix(10)
                        )
                    }
                Button {
                    let clean = draft.trimmingCharacters(in: .whitespaces)
                    if !clean.isEmpty { username = clean }
                    isEditing = false
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .padding(.trailing, 12)
                }
            }
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
            .frame(maxWidth: 240)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
        } else {
            // Modo lectura: @nombre centrado + lápiz justo a su derecha
            HStack(spacing: 6) {
                Text(username.isEmpty ? "usuario" : "@ \(username)")
                    .font(.palatino(.title3))
                    .foregroundStyle(username.isEmpty ? .secondary : .primary)
                Button {
                    draft = username
                    isEditing = true
                    focused = true
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
        }
    }
}



// MARK: - Modelos auxiliares para la confirmación de guardado
struct VisitEntry: Identifiable {
    var id: String { isoCode }
    let isoCode: String
    let flagEmoji: String
    let name: String
    var count: Int
}

struct ProximoRow: Identifiable {
    let id: String
    let country: Country
    let trip: Trip?

    var isoCode: String { country.isoCode }
    var dateFrom: Date? { trip?.dateFrom ?? country.plannedDate }
    var dateTo: Date? { trip?.dateTo ?? country.plannedDateTo }
    var transport: String? { trip?.transport ?? country.transport }
    var rowTitle: String? { trip?.title ?? country.plannedTitle }
}

// Payload identificable para el sheet de "Finalizados" del perfil.
// Ver YearTravelView.onFinalizadosTap.
struct FinalizadosSheetPayload: Identifiable, Equatable {
    var id: Int { year }
    let year: Int
}

struct AirportConfirmEntry: Identifiable {
    var id: String { iata }
    let iata: String
    var count: Int
}

struct AirlineConfirmEntry: Identifiable {
    var id: String { name }
    let name: String
    var count: Int
}

// MARK: - Achievement toast (UIWindow, aparece sobre modales)
final class AchievementToastController {
    static let shared = AchievementToastController()
    private var toastWindow: UIWindow?

    func show(_ toasts: [AchievementKind], menuPositionIsTop: Bool, isRaskmapPro: Bool) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        toastWindow?.isHidden = true
        toastWindow = nil
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = false
        let view = AchievementToastView(toasts: toasts, menuPositionIsTop: menuPositionIsTop, isRaskmapPro: isRaskmapPro)
        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        toastWindow = window
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4.0))
            await MainActor.run {
                self?.toastWindow?.isHidden = true
                self?.toastWindow = nil
            }
        }
    }
}

private struct AchievementToastView: View {
    let toasts: [AchievementKind]
    let menuPositionIsTop: Bool
    let isRaskmapPro: Bool

    var body: some View {
        VStack {
            if menuPositionIsTop { Spacer() }
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(toasts, id: \.title) { kind in
                        HStack(spacing: 8) {
                            Text(kind.title)
                                .font(.palatino(.body, weight: .bold))
                                .foregroundStyle(.white)
                            Text(kind.medal).font(.title3)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: Radius.card))
                        .overlay {
                            if !isRaskmapPro {
                                RoundedRectangle(cornerRadius: Radius.card)
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        Image(systemName: "lock.fill")
                                            .foregroundStyle(.purple)
                                            .font(.title3)
                                    }
                            }
                        }
                    }
                }
                .padding(.trailing, 16)
                .padding(.top, menuPositionIsTop ? 0 : 55)
                .padding(.bottom, menuPositionIsTop ? 110 : 0)
            }
            if !menuPositionIsTop { Spacer() }
        }
    }
}
