//
//  TopBarWidgets.swift
//  Raskmap
//
//  Subvistas del top bar y bottom sheet del país:
//  · StatBadge — badge contador (visitados/próximos/etc) en el dock.
//  · LegendItem — fila de leyenda visual.
//  · CountryBottomSheet — sheet de acciones al tappear un país.
//  · ActionButton — botón rectangular con label/color/selected.
//
//  Reutilizadas desde ContentView root y varias sheets.
//
//  Extraído de ContentView.swift durante Fase D.
//

import SwiftUI

// MARK: - Subvistas

struct StatBadge: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.custom("Satoshi-Bold", size: 20))
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(.custom("Satoshi-Regular", size: 9))
                .foregroundStyle(.secondary)
                .tracking(0.4)
        }
        .frame(minWidth: 70)
        .padding(.vertical, 9)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: Radius.cell, style: .continuous))
        // VoiceOver: combina los dos textos en una sola cadena legible
        // en lugar de leer "42" y "Visitados" como elementos separados.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color.opacity(0.8))
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(color, lineWidth: 0.5))
            Text(label)
                .font(.custom("Satoshi-Regular", size: 10))
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Leyenda: \(label)")
    }
}

// MARK: - Bottom Sheet país
struct CountryBottomSheet: View {
    let country: Country
    let displayName: String
    let flagEmoji: String?
    var isoA2: String? = nil
    let onStatusChange: (CountryStatus) -> Void
    let onDismiss: () -> Void
    var showBucketList: Bool = true
    var onAddPastTrip: (() -> Void)? = nil
    var onAddNextTrip: (() -> Void)? = nil
    var onEditTrips: (() -> Void)? = nil

    @EnvironmentObject private var colorTheme: ColorThemeManager
    @State private var showRemoveConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Hero header — la bandera arranca con un margen amplio para no quedar
            // pegada al drag indicator del sheet ni cortarse en pantallas estrechas.
            VStack(spacing: 12) {
                Group {
                    if let iso = isoA2, !iso.isEmpty {
                        TwemojiFlag(iso2: iso, size: 64, fallbackEmoji: flagEmoji ?? "🌐")
                    } else {
                        FlagLabel(emoji: flagEmoji ?? "🌐", size: 64)
                    }
                }
                .frame(width: 80, height: 80)
                Text(displayName)
                    .font(.palatino(.title2, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 24)
                if country.status != .none {
                    Text(country.status.label)
                        .font(.custom("Satoshi-Regular", size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Color(.systemGray5), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
            .padding(.bottom, 20)

            Divider()
                .padding(.horizontal, 24)

            VStack(spacing: 8) {
                let isVisited = country.status == .visited
                ActionButton(
                    label: isVisited ? "✅ Añadido a visitados" : "✅ Añadir a visitados",
                    color: colorTheme.visitedColor,
                    isSelected: isVisited,
                    action: {
                        if isVisited { showRemoveConfirm = true }
                        else { onStatusChange(.visited) }
                    }
                )
                if isVisited {
                    ActionButton(
                        label: "🗓 Añadir viaje pasado",
                        color: .secondary,
                        isSelected: false,
                        action: { onAddPastTrip?() }
                    )
                    ActionButton(
                        label: "🗺️ Ver viajes",
                        color: .secondary,
                        isSelected: false,
                        action: { onEditTrips?() }
                    )
                }
                if country.status != .lived {
                    let isProximo = country.status == .wantToVisit
                    ActionButton(
                        label: isProximo ? "🔜 Añadido a próximos" : "🔜 Añadir próximo viaje",
                        color: colorTheme.wantToVisitColor,
                        isSelected: isProximo,
                        action: {
                            if isProximo { showRemoveConfirm = true }
                            else { onAddNextTrip?() }
                        }
                    )
                }
                if showBucketList && (country.status == .none || country.status == .bucketList) {
                    let isBucket = country.status == .bucketList
                    ActionButton(
                        label: isBucket ? "📝 Añadido a quiero ir" : "📝 Añadir a quiero ir",
                        color: colorTheme.bucketListColor,
                        isSelected: isBucket,
                        action: {
                            if isBucket { showRemoveConfirm = true }
                            else { onStatusChange(.bucketList) }
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()
        }
        .alert("¿Eliminar de la lista?", isPresented: $showRemoveConfirm) {
            Button("Eliminar \(displayName)", role: .destructive) {
                onStatusChange(.none)
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("\(displayName) se eliminará de la lista.")
        }
    }
}

struct ActionButton: View {
    let label: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.palatino(.body, weight: .medium))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(color)
                        .font(.body)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .background(
                isSelected ? color.opacity(0.12) : Color(.systemGray6),
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(isSelected ? color.opacity(0.35) : .clear, lineWidth: 1)
            )
            .foregroundStyle(isSelected ? color : .primary)
        }
    }
}
