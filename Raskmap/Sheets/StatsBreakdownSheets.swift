//
//  StatsBreakdownSheets.swift
//  Raskmap
//
//  Sheets drill-down de "TransportStatsSheet" para listar aeropuertos,
//  aerolíneas, asientos y posiciones más usadas. Cada uno recibe los datos
//  ya agregados (no consulta SwiftData) → 100% autocontenidos, sin acceso
//  a estado privado de ContentView.
//
//  Extraídos de ContentView.swift durante la modularización (Fase D).
//

import SwiftUI

// MARK: - Airport stats sheet
struct AirportStatsSheet: View {
    let airports: [(iata: String, name: String, country: String, count: Int)]
    let allFeatures: [CountryFeature]
    @Environment(\.dismiss) private var dismiss

    private func flagEmoji(_ a2: String) -> String {
        guard a2.count == 2 else { return "🌐" }
        return a2.uppercased().unicodeScalars.compactMap {
            Unicode.Scalar(127397 + $0.value).map { String($0) }
        }.joined()
    }

    var body: some View {
        NavigationStack {
            List(airports, id: \.iata) { ap in
                HStack(spacing: 10) {
                    FlagLabel(emoji: flagEmoji(ap.country), size: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ap.name).font(.palatino(.body)).foregroundStyle(.primary)
                        Text(ap.iata).font(.palatino(.caption, weight: .bold)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(ap.count)x")
                        .font(.palatino(.subheadline, weight: .bold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(.systemGray5), in: Capsule())
                }
                .padding(.vertical, 2)
            }
            .listStyle(.plain)
            .navigationTitle("✈️ Aeropuertos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .appColorScheme()
    }
}

// MARK: - Airline stats sheet
struct AirlineStatsSheet: View {
    let airlines: [(name: String, count: Int)]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(airlines, id: \.name) { al in
                HStack {
                    Text(al.name).font(.palatino(.body))
                    Spacer()
                    Text("\(al.count)x")
                        .font(.palatino(.subheadline, weight: .bold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(.systemGray5), in: Capsule())
                }
                .padding(.vertical, 2)
            }
            .listStyle(.plain)
            .navigationTitle("🛫 Aerolíneas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .appColorScheme()
    }
}

// MARK: - Seat stats sheet
struct SeatStatsSheet: View {
    let seats: [(seat: String, count: Int)]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if seats.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "seat.fill")
                            .font(.system(size: 40)).foregroundStyle(.secondary)
                        Text("Aún no hay asientos registrados")
                            .font(.palatino(.subheadline)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(seats, id: \.seat) { s in
                        HStack {
                            Text(s.seat).font(.palatino(.body, weight: .bold))
                            Spacer()
                            Text("\(s.count)x")
                                .font(.palatino(.subheadline, weight: .bold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color(.systemGray5), in: Capsule())
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("💺 Asientos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .appColorScheme()
    }
}

// MARK: - Seat position stats sheet
struct SeatPositionStatsSheet: View {
    let positions: [(position: String, count: Int)]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if positions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.rectangle")
                            .font(.system(size: 40)).foregroundStyle(.secondary)
                        Text("Aún no hay tipos de asiento registrados")
                            .font(.palatino(.subheadline)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(positions, id: \.position) { p in
                        HStack {
                            Text(p.position.capitalized).font(.palatino(.body))
                            Spacer()
                            Text("\(p.count)x")
                                .font(.palatino(.subheadline, weight: .bold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color(.systemGray5), in: Capsule())
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("🪟 Tipo asiento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .appColorScheme()
    }
}
