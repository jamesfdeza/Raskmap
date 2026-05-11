//
//  PassportAndFlightSlider.swift
//  Raskmap
//
//  Widgets de pasaporte y slider del modo vuelos:
//  · PassportAvatarView — vista del avatar pasaporte con proporciones
//    reales (822×1091 px scaled).
//  · PassportOption (enum) — pasaportes disponibles (ES/FR/UK/USA/etc).
//  · PassportPickerSheet — selector full-screen del pasaporte.
//  · FlightFilterSlider — slider modo vuelos (past/upcoming) con
//    cápsula transparente y thumb arrastrable.
//
//  Extraído de ContentView.swift durante Fase D.
//

import SwiftUI

// MARK: - Avatar pequeño para el header
struct PassportAvatarView: View {
    let key: String
    let height: CGFloat

    // Proporciones reales de las imágenes de pasaporte (≈ 822×1091 px).
    static let aspect: CGFloat = 822.0 / 1091.0

    var body: some View {
        let width = height * Self.aspect
        let corner = height * 0.08
        Image(key)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
    }
}

enum PassportOption: String, CaseIterable, Identifiable {
    case one   = "PASSPORT"
    case two   = "PASSPORT 2"
    case three = "PASSPORT 3"
    case four  = "PASSPORT 4"
    var id: String { rawValue }
}

struct PassportPickerSheet: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    Text("Elige tu pasaporte")
                        .font(.custom("Satoshi-Bold", size: 20))
                        .padding(.top, 4)
                    Text("Será tu avatar en la app.")
                        .font(.palatino(.footnote))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 6)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16),
                                    GridItem(.flexible(), spacing: 16)],
                          spacing: 16) {
                    ForEach(PassportOption.allCases) { opt in
                        PassportSelectableCard(key: opt.rawValue,
                                               isSelected: selection == opt.rawValue)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    selection = opt.rawValue
                                }
                            }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Listo") { dismiss() }.font(.palatino(.body, weight: .bold))
                }
            }
        }
        .appColorScheme()
    }
}

// `internal` (default access) — ContentView lo usa desde
// onboardingSheet() para mostrar el grid de pasaportes seleccionables.
struct PassportSelectableCard: View {
    let key: String
    let isSelected: Bool

    var body: some View {
        VStack {
            PassportAvatarView(key: key, height: 200)
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 26))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(6)
                    }
                }
                .scaleEffect(isSelected ? 1.03 : 1.0)
                .shadow(color: isSelected ? Color.accentColor.opacity(0.55) : .black.opacity(0.18),
                        radius: isSelected ? 12 : 5, y: 3)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Segmented slider (modo vuelo)
/// Segmented control con dos opciones (Visitados / Próximos).
/// Antes usaba `.glassEffect` de iOS 26, pero el blur del thumb ocultaba el
/// texto debajo. Ahora el thumb es una cápsula TRANSPARENTE con un borde
/// blanco suave y un degradado sutil — permite leer la palabra seleccionada
/// perfectamente y sigue viéndose atractivo.
struct FlightFilterSlider: View {
    @Binding var selection: FlightRouteFilter
    @GestureState private var dragDelta: CGFloat = 0
    @GestureState private var isPressing: Bool = false

    private let segments: [(FlightRouteFilter, String, String)] = [
        (.past,     "Finalizados", "checkmark.seal.fill"),
        (.upcoming, "Próximos",    "airplane.departure")
    ]

    private func index(_ f: FlightRouteFilter) -> Int {
        segments.firstIndex(where: { $0.0 == f }) ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let segW = geo.size.width / CGFloat(segments.count)
            let h = geo.size.height
            let baseX = segW * CGFloat(index(selection))
            let rawX = baseX + dragDelta
            let clampedX = max(0, min(geo.size.width - segW, rawX))
            let pressScale: CGFloat = isPressing ? 1.06 : 1.0

            ZStack(alignment: .leading) {
                // Thumb debajo del texto para no taparlo — cápsula transparente
                // con un gradiente sutil y borde blanco suave.
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.55), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.18), radius: 6, y: 2)
                    .frame(width: segW - 4, height: h - 4)
                    .scaleEffect(pressScale)
                    // ZStack(alignment: .leading) ya centra verticalmente,
                    // así que SOLO aplicamos offset horizontal (el +2 es el
                    // margen simétrico entre thumb y borde de la cápsula
                    // exterior). Antes tenía también y:2 que empujaba el
                    // thumb 2pt por debajo del centro y chocaba con el borde.
                    .offset(x: clampedX + 2)
                    .animation(.smooth(duration: 0.32), value: selection)
                    .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.85), value: isPressing)
                    .allowsHitTesting(false)

                // Textos con icono (arriba del thumb). Cada chip ocupa su slot.
                HStack(spacing: 0) {
                    ForEach(segments, id: \.0) { seg in
                        HStack(spacing: 6) {
                            Image(systemName: seg.2)
                                .font(.system(size: 12, weight: .semibold))
                            Text(seg.1)
                                .font(.custom("Satoshi-Bold", size: 13))
                        }
                        .foregroundStyle(selection == seg.0 ? Color.white : Color.white.opacity(0.55))
                        .frame(width: segW, height: h)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard selection != seg.0 else { return }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.smooth(duration: 0.32)) { selection = seg.0 }
                        }
                        .accessibilityAddTraits(selection == seg.0 ? [.isSelected, .isButton] : .isButton)
                        .accessibilityLabel("Filtro vuelos: \(seg.1)")
                    }
                }

            }
            // Drag simultáneo al tap — arrastrar el thumb actualiza selection.
            // Se aplica al ZStack entero para no bloquear los onTapGesture de
            // cada chip. minimumDistance > 0 evita conflicto con los taps.
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .updating($isPressing) { _, state, _ in state = true }
                    .updating($dragDelta) { value, state, _ in
                        state = value.translation.width
                    }
                    .onEnded { value in
                        let finalX = baseX + value.translation.width
                        let idx = Int((finalX + segW / 2) / segW)
                        let clamped = max(0, min(segments.count - 1, idx))
                        let newSel = segments[clamped].0
                        if newSel != selection {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                        withAnimation(.smooth(duration: 0.35)) { selection = newSel }
                    }
            )
            .background(
                // Fondo del propio slider: cápsula muy transparente para que
                // se vea sobre mapa/fondo sin dar sensación de bloque opaco.
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.28))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
            )
        }
        .frame(height: 38)
        .accessibilityElement(children: .contain)
    }
}
