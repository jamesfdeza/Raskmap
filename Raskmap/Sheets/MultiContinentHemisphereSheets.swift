//
//  MultiContinentHemisphereSheets.swift
//  Raskmap
//
//  Sheets para resolver ambigüedades de países que se extienden por
//  más de un continente o hemisferio, más helpers visuales:
//  · MultiContinentEntry (data model) + multiContinentList (datos).
//  · MultiContinentSheet — picker continente para países tipo Turquía,
//    Rusia, Egipto, Kazajistán, etc.
//  · MultiHemisphereSheet — picker hemisferio (norte/sur/ambos).
//  · FavoriteAirportPickerSheet — selector de aeropuerto favorito.
//  · ColorPickerRow — fila con label + ColorPicker para tema visual.
//
//  Self-contained: usan @AppStorage para persistir, no acceden a
//  state privado de ContentView.
//
//  Extraído de ContentView.swift durante Fase D.
//

import SwiftUI

// MARK: - Países pluricontinentales
struct MultiContinentEntry: Identifiable {
    let id: String  // ISO code
    let flag: String
    let name: String
    let options: [(label: String, value: String)]
    let defaultValue: String
}

private let multiContinentEntries: [MultiContinentEntry] = [
    .init(id: "RUS", flag: "🇷🇺", name: "Rusia",
          options: [("Europa","europa"),("Asia","asia"),("Ambos","ambos")],
          defaultValue: "europa"),
    .init(id: "TUR", flag: "🇹🇷", name: "Turquía",
          options: [("Europa","europa"),("Asia","medioOriente"),("Ambos","ambos")],
          defaultValue: "medioOriente"),
    .init(id: "CYP", flag: "🇨🇾", name: "Chipre",
          options: [("Europa","europa"),("Asia","medioOriente"),("Ambos","ambos")],
          defaultValue: "europa"),
    .init(id: "AZE", flag: "🇦🇿", name: "Azerbaiyán",
          options: [("Europa","europa"),("Asia","asia"),("Ambos","ambos")],
          defaultValue: "asia"),
    .init(id: "GEO", flag: "🇬🇪", name: "Georgia",
          options: [("Europa","europa"),("Asia","asia"),("Ambos","ambos")],
          defaultValue: "asia"),
    .init(id: "KAZ", flag: "🇰🇿", name: "Kazajistán",
          options: [("Europa","europa"),("Asia","asia"),("Ambos","ambos")],
          defaultValue: "asia"),
    .init(id: "EGY", flag: "🇪🇬", name: "Egipto",
          options: [("África","africa"),("Asia","asia"),("Ambos","ambos")],
          defaultValue: "africa"),
]

struct MultiContinentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("multiContinentRaw") private var rawAssignments: String = "{}"
    @State private var showInfoToast: Bool = false

    private var assignments: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(rawAssignments.utf8))) ?? [:]
    }

    private func setAssignment(_ iso: String, _ value: String) {
        var dict = assignments
        dict[iso] = value
        if let data = try? JSONEncoder().encode(dict) {
            rawAssignments = String(data: data, encoding: .utf8) ?? "{}"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(multiContinentEntries) { entry in
                        HStack(spacing: 12) {
                            FlagLabel(emoji: entry.flag, size: 22)
                            Text(entry.name).font(.palatino(.body))
                            Spacer()
                            Picker("", selection: Binding(
                                get: { assignments[entry.id] ?? entry.defaultValue },
                                set: { setAssignment(entry.id, $0) }
                            )) {
                                ForEach(entry.options, id: \.value) { opt in
                                    Text(opt.label).tag(opt.value)
                                }
                            }
                            .pickerStyle(.menu)
                            .font(.palatino(.body))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        if entry.id != multiContinentEntries.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Países pluricontinentales")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { withAnimation { showInfoToast = true } } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
        }
        .overlay {
            if showInfoToast {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 16) {
                        Image(systemName: "info.circle.fill")
                            .font(.title2).foregroundStyle(.blue)
                        Text("Algunos países se extienden por dos continentes (como Rusia, Turquía o Egipto). Aquí decides en qué continente contarlos —o en ambos— para tus estadísticas por regiones y los logros de continentes completos.")
                            .font(.palatino(.body))
                            .multilineTextAlignment(.center)
                        Button { withAnimation { showInfoToast = false } } label: {
                            Text("Entendido")
                                .font(.palatino(.body, weight: .bold))
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(.white)
                        }.buttonStyle(.plain)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 32)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                .animation(.spring(duration: 0.3), value: showInfoToast)
            }
        }
        .presentationDetents([.large])
        .appColorScheme()
    }
}

// MARK: - Países en más de un hemisferio
struct MultiHemisphereSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("multiHemisphereRaw") private var rawAssignments: String = "{}"
    @State private var showInfoToast: Bool = false

    private var assignments: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(rawAssignments.utf8))) ?? [:]
    }

    private func setAssignment(_ iso: String, _ value: String) {
        var dict = assignments
        dict[iso] = value
        if let data = try? JSONEncoder().encode(dict) {
            rawAssignments = String(data: data, encoding: .utf8) ?? "{}"
        }
    }

    private let entries = AchievementKind.multiHemisphereData

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(entries, id: \.iso) { entry in
                        HStack(spacing: 12) {
                            FlagLabel(emoji: entry.flag, size: 22)
                            Text(entry.name).font(.palatino(.body))
                            Spacer()
                            Picker("", selection: Binding(
                                get: { assignments[entry.iso] ?? entry.defaultH },
                                set: { setAssignment(entry.iso, $0) }
                            )) {
                                Text("Norte").tag("norte")
                                Text("Sur").tag("sur")
                                Text("Ambos").tag("ambos")
                            }
                            .pickerStyle(.menu)
                            .font(.palatino(.body))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        if entry.iso != entries.last?.iso {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Países plurihemisferiales")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { withAnimation { showInfoToast = true } } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
        }
        .overlay {
            if showInfoToast {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 16) {
                        Image(systemName: "info.circle.fill")
                            .font(.title2).foregroundStyle(.blue)
                        Text("Algunos países se extienden por ambos hemisferios (norte y sur). Aquí decides en cuál contarlos —o en ambos— para tus estadísticas y el logro «Ambos hemisferios». Afecta también a los porcentajes de hemisferio en la pantalla de logros.")
                            .font(.palatino(.body))
                            .multilineTextAlignment(.center)
                        Button { withAnimation { showInfoToast = false } } label: {
                            Text("Entendido")
                                .font(.palatino(.body, weight: .bold))
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(.white)
                        }.buttonStyle(.plain)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 32)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                .animation(.spring(duration: 0.3), value: showInfoToast)
            }
        }
        .presentationDetents([.large])
        .appColorScheme()
    }
}

// MARK: - Selector de aeropuerto favorito
struct FavoriteAirportPickerSheet: View {
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var query: String = ""

    init(selected: Binding<String>) {
        self._selected = selected
        self._draft = State(initialValue: selected.wrappedValue)
    }

    private static let allAirports = RoutePickerSheet.allAirports

    private var filtered: [AirportData] {
        if query.isEmpty { return Self.allAirports }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return Self.allAirports.filter {
            $0.iata.range(of: query, options: opts) != nil ||
            $0.name.range(of: query, options: opts) != nil ||
            $0.city.range(of: query, options: opts) != nil ||
            $0.countryName.range(of: query, options: opts) != nil
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List(filtered, id: \.iata) { ap in
                    Button {
                        draft = draft == ap.iata ? "" : ap.iata
                    } label: {
                        HStack(spacing: 10) {
                            FlagLabel(emoji: ap.flagEmoji, size: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(ap.iata).font(.palatino(.subheadline, weight: .bold))
                                    Text(ap.name).font(.palatino(.body)).foregroundStyle(.primary)
                                }
                                Text(ap.city).font(.palatino(.caption)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if draft == ap.iata {
                                Image(systemName: "star.fill").foregroundStyle(.yellow)
                            }
                        }
                    }.buttonStyle(.plain)
                }
                .listStyle(.plain)
                .searchable(text: $query, prompt: "Buscar aeropuerto o IATA")

                Button {
                    selected = draft
                    dismiss()
                } label: {
                    Text("Aceptar")
                        .font(.palatino(.body, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(Color(.systemBackground))
            }
            .navigationTitle("Aeropuerto favorito")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .presentationDetents([.large])
        .appColorScheme()
    }
}

// MARK: - Fila de selector de color
struct ColorPickerRow: View {
    let label: String
    @Binding var color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.palatino(.body))
            Spacer()
            ColorPicker("", selection: $color, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 32, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
