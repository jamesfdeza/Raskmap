//
//  LogrosSheet.swift
//  Raskmap
//
//  Sheet de logros (achievements) — grid de tarjetas con primeros viajes,
//  microestados, multi-continentes/hemisferios, regiones completas, etc.
//  Self-contained: recibe los trips y features necesarios como params.
//
//  Extraído de ContentView.swift durante Fase D.
//

import SwiftUI

// MARK: - Logros
struct LogrosSheet: View {
    let firstTrip: Trip?
    let firstLayoverTrip: Trip?
    let trip100: Trip?
    let firstMicroestadoTrip: Trip?
    let features: [CountryFeature]
    let pastTrips: [Trip]
    let visitedIsoCodes: Set<String>
    let isAchieved: (AchievementKind) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selectedKind: AchievementKind? = nil

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = Locale(identifier: "es")
        return f
    }()

    private func tripDateStr(_ trip: Trip) -> String {
        let start = Self.dateFmt.string(from: trip.dateFrom)
        if let end = trip.dateTo, end != trip.dateFrom {
            return "\(start) – \(Self.dateFmt.string(from: end))"
        }
        return start
    }

    private func lastTripDate(for kind: AchievementKind) -> Date {
        switch kind {
        case .firstTrip:         return firstTrip?.effectiveEndDate ?? .distantPast
        case .firstLayover:      return firstLayoverTrip?.effectiveEndDate ?? .distantPast
        case .trips100:          return trip100?.effectiveEndDate ?? .distantPast
        case .primerMicroestado: return firstMicroestadoTrip?.dateFrom ?? .distantPast
        case .allWorld, .ambosHemisferios, .todosLosContinentes:
            return pastTrips.map { $0.effectiveEndDate }.max() ?? .distantPast
        default:
            let isoCodes = kind.zoneIsoCodes.isEmpty ? kind.regionIsoCodes : kind.zoneIsoCodes
            return pastTrips.filter { isoCodes.contains($0.isoCode) }
                .map { $0.effectiveEndDate }.max() ?? .distantPast
        }
    }

    private func timeAgo(from date: Date) -> String {
        let now = Date()
        let days = Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0
        if days < 30 { return days == 1 ? "Hace 1 día" : "Hace \(days) días" }
        let months = Calendar.current.dateComponents([.month], from: date, to: now).month ?? 0
        if months < 12 { return months == 1 ? "Hace 1 mes" : "Hace \(months) meses" }
        let years = Calendar.current.dateComponents([.year], from: date, to: now).year ?? 0
        return years == 1 ? "Hace 1 año" : "Hace \(years) años"
    }

    @ViewBuilder
    private func tripToastContent(_ trip: Trip) -> some View {
        VStack(spacing: 4) {
            let flag = features.first(where: { $0.isoCode == trip.isoCode })?.flagEmoji ?? "🌐"
            let name = features.first(where: { $0.isoCode == trip.isoCode })?.localizedName ?? trip.isoCode
            HStack(spacing: 6) {
                FlagLabel(emoji: flag, size: 17)
                Text(name).font(.palatino(.headline))
            }
            if let title = trip.title {
                Text(title).font(.palatino(.subheadline)).foregroundStyle(.secondary)
            }
            Text(tripDateStr(trip)).font(.palatino(.caption)).foregroundStyle(.secondary)
            Text(timeAgo(from: trip.dateFrom))
                .font(.palatino(.caption, weight: .bold))
                .foregroundStyle(.blue)
        }
    }

    private func regionTripCount(_ kind: AchievementKind) -> Int {
        pastTrips.filter { kind.regionIsoCodes.contains($0.isoCode) }.count
    }
    private func regionVisitedCount(_ kind: AchievementKind) -> Int {
        visitedIsoCodes.intersection(kind.regionIsoCodes).count
    }
    private func visitedRegionDetail(_ kind: AchievementKind) -> some View {
        VStack(spacing: 4) {
            Text("\(regionVisitedCount(kind)) territorios en \(kind.regionName)")
                .font(.palatino(.subheadline, weight: .bold))
            Text("¡Lo conseguiste!")
                .font(.palatino(.caption))
                .foregroundStyle(.secondary)
        }
    }
    private func fiveTripsDetail(_ kind: AchievementKind) -> some View {
        VStack(spacing: 4) {
            Text("\(regionTripCount(kind)) viajes en \(kind.regionName)")
                .font(.palatino(.subheadline, weight: .bold))
            Text("¡Lo conseguiste!")
                .font(.palatino(.caption))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func achievementDetail(_ kind: AchievementKind) -> some View {
        switch kind {
        case .firstTrip:
            if let trip = firstTrip { tripToastContent(trip) }
        case .firstLayover:
            if let trip = firstLayoverTrip { tripToastContent(trip) }
        case .primerMicroestado:
            if let trip = firstMicroestadoTrip { tripToastContent(trip) }
        case .trips100:
            if let trip = trip100 { tripToastContent(trip) }
        case .allWorld:
            VStack(spacing: 4) {
                Text("¡Has visitado el mundo entero!")
                    .font(.palatino(.subheadline, weight: .bold))
                Text("Logro legendario")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
        case .visitedAntarctica:
            VStack(spacing: 4) {
                Text("¡Has pisado la Antártida!")
                    .font(.palatino(.subheadline, weight: .bold))
                Text("El continente más inhóspito del planeta")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
        case .visitedNortamerica:   visitedRegionDetail(kind)
        case .visitedCaribe:        visitedRegionDetail(kind)
        case .visitedSudamerica:    visitedRegionDetail(kind)
        case .visitedCentroamerica: visitedRegionDetail(kind)
        case .visitedAfrica:        visitedRegionDetail(kind)
        case .visitedEuropa:        visitedRegionDetail(kind)
        case .visitedMedioOriente:  visitedRegionDetail(kind)
        case .visitedOceania:       visitedRegionDetail(kind)
        case .visitedAsia:          visitedRegionDetail(kind)
        case .fiveEurope:           fiveTripsDetail(kind)
        case .fiveAsia:             fiveTripsDetail(kind)
        case .fiveAfrica:           fiveTripsDetail(kind)
        case .fiveMedioOriente:     fiveTripsDetail(kind)
        case .fiveOceania:          fiveTripsDetail(kind)
        case .fiveNortamerica:      fiveTripsDetail(kind)
        case .fiveCaribe:           fiveTripsDetail(kind)
        case .fiveSudamerica:       fiveTripsDetail(kind)
        case .fiveCentroamerica:    fiveTripsDetail(kind)
        case .europaCompleta, .asiaCompleta, .medioOrienteCompleto,
             .africaCompleta, .americaCompleta, .oceaniaCompleta:
            VStack(spacing: 4) {
                Text("¡Logro extraordinario!")
                    .font(.palatino(.subheadline, weight: .bold))
                Text("Has visitado todos los territorios de la zona")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
        case .todaLaUE:
            VStack(spacing: 4) {
                Text("¡Todos los países de la UE!")
                    .font(.palatino(.subheadline, weight: .bold))
                Text("Has visitado los 27 estados miembros")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
        case .todosEslavos:
            VStack(spacing: 4) {
                Text("¡Todos los pueblos eslavos!")
                    .font(.palatino(.subheadline, weight: .bold))
                Text("Has visitado los 13 países de habla eslava")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
        case .todosEscandinavos:
            VStack(spacing: 4) {
                Text("¡Escandinavia completa!")
                    .font(.palatino(.subheadline, weight: .bold))
                Text("Has visitado los 5 países nórdicos")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
        case .todosBalcanicos:
            VStack(spacing: 4) {
                Text("¡Los Balcanes completos!")
                    .font(.palatino(.subheadline, weight: .bold))
                Text("Has visitado todos los países balcánicos")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
        case .todosMicroestados:
            VStack(spacing: 4) {
                Text("¡Todos los microestados europeos!")
                    .font(.palatino(.subheadline, weight: .bold))
                Text("Andorra, Liechtenstein, Malta, Mónaco, San Marino y Vaticano")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
        case .ambosHemisferios:
            VStack(spacing: 4) {
                Text("¡Norte y sur del planeta!")
                    .font(.palatino(.subheadline, weight: .bold))
                Text("Has estado en ambos hemisferios")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
        case .todosLosContinentes:
            VStack(spacing: 4) {
                Text("¡Los 5 continentes!")
                    .font(.palatino(.subheadline, weight: .bold))
                Text("Europa, Asia, África, América y Oceanía")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
        case .pasaporteEuropa, .pasaporteAsia, .pasaporteMedioOriente,
             .pasaporteAfrica, .pasaporteAmerica, .pasaporteOceania:
            VStack(spacing: 4) {
                Text("¡Pasaporte completo!")
                    .font(.palatino(.subheadline, weight: .bold))
                Text("Has visitado todos los países de tu pasaporte")
                    .font(.palatino(.caption))
                    .foregroundStyle(.secondary)
            }
        // === FASE 2: nuevos logros ===
        // Detalle genérico por categoría — el título del propio logro ya dice
        // mucho, así que el modal sólo añade un subtítulo motivacional.
        case .trips5, .trips10, .trips25, .trips50:
            genericAchievementDetail(headline: kind.title, subtitle: "¡Sigue acumulando aventuras!")
        case .paises10, .paises25, .paises50, .paises75, .centurion:
            genericAchievementDetail(headline: kind.title, subtitle: "Conteo según tu modo activo (ONU / ONU+obs / Todos)")
        case .todosBalticos:
            genericAchievementDetail(headline: "¡Los 3 países bálticos!", subtitle: "Estonia, Letonia y Lituania")
        case .todosCaucaso:
            genericAchievementDetail(headline: "¡Todo el Cáucaso!", subtitle: "Armenia, Azerbaiyán y Georgia")
        case .todosAnglosfera:
            genericAchievementDetail(headline: "¡Toda la Anglosfera!", subtitle: "USA, UK, Canadá, Australia y Nueva Zelanda")
        case .todosNordicos:
            genericAchievementDetail(headline: "¡Los 5 países nórdicos!", subtitle: "Noruega, Suecia, Dinamarca, Finlandia e Islandia")
        case .todosG7:
            genericAchievementDetail(headline: "¡Todo el G7!", subtitle: "Las 7 economías más industrializadas")
        case .todosBRICS:
            genericAchievementDetail(headline: "¡Todos los BRICS!", subtitle: "Brasil, Rusia, India, China y Sudáfrica")
        case .todosASEAN:
            genericAchievementDetail(headline: "¡Todos los ASEAN!", subtitle: "Los 10 países del sudeste asiático")
        case .todosLusofonos:
            genericAchievementDetail(headline: "¡Todos los lusófonos!", subtitle: "Los 8 países donde se habla portugués")
        case .todosMediterraneo:
            genericAchievementDetail(headline: "¡Todo el Mediterráneo!", subtitle: "Los 22 países con costa mediterránea")
        case .todosHispanohablantes:
            genericAchievementDetail(headline: "¡Todos los hispanohablantes!", subtitle: "Los 21 países donde el español es oficial")
        case .primerVuelo:
            genericAchievementDetail(headline: "¡Tu primer vuelo!", subtitle: "Despegaron las alas del viaje")
        case .vuelos10, .vuelos50, .frequentFlyer:
            genericAchievementDetail(headline: kind.title, subtitle: "Tramos de avión acumulados")
        case .trotamundosTerrestre:
            genericAchievementDetail(headline: "¡Trotamundos terrestre!", subtitle: "10 viajes sin pisar un avión")
        case .daytrip:
            genericAchievementDetail(headline: "¡Daytrip!", subtitle: "Un viaje de ida y vuelta en el mismo día")
        case .sabbatical:
            genericAchievementDetail(headline: "¡Sabbatical!", subtitle: "Un viaje de más de 30 días")
        case .nomada:
            genericAchievementDetail(headline: "¡Nómada!", subtitle: "Un viaje de más de 90 días")
        case .cincoPaisesAno, .diezPaisesAno, .veintePaisesAno:
            genericAchievementDetail(headline: kind.title, subtitle: "Países distintos en un mismo año")
        case .anoCompletoViajero:
            genericAchievementDetail(headline: "¡Año completo viajero!", subtitle: "Has viajado en los 12 meses del calendario")
        case .viajeroNavideno:
            genericAchievementDetail(headline: "¡Viajero navideño!", subtitle: "Has viajado entre 20-dic y 6-ene")
        case .sieteMaravillas:
            genericAchievementDetail(headline: "¡Las 7 maravillas modernas!", subtitle: "Has visitado las 7: Gran Muralla, Petra, Cristo Redentor, Machu Picchu, Chichén Itzá, Coliseo y Taj Mahal")
        // Fase 3
        case .medioMundo:
            genericAchievementDetail(headline: "¡Medio mundo visitado!", subtitle: "Has cruzado el ecuador del mundo según tu modo de conteo")
        case .capitanBarco:
            genericAchievementDetail(headline: "¡Capitán de barco!", subtitle: "5 tramos en barco completados")
        case .mochileroAutentico:
            genericAchievementDetail(headline: "¡Mochilero auténtico!", subtitle: "5 tramos andando — los pies como motor")
        case .multimodal:
            genericAchievementDetail(headline: "¡Multimodal!", subtitle: "Un viaje con 3 o más medios de transporte distintos")
        case .cincoAerolineas, .veinticincoAerolineas:
            genericAchievementDetail(headline: kind.title, subtitle: "Aerolíneas distintas en tu historial")
        case .diezAeropuertos, .cincuentaAeropuertos:
            genericAchievementDetail(headline: kind.title, subtitle: "Aeropuertos distintos por los que has pasado")
        case .hubMaster:
            genericAchievementDetail(headline: "¡Hub Master!", subtitle: "Has pasado por 3 de los grandes hubs mundiales (DXB, LHR, JFK, HND, CDG, SIN, ATL, AMS)")
        case .maratonViajero:
            genericAchievementDetail(headline: "¡Maratón viajero!", subtitle: "3 países distintos en 30 días")
        case .dosContinentesUnViaje:
            genericAchievementDetail(headline: "¡2 continentes en 1 viaje!", subtitle: "Cruzaste dos macro-continentes en el mismo trip")
        case .cincoPaisesUnViaje:
            genericAchievementDetail(headline: "¡5 países en 1 viaje!", subtitle: "Cinco destinos en un solo trip")
        case .segundaCasa:
            genericAchievementDetail(headline: "¡Segunda casa!", subtitle: "Has visitado el mismo país 5 veces")
        case .querencia:
            genericAchievementDetail(headline: "¡Querencia!", subtitle: "Has visitado el mismo país 10 veces")
        }
    }

    /// Detalle genérico para logros Fase 2 — un par título + subtítulo
    /// centrados, mismo estilo visual que los específicos.
    @ViewBuilder
    private func genericAchievementDetail(headline: String, subtitle: String) -> some View {
        VStack(spacing: 4) {
            Text(headline)
                .font(.palatino(.subheadline, weight: .bold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.palatino(.caption))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                let achievedKinds = AchievementKind.allCases.filter { isAchieved($0) }.sorted { a, b in
                    if a.medalOrder != b.medalOrder { return a.medalOrder < b.medalOrder }
                    return lastTripDate(for: a) > lastTripDate(for: b)
                }
                let pendingKinds = AchievementKind.allCases.filter { !isAchieved($0) }
                    .sorted { $0.medalOrder < $1.medalOrder }
                ForEach(achievedKinds + pendingKinds, id: \.title) { kind in
                    let unlocked = isAchieved(kind)
                    Button {
                        if unlocked { selectedKind = kind }
                    } label: {
                        HStack(spacing: 12) {
                            Text(kind.medal)
                                .font(.title2)
                                .grayscale(unlocked ? 0 : 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title)
                                    .font(.palatino(.body))
                                    .foregroundStyle(unlocked ? .primary : .secondary)
                                if !unlocked {
                                    Text("Aún no conseguido")
                                        .font(.palatino(.caption))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            if unlocked {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .opacity(unlocked ? 1 : 0.5)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Logros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                        .font(.palatino(.body))
                }
            }
            .overlay {
                if let kind = selectedKind {
                    ZStack {
                        Color.black.opacity(0.45).ignoresSafeArea()
                        VStack(spacing: 14) {
                            Text(kind.medal).font(.system(size: 60))
                            Text(kind.title)
                                .font(.palatino(.title3, weight: .bold))
                                .multilineTextAlignment(.center)
                            achievementDetail(kind)
                            Button { selectedKind = nil } label: {
                                Text("Cerrar")
                                    .font(.palatino(.body, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.blue, in: RoundedRectangle(cornerRadius: Radius.cell))
                                    .foregroundStyle(.white)
                            }
                            .padding(.top, 4)
                        }
                        .padding(24)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: Radius.sheet))
                        .padding(.horizontal, 32)
                        .shadow(radius: 20)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedKind != nil)
        }
        .appColorScheme()
    }
}
