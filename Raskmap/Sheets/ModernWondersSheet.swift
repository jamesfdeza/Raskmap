//
//  ModernWondersSheet.swift
//  Raskmap
//
//  Sheet de las 7 Maravillas Modernas. El usuario marca/desmarca cada
//  maravilla con un tap en su tarjeta. Cuando las 7 están marcadas, el
//  logro `sieteMaravillas` (🏆) se desbloquea automáticamente vía la
//  evaluación reactiva en ContentView / ProfileSheet.
//
//  Persistencia: `@AppStorage("modernWondersVisited")` con un JSON Set<String>
//  de identificadores de maravilla. Desacoplado de Trip/Country — no usa
//  SwiftData. Sync vía iCloud Key-Value Store no aplica aquí (es local
//  por device); si en el futuro se quiere CloudKit-sync, migrar a un
//  modelo `@Model`.
//

import SwiftUI

/// Las 7 maravillas del mundo moderno (lista de "New 7 Wonders" votada en
/// 2007). Cada maravilla tiene un id estable, un emoji que la evoca y un
/// nombre + país para mostrar bajo el icono. El id se usa como clave en
/// el Set persistido — no cambiar valores existentes para no perder marcas
/// guardadas previamente.
struct ModernWonder: Identifiable, Hashable {
    let id: String       // clave estable para AppStorage (no cambiar)
    let emoji: String    // logo visual sobre la tarjeta
    let name: String     // nombre del monumento
    let country: String  // país (display secundario)

    static let all: [ModernWonder] = [
        ModernWonder(id: "gran_muralla", emoji: "🏯",   name: "Gran Muralla",    country: "China"),
        ModernWonder(id: "petra",        emoji: "🏛️", name: "Petra",            country: "Jordania"),
        ModernWonder(id: "cristo",       emoji: "✝️",  name: "Cristo Redentor", country: "Brasil"),
        ModernWonder(id: "machu_picchu", emoji: "⛰️",  name: "Machu Picchu",    country: "Perú"),
        ModernWonder(id: "chichen_itza", emoji: "🌮",  name: "Chichén Itzá",    country: "México"),
        ModernWonder(id: "coliseo",      emoji: "🏟️", name: "Coliseo",          country: "Italia"),
        ModernWonder(id: "taj_mahal",    emoji: "🕌",  name: "Taj Mahal",       country: "India"),
    ]
}

struct ModernWondersSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// JSON-encoded `Set<String>` con los ids de maravillas marcadas como
    /// visitadas. Default `"[]"` (set vacío). Misma clave que lee el
    /// logro `sieteMaravillas` en AchievementKind / ContentView /
    /// ProfileSheet — cualquier cambio aquí dispara la reactividad.
    @AppStorage("modernWondersVisited") private var visitedRaw: String = "[]"

    private let accent = BrandColor.accent

    /// Set decodificado de ids marcados. Lee siempre `visitedRaw` para
    /// reactividad — un cambio en @AppStorage re-renderiza el body.
    private var visited: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: Data(visitedRaw.utf8))) ?? []
    }

    private func setVisited(_ set: Set<String>) {
        if let data = try? JSONEncoder().encode(set),
           let str = String(data: data, encoding: .utf8) {
            visitedRaw = str
        }
    }

    private func toggle(_ id: String) {
        var current = visited
        if current.contains(id) { current.remove(id) }
        else { current.insert(id) }
        setVisited(current)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private var completed: Bool { visited.count >= 7 }

    /// Grid de 2 columnas — tarjetas cuadradas con esquinas redondeadas.
    /// Adapta su anchura al safe area, no fija pixel-perfect.
    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // ── Header: icono + título + subtítulo + progreso ────────
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color.purple.opacity(0.85), Color.pink.opacity(0.85)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 64, height: 64)
                            Image(systemName: "crown.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Text("Maravillas modernas")
                            .font(.custom("Satoshi-Bold", size: 22))
                        Text("Marca las que hayas visitado")
                            .font(.palatino(.subheadline))
                            .foregroundStyle(.secondary)
                        Text("\(visited.count) / 7")
                            .font(.custom("Satoshi-Bold", size: 14))
                            .foregroundStyle(completed ? Color.green : accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                (completed ? Color.green : accent).opacity(0.12),
                                in: Capsule()
                            )
                    }
                    .padding(.top, 16)

                    // ── Grid de 6 tarjetas (2 cols × 3 filas) + 7ª centrada ─
                    // El LazyVGrid rellena columna izquierda primero, así
                    // que metiendo solo las 6 primeras tenemos un grid
                    // simétrico. La 7ª (Taj Mahal) va aparte en un HStack
                    // con Spacers para quedar centrada y al mismo ancho
                    // visual que las celdas del grid (1/2 del ancho útil).
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(ModernWonder.all.prefix(6)) { wonder in
                            wonderCard(wonder: wonder, isMarked: visited.contains(wonder.id))
                                .onTapGesture { toggle(wonder.id) }
                        }
                    }
                    .padding(.horizontal, 20)

                    if let seventh = ModernWonder.all.last {
                        // GeometryReader para emular el mismo ancho que un
                        // cell del LazyVGrid (~ mitad del ancho útil tras
                        // descontar padding 20 + spacing 14 entre cols).
                        GeometryReader { geo in
                            let cellWidth = (geo.size.width - 20*2 - 14) / 2
                            HStack {
                                Spacer()
                                wonderCard(wonder: seventh, isMarked: visited.contains(seventh.id))
                                    .frame(width: cellWidth)
                                    .onTapGesture { toggle(seventh.id) }
                                Spacer()
                            }
                        }
                        // Altura aprox. de una tarjeta para que el
                        // GeometryReader reserve espacio (las tarjetas son
                        // ~120pt: emoji 44 + paddings + nombre + país).
                        .frame(height: 130)
                    }

                    // ── Banner de logro completado ───────────────────────────
                    // Sólo aparece tras marcar las 7. El logro 🏆
                    // `sieteMaravillas` se dispara via reactividad en
                    // ContentView, mostrando además la Live Activity
                    // celebratoria si el usuario es Pro.
                    if completed {
                        HStack(spacing: 10) {
                            Text("🏆").font(.system(size: 26))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("¡Logro desbloqueado!")
                                    .font(.custom("Satoshi-Bold", size: 14))
                                Text("Las 7 maravillas modernas")
                                    .font(.palatino(.caption))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(
                            LinearGradient(colors: [Color.yellow.opacity(0.18), Color.orange.opacity(0.18)],
                                           startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: Radius.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.card)
                                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                        )
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.bottom, 28)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body, weight: .bold))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .appColorScheme()
    }

    /// Tarjeta cuadrada con esquinas redondeadas: emoji grande arriba,
    /// nombre + país abajo, borde/relleno diferenciado cuando está marcada.
    /// La interacción de tap se aplica desde el padre (onTapGesture) para
    /// que toda la tarjeta sea hit area uniforme — no Button para evitar
    /// estilos de pulsación inconsistentes en grids.
    @ViewBuilder
    private func wonderCard(wonder: ModernWonder, isMarked: Bool) -> some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Text(wonder.emoji)
                    .font(.system(size: 44))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                if isMarked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.green, Color.white)
                        .background(Circle().fill(Color.white).frame(width: 18, height: 18))
                        .offset(x: 2, y: -2)
                }
            }
            VStack(spacing: 2) {
                Text(wonder.name)
                    .font(.custom("Satoshi-Bold", size: 14))
                    .lineLimit(1)
                Text(wonder.country)
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(isMarked ? accent.opacity(0.10) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isMarked ? accent.opacity(0.45) : Color.clear, lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .animation(.easeInOut(duration: 0.18), value: isMarked)
    }
}
