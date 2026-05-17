//
//  ContentView.swift
//  RaskmapWatch Watch App
//
//  Hero del Watch App: 3 tabs accesibles vía swipe horizontal.
//  Antes era un placeholder "Hello, world!" generado por Xcode.
//
//  Tab 1 — Próximo viaje: bandera + countdown + nombre.
//  Tab 2 — Países visitados: gauge circular según countingMode.
//  Tab 3 — Stats: número grande de países visitados + total.
//
//  Datos vía App Group (mismo UserDefaults suite que el widget iOS).
//  Sync iPhone → Watch es automático porque ambos leen del App Group;
//  el iPhone actualiza los valores en `WidgetDataWriter.swift`.
//

import SwiftUI

private let appGroupID = "group.com.jaime.raskmap"
private var sharedDefaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

struct ContentView: View {
    @State private var selectedTab: Int = 0
    /// Tick que fuerza re-evaluación de las child views cuando el user
    /// pulla a refrescar — incrementarlo dispara `.id(refreshTick)` y
    /// SwiftUI recrea las views, re-leyendo el App Group.
    @State private var refreshTick: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NextTripWatchView()
                .id("nextTrip-\(refreshTick)")
                .tag(0)

            VisitedGaugeWatchView()
                .id("gauge-\(refreshTick)")
                .tag(1)

            StatsWatchView()
                .id("stats-\(refreshTick)")
                .tag(2)

            VisitedFlagsWatchView()
                .id("flags-\(refreshTick)")
                .tag(3)
        }
        .tabViewStyle(.page)
        .onAppear { refreshTick += 1 }   // re-cargar al volver de bg
        .toolbar {
            // Botón refresh en la barra superior — Watch HIG-friendly.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    refreshTick += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Actualizar")
            }
        }
    }
}

// MARK: - Tab 1: Próximo viaje

private struct NextTripWatchView: View {
    @State private var flag: String = ""
    @State private var days: Int = -1
    @State private var name: String = ""

    var body: some View {
        VStack(spacing: 8) {
            if days >= 0 {
                Text(flag.isEmpty ? "🌐" : flag)
                    .font(.system(size: 50))
                VStack(spacing: 2) {
                    Text("\(days)")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(days == 1 ? "DÍA" : "DÍAS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                }
                Text(name.isEmpty ? "—" : name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Image(systemName: "airplane.departure")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("Sin próximo viaje")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        flag = sharedDefaults?.string(forKey: "widget_next_flag") ?? ""
        days = sharedDefaults?.object(forKey: "widget_next_days") as? Int ?? -1
        let title = sharedDefaults?.string(forKey: "widget_next_title") ?? ""
        let country = sharedDefaults?.string(forKey: "widget_next_name") ?? ""
        name = title.isEmpty ? country : title
    }
}

// MARK: - Tab 2: Gauge de visitados

private struct VisitedGaugeWatchView: View {
    @State private var visited: Int = 0
    @State private var total: Int = 193

    private var pct: Double {
        guard total > 0 else { return 0 }
        return min(1.0, max(0.0, Double(visited) / Double(total)))
    }

    var body: some View {
        VStack(spacing: 10) {
            Gauge(value: pct) {
                Text("Visitados")
            } currentValueLabel: {
                Text("\(visited)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            } minimumValueLabel: {
                Text("0").font(.caption2)
            } maximumValueLabel: {
                Text("\(total)").font(.caption2)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(.green)
            .scaleEffect(1.6)
            .frame(width: 100, height: 100)

            Text("\(Int(pct * 100))% del mundo")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: load)
    }

    private func load() {
        let mode = sharedDefaults?.string(forKey: "widget_counting_mode") ?? "un"
        visited = sharedDefaults?.integer(forKey: "widget_visited_\(mode)") ?? 0
        total = (mode == "un" ? 193 : (mode == "unPlus" ? 195 : 249))
    }
}

// MARK: - Tab 3: Stats numbers

private struct StatsWatchView: View {
    @State private var visited: Int = 0
    @State private var modeLabel: String = ""

    var body: some View {
        VStack(spacing: 4) {
            Text("\(visited)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
            Text(modeLabel.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            Text(visited == 1 ? "país visitado" : "países visitados")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: load)
    }

    private func load() {
        let mode = sharedDefaults?.string(forKey: "widget_counting_mode") ?? "un"
        visited = sharedDefaults?.integer(forKey: "widget_visited_\(mode)") ?? 0
        modeLabel = mode == "un" ? "ONU"
                  : mode == "unPlus" ? "ONU+OBS"
                  : "Todos"
    }
}

// MARK: - Tab 4: Banderas visitadas

/// Grid scrollable con las banderas de países visitados. Lee
/// `widget_all_flags` del App Group — string concatenado de emojis
/// (cada bandera ocupa 2 unicode scalars).
private struct VisitedFlagsWatchView: View {
    @State private var flags: [String] = []

    private let columns = [
        GridItem(.adaptive(minimum: 32), spacing: 6)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if flags.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "globe.americas")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("Sin países visitados")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 30)
                } else {
                    Text("\(flags.count) países")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Array(flags.enumerated()), id: \.offset) { _, flag in
                            Text(flag).font(.system(size: 22))
                        }
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        let raw = sharedDefaults?.string(forKey: "widget_top_visited_flags") ?? ""
        flags = Self.splitFlags(raw)
    }

    /// Split de un string de banderas emoji a array de strings (cada
    /// flag = 2 regional indicator scalars). Necesario porque
    /// `String.split(separator:)` no funciona con emojis compuestos.
    static func splitFlags(_ raw: String) -> [String] {
        var result: [String] = []
        var current = ""
        for ch in raw {
            current.append(ch)
            // Una bandera = 2 scalars regional indicator. Cada `Character`
            // de SwiftUI ya es un grapheme cluster completo (la bandera).
            if !current.isEmpty {
                result.append(current)
                current = ""
            }
        }
        return result.filter { !$0.isEmpty && $0 != "🌐" }
    }
}

#Preview {
    ContentView()
}
