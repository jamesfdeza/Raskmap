//
//  MapQuadrantsSheets.swift
//  Raskmap
//
//  Cuadrantes de mapa para "passport" personalizado:
//  · MapQuadrant (Codable) — modelo de cuadrante (4 países en grid).
//  · MapExportSheet — vista del passport completo + export como imagen.
//  · AddQuadrantSheet — crear nuevo cuadrante temático.
//  · QuadrantDetailSheet — editar cuadrante existente.
//
//  Extraído de ContentView.swift durante Fase D.
//

import SwiftUI
import UIKit
import MapKit
import CoreLocation

// MARK: - Cuadrante de mapa
struct MapQuadrant: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var candidateIsoCodes: [String]
    var position: Int

    init(id: UUID = UUID(), title: String, candidateIsoCodes: [String], position: Int = 0) {
        self.id = id; self.title = title; self.candidateIsoCodes = candidateIsoCodes; self.position = position
    }

    enum CodingKeys: String, CodingKey { case id, title, candidateIsoCodes, position }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        candidateIsoCodes = try c.decode([String].self, forKey: .candidateIsoCodes)
        position = (try? c.decodeIfPresent(Int.self, forKey: .position)) ?? -1
    }
}

// MARK: - Exportar mapa como imagen
struct MapExportSheet: View {
    let visitedCountries: [Country]
    let features: [CountryFeature]
    let countingModeRaw: String
    let visitedColor: Color
    let trips: [Trip]

    private var countingMode: CountingMode { CountingMode(rawValue: countingModeRaw) ?? .all }

    @AppStorage("multiContinentRaw") private var multiContinentRaw: String = "{}"
    private var multiContinentAssignments: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(multiContinentRaw.utf8))) ?? [:]
    }

    private var zoneCounter: String {
        let mode = countingMode
        if selectedZone.isWorld {
            let visited = visitedCountries.filter { mode.counts($0.isoCode) }.count
            return "\(visited)/\(mode.denominator)"
        }
        let codes = AchievementKind.adjustSet(selectedZone.isoCodes, forZone: selectedZone.zoneName, assignments: multiContinentAssignments)
        let visited = visitedCountries.filter { codes.contains($0.isoCode) && mode.counts($0.isoCode) }.count
        let total = codes.filter { mode.counts($0) }.count
        return "\(visited)/\(total)"
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @AppStorage("isRaskmapPro") private var isRaskmapPro: Bool = false
    @State private var showSubscriptionFromMap: Bool = false
    @State private var renderedImage: UIImage? = nil
    @State private var isRendering: Bool = true
    @State private var isSaving: Bool = false
    @State private var savedToast: Bool = false
    @State private var showFormatDialog: Bool = false
    @State private var selectedZone: ExportZone = .europa
    @State private var showAddQuadrant: Bool = false
    @State private var selectedQuadrant: MapQuadrant? = nil
    @State private var quadrantToEdit: MapQuadrant? = nil
    @State private var isEditingQuadrants: Bool = false
    @State private var quadrantToDelete: MapQuadrant? = nil
    @State private var showResetConfirm: Bool = false
    @AppStorage("mapQuadrantsData") private var mapQuadrantsData: String = "{}"
    @AppStorage("didInsertDefaultQuadrants") private var didInsertDefaultQuadrants: Bool = false

    private var allQuadrants: [String: [MapQuadrant]] {
        guard let data = mapQuadrantsData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: [MapQuadrant]].self, from: data)
        else { return [:] }
        return decoded
    }
    private var currentQuadrantSlots: [MapQuadrant?] {
        var list = allQuadrants[selectedZone.rawValue] ?? []
        if list.contains(where: { $0.position < 0 || $0.position >= 4 }) {
            for i in list.indices { list[i].position = i }
        }
        var slots: [MapQuadrant?] = [nil, nil, nil, nil]
        for q in list where q.position >= 0 && q.position < 4 {
            if slots[q.position] == nil { slots[q.position] = q }
        }
        return slots
    }
    private func saveQuadrant(_ q: MapQuadrant) {
        var all = allQuadrants
        let slots = currentQuadrantSlots
        let nextPos = slots.firstIndex(where: { $0 == nil }) ?? 0
        var newQ = q; newQ.position = nextPos
        var list = all[selectedZone.rawValue] ?? []
        list.append(newQ)
        all[selectedZone.rawValue] = list
        if let data = try? JSONEncoder().encode(all), let str = String(data: data, encoding: .utf8) {
            mapQuadrantsData = str
        }
    }
    private func saveAllQuadrants(_ list: [MapQuadrant]) {
        var all = allQuadrants
        all[selectedZone.rawValue] = list
        if let data = try? JSONEncoder().encode(all), let str = String(data: data, encoding: .utf8) {
            mapQuadrantsData = str
        }
    }
    private func updateQuadrant(_ q: MapQuadrant) {
        var all = allQuadrants
        var list = all[selectedZone.rawValue] ?? []
        if let idx = list.firstIndex(where: { $0.id == q.id }) {
            list[idx] = q
        }
        all[selectedZone.rawValue] = list
        if let data = try? JSONEncoder().encode(all), let str = String(data: data, encoding: .utf8) {
            mapQuadrantsData = str
        }
    }
    private func deleteQuadrant(_ q: MapQuadrant) {
        var all = allQuadrants
        var list = all[selectedZone.rawValue] ?? []
        list.removeAll { $0.id == q.id }
        all[selectedZone.rawValue] = list
        if let data = try? JSONEncoder().encode(all), let str = String(data: data, encoding: .utf8) {
            mapQuadrantsData = str
        }
    }
    private func insertDefaultsIfNeeded(zone: ExportZone, defaults: [(pos: Int, title: String, codes: [String])]) {
        var all = allQuadrants
        var list = all[zone.rawValue] ?? []
        // Normalize legacy positions (position == -1) before checking
        if list.contains(where: { $0.position < 0 || $0.position >= 4 }) {
            for i in list.indices { list[i].position = i }
        }
        let occupied = Set(list.filter { $0.position >= 0 && $0.position < 4 }.map { $0.position })
        var changed = false
        for d in defaults where !occupied.contains(d.pos) {
            list.append(MapQuadrant(title: d.title, candidateIsoCodes: d.codes, position: d.pos))
            changed = true
        }
        if changed {
            all[zone.rawValue] = list
            if let data = try? JSONEncoder().encode(all), let str = String(data: data, encoding: .utf8) {
                mapQuadrantsData = str
            }
        }
    }
    private func insertZoneDefaultsIfNeeded() {
        guard !didInsertDefaultQuadrants else { return }
        insertDefaultsIfNeeded(zone: .europa, defaults: [
            (0, "Unión Europea 🇪🇺", ["AUT","BEL","BGR","HRV","CYP","CZE","DNK","EST","FIN","FRA",
                                       "DEU","GRC","HUN","IRL","ITA","LVA","LTU","LUX","MLT","NLD",
                                       "POL","PRT","ROU","SVK","SVN","ESP","SWE"]),
            (1, "Microestados 🌐",   ["AND","LIE","MCO","SMR","VAT","MLT"]),
            (2, "Países nórdicos ❄️", ["NOR","SWE","DNK","FIN","ISL","FRO","ALD"])
        ])
        insertDefaultsIfNeeded(zone: .asia, defaults: [
            (0, "Asia Central 🏔️",  ["KAZ","KGZ","TJK","TKM","UZB","AFG"]),
            (1, "Asia Este 🏯",      ["CHN","JPN","PRK","KOR","MNG","TWN","HKG","MAC"]),
            (2, "Asia Sur 🌺",       ["IND","PAK","BGD","LKA","NPL","BTN","MDV","IOT"])
        ])
        insertDefaultsIfNeeded(zone: .africa, defaults: [
            (0, "Insulares 🏝️",  ["CPV","COM","MDG","MUS","STP","SYC","SHN"]),
            (1, "Safari 🦁",     ["KEN","TZA","ZAF","BWA","NAM","ZWE","UGA","RWA",
                                   "ETH","MOZ","ZMB","MWI","TCD","GAB","CMR"]),
            (2, "Sahel ☀️",      ["MRT","SEN","GMB","MLI","BFA","NER","NGA","TCD",
                                   "SDN","SSD","ERI","SAH"])
        ])
        insertDefaultsIfNeeded(zone: .america, defaults: [
            (0, "Norteamérica 🦅",    ["MEX","CAN","USA","GRL","SPM"]),
            (1, "Centroamérica 🌴",   ["BLZ","GTM","SLV","HND","NIC","CRI","PAN",
                                        "ATG","BHS","BRB","CUB","DMA","DOM","GRD",
                                        "HTI","JAM","KNA","LCA","VCT","TTO",
                                        "ABW","AIA","BMU","VGB","CYM","CUW",
                                        "MSR","PRI","BLM","MAF","SXM","TCA","VIR"]),
            (2, "Sudamérica 🌎",      ["ARG","BOL","BRA","CHL","COL","ECU","GUY",
                                        "PRY","PER","SUR","URY","VEN","FLK"])
        ])
        insertDefaultsIfNeeded(zone: .medioOriente, defaults: [
            (0, "Petroleros 🛢️",    ["SAU","ARE","IRQ","IRN","KWT","QAT","BHR","OMN"]),
            (1, "Históricos 🏛️",   ["IRQ","ISR","JOR","LBN","SYR","IRN","TUR",
                                      "PSE","YEM","OMN","SAU"]),
            (2, "F1 GP 🏎️",        ["BHR","SAU","ARE","QAT"])
        ])
        insertDefaultsIfNeeded(zone: .oceania, defaults: [
            (0, "Una isla 🏝️",        ["NRU","NIU","GUM","NFK"]),
            (1, "Commonwealth 👑",     ["AUS","NZL","PNG","FJI","SLB","VUT","TON",
                                         "WSM","KIR","NRU","TUV","COK","NIU","NFK","PCN"]),
            (2, "Comparten isla 🌊",   ["PNG","IDN"])
        ])
        didInsertDefaultQuadrants = true
    }
    private func resetToDefaults() {
        mapQuadrantsData = "{}"
        didInsertDefaultQuadrants = false
        insertZoneDefaultsIfNeeded()
    }
    @discardableResult
    private func swapQuadrant(idStr: String?, toIndex: Int) -> Bool {
        var list = allQuadrants[selectedZone.rawValue] ?? []
        if list.contains(where: { $0.position < 0 }) {
            for i in list.indices { list[i].position = i }
        }
        guard let idStr, let fromIdx = list.firstIndex(where: { $0.id.uuidString == idStr }) else { return false }
        let fromPos = list[fromIdx].position
        guard fromPos != toIndex else { return false }
        if let toIdx = list.firstIndex(where: { $0.position == toIndex }) {
            list[toIdx].position = fromPos
        }
        list[fromIdx].position = toIndex
        saveAllQuadrants(list)
        return true
    }

    enum ExportZone: String, CaseIterable, Identifiable {
        case europa = "Europa"; case asia = "Asia"
        case medioOriente = "M. Oriente"; case africa = "África"
        case america = "América"; case oceania = "Oceanía"
        case mundo = "Mundo"
        var id: String { rawValue }
        var isWorld: Bool { self == .mundo }

        var zoneName: String {
            switch self {
            case .europa: return "europa"
            case .asia: return "asia"
            case .medioOriente: return "medioOriente"
            case .africa: return "africa"
            case .america: return "america"
            case .oceania: return "oceania"
            case .mundo: return "mundo"
            }
        }

        var region: MKCoordinateRegion {
            switch self {
            case .europa:      return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 53,  longitude: 12),  span: MKCoordinateSpan(latitudeDelta: 52,  longitudeDelta: 90))
            case .asia:        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 32,  longitude: 95),  span: MKCoordinateSpan(latitudeDelta: 80,  longitudeDelta: 130))
            case .medioOriente:return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 27,  longitude: 43),  span: MKCoordinateSpan(latitudeDelta: 42,  longitudeDelta: 56))
            case .africa:      return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 1,   longitude: 17),  span: MKCoordinateSpan(latitudeDelta: 82,  longitudeDelta: 82))
            case .america:     return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 8,   longitude: -95), span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 148))
            case .oceania:     return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: -22, longitude: 148), span: MKCoordinateSpan(latitudeDelta: 72,  longitudeDelta: 100))
            case .mundo:       return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 20,  longitude: 10),  span: MKCoordinateSpan(latitudeDelta: 160, longitudeDelta: 360))
            }
        }

        var isoCodes: Set<String> {
            switch self {
            case .europa:
                return ["ALB","AND","AUT","BLR","BEL","BIH","BGR","HRV","CYP","CZE",
                        "DNK","EST","FIN","FRA","DEU","GRC","HUN","ISL","IRL","ITA",
                        "LVA","LIE","LTU","LUX","MLT","MDA","MCO","MNE","NLD","MKD",
                        "NOR","POL","PRT","ROU","RUS","SMR","SRB","SVK","SVN","ESP",
                        "SWE","CHE","UKR","GBR","VAT","KOS","ALD","FRO","GIB","GGY","IMN","JEY"]
            case .asia:
                return ["AFG","ARM","AZE","BGD","BTN","BRN","KHM","CHN","GEO","IND",
                        "IDN","JPN","KAZ","PRK","KOR","KGZ","LAO","MYS","MDV","MNG",
                        "MMR","NPL","PAK","PHL","SGP","LKA","TWN","TJK","THA","TLS",
                        "TKM","UZB","VNM","HKG","MAC","IOT"]
            case .medioOriente:
                return ["BHR","IRN","IRQ","ISR","JOR","KWT","LBN","OMN","PSE","PSX",
                        "QAT","SAU","SYR","TUR","ARE","YEM"]
            case .africa:
                return ["DZA","AGO","BEN","BWA","BFA","BDI","CPV","CMR","CAF","TCD",
                        "COM","COD","COG","CIV","DJI","EGY","GNQ","ERI","ETH","GAB",
                        "GMB","GHA","GIN","GNB","KEN","LSO","LBR","LBY","MDG","MWI",
                        "MLI","MRT","MUS","MAR","MOZ","NAM","NER","NGA","RWA","STP",
                        "SEN","SYC","SLE","SOM","ZAF","SSD","SDS","SDN","SWZ","TZA",
                        "TGO","TUN","UGA","ZMB","ZWE","SAH","SHN"]
            case .america:
                return ["ATG","ARG","BHS","BRB","BLZ","BOL","BRA","CAN","CHL","COL",
                        "CRI","CUB","DMA","DOM","ECU","SLV","GRD","GTM","GUY","HTI",
                        "HND","JAM","MEX","NIC","PAN","PRY","PER","KNA","LCA","VCT",
                        "SUR","TTO","USA","URY","VEN","ABW","AIA","BMU","VGB","CYM",
                        "CUW","FLK","GRL","MSR","PRI","BLM","MAF","SPM","SXM","TCA","VIR"]
            case .oceania:
                return ["AUS","FJI","KIR","MHL","FSM","NRU","NZL","PLW","PNG","WSM",
                        "SLB","TON","TUV","VUT","ASM","COK","PYF","GUM","NCL","NIU",
                        "NFK","MNP","PCN","WLF"]
            case .mundo:
                return []   // handled specially: all visited features
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
              VStack(spacing: 12) {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach([ExportZone.europa, .asia, .medioOriente]) { zone in
                            Button {
                                selectedZone = zone; renderedImage = nil; isRendering = true
                            } label: {
                                Text(zone.rawValue)
                                    .font(.palatino(.footnote, weight: selectedZone == zone ? .bold : .regular))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(selectedZone == zone ? Color.blue : Color(.systemGray5), in: RoundedRectangle(cornerRadius: Radius.cell))
                                    .foregroundStyle(selectedZone == zone ? .white : .primary)
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        ForEach([ExportZone.africa, .america, .oceania]) { zone in
                            Button {
                                selectedZone = zone; renderedImage = nil; isRendering = true
                            } label: {
                                Text(zone.rawValue)
                                    .font(.palatino(.footnote, weight: selectedZone == zone ? .bold : .regular))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(selectedZone == zone ? Color.blue : Color(.systemGray5), in: RoundedRectangle(cornerRadius: Radius.cell))
                                    .foregroundStyle(selectedZone == zone ? .white : .primary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)

                ZStack {
                    if let img = renderedImage {
                        Image(uiImage: img).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: Radius.cell)).shadow(radius: 6)
                    } else {
                        RoundedRectangle(cornerRadius: Radius.cell).fill(Color(.systemGray6))
                            .aspectRatio(selectedZone.isWorld ? CGFloat(780)/640 : 1, contentMode: .fit)
                            .overlay { VStack(spacing: 12) { ProgressView(); Text("Generando mapa…").font(.palatino(.caption)).foregroundStyle(.secondary) } }
                    }
                }
                .padding(.horizontal, 16)
                .onAppear { renderMap() }
                .onChange(of: selectedZone) { _, _ in renderMap() }

                Spacer()

                // ── Cuadrantes (grid fijo 2×2) — oculto para mundo ──
                if !selectedZone.isWorld {
                    quadrantGrid()
                        .padding(.horizontal, 16)
                }

                Spacer()

                Button {
                    guard renderedImage != nil else { return }
                    if selectedZone.isWorld {
                        saveImage(size: CGSize(width: 1560, height: 1280))
                    } else {
                        showFormatDialog = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isSaving { ProgressView().tint(.white) } else { Image(systemName: "square.and.arrow.down") }
                        Text(savedToast ? "¡Guardada!" : "Guardar en galería")
                    }
                    .font(.palatino(.body, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(savedToast ? Color.green : Color.blue, in: RoundedRectangle(cornerRadius: Radius.cell))
                    .foregroundStyle(.white)
                }
                .padding(.horizontal, 24).padding(.bottom, 24).disabled(renderedImage == nil || isSaving)
                .animation(.easeInOut(duration: 0.2), value: savedToast)
                .confirmationDialog("Formato de imagen", isPresented: $showFormatDialog) {
                    Button("1:1 (cuadrado)") { saveImage(size: CGSize(width: 900, height: 900)) }
                    Button("9:16 (vertical)") { saveImage(size: CGSize(width: 900, height: 1600)) }
                    Button("Cancelar", role: .cancel) {}
                }
              }
              .blur(radius: isRaskmapPro ? 0 : 12)
              .allowsHitTesting(isRaskmapPro)
              if !isRaskmapPro {
                  VStack(spacing: 16) {
                      Image(systemName: "lock.fill")
                          .font(.system(size: 44))
                          .foregroundStyle(.purple)
                      Text("Función Pro")
                          .font(.palatino(.title3, weight: .bold))
                          .foregroundStyle(.purple)
                      Button { showSubscriptionFromMap = true } label: {
                          Text("Desbloquear Pro")
                              .font(.palatino(.body, weight: .bold))
                              .foregroundStyle(.white)
                              .padding(.horizontal, 28)
                              .padding(.vertical, 12)
                              .background(Color.purple, in: Capsule())
                      }
                      .buttonStyle(.plain)
                  }
              }
            }
            .padding(.top, 8)
            .navigationTitle("Mi mapa").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button { showResetConfirm = true } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .accessibilityLabel("Restablecer cuadrantes")
                        Button { isEditingQuadrants.toggle() } label: {
                            Image(systemName: isEditingQuadrants ? "checkmark" : "pencil")
                        }
                        .accessibilityLabel(isEditingQuadrants ? "Terminar edición" : "Editar cuadrantes")
                    }
                }
            }
            .sheet(isPresented: $showSubscriptionFromMap) { SubscriptionSheet() }
            .sheet(isPresented: $showAddQuadrant) {
                AddQuadrantSheet(features: features, zone: selectedZone, countingModeRaw: countingModeRaw) { q in saveQuadrant(q) }
            }
            .sheet(item: $quadrantToEdit) { q in
                AddQuadrantSheet(features: features, zone: selectedZone, countingModeRaw: countingModeRaw, initialQuadrant: q) { updated in
                    updateQuadrant(updated)
                }
            }
            .sheet(item: $selectedQuadrant) { q in
                let visitedSet = Set(visitedCountries.map { $0.isoCode })
                QuadrantDetailSheet(quadrant: q, features: features, visitedIsoCodes: visitedSet, countingModeRaw: countingModeRaw, zoneName: selectedZone.zoneName, multiContinentAssignments: multiContinentAssignments)
            }
            .alert("¿Eliminar lista?", isPresented: Binding(
                get: { quadrantToDelete != nil },
                set: { if !$0 { quadrantToDelete = nil } }
            )) {
                Button("Eliminar", role: .destructive) {
                    if let q = quadrantToDelete { deleteQuadrant(q) }
                    quadrantToDelete = nil
                    isEditingQuadrants = false
                }
                Button("Cancelar", role: .cancel) { quadrantToDelete = nil }
            } message: {
                if let q = quadrantToDelete { Text("Se eliminará «\(q.title)».") }
            }
            .alert("Restablecer cuadrantes", isPresented: $showResetConfirm) {
                Button("Restablecer", role: .destructive) { resetToDefaults() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se borrarán todos los cuadrantes actuales y se restaurarán los predeterminados.")
            }
        }
        .appColorScheme()
        .onAppear { insertZoneDefaultsIfNeeded() }
    }

    @ViewBuilder
    private func quadrantSlot(index: Int) -> some View {
        let slots = currentQuadrantSlots
        let visitedSet = Set(visitedCountries.map { $0.isoCode })
        let currentMode = CountingMode(rawValue: countingModeRaw) ?? .all
        if let q = slots[index] {
            let zoneFiltered = AchievementKind.filterCandidatesForZone(
                q.candidateIsoCodes,
                zoneName: selectedZone.zoneName,
                assignments: multiContinentAssignments,
                quadrantTitle: q.title
            )
            let zoneFilteredSet = Set(zoneFiltered)
            let activeCodes = q.candidateIsoCodes.filter { zoneFilteredSet.contains($0) && currentMode.counts($0) }
            let cnt = activeCodes.filter { visitedSet.contains($0) }.count
            ZStack(alignment: .topTrailing) {
                Button { if !isEditingQuadrants { selectedQuadrant = q } } label: {
                    VStack(spacing: 4) {
                        FlagAwareText(text: q.title,
                                      font: .palatino(.caption, weight: .bold),
                                      size: 14)
                            .lineLimit(1)
                        Text("\(cnt)/\(activeCodes.count)")
                            .font(.palatino(.title3, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(.primary)
                    .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: Radius.cell))
                }
                .buttonStyle(.plain)
                if isEditingQuadrants {
                    HStack(spacing: 4) {
                        Button { quadrantToEdit = q } label: {
                            Image(systemName: "pencil.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.title3)
                                .background(Circle().fill(Color(.systemBackground)))
                        }
                        .accessibilityLabel("Editar cuadrante \(q.title)")
                        Button { quadrantToDelete = q } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                                .font(.title3)
                                .background(Circle().fill(Color(.systemBackground)))
                        }
                        .accessibilityLabel("Eliminar cuadrante \(q.title)")
                    }
                    .offset(x: 6, y: -6)
                }
            }
            .draggable(q.id.uuidString)
            .dropDestination(for: String.self) { items, _ in swapQuadrant(idStr: items.first, toIndex: index) }
        } else {
            Button { showAddQuadrant = true } label: {
                Image(systemName: "plus")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
            }
            .buttonStyle(.plain)
            .dropDestination(for: String.self) { items, _ in swapQuadrant(idStr: items.first, toIndex: index) }
        }
    }

    @ViewBuilder
    private func quadrantGrid() -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                quadrantSlot(index: 0)
                quadrantSlot(index: 1)
            }
            HStack(spacing: 8) {
                quadrantSlot(index: 2)
                quadrantSlot(index: 3)
            }
        }
    }

    private func saveImage(size: CGSize) {
        isSaving = true
        let isWorld = selectedZone.isWorld
        let snapSize = isWorld ? CGSize(width: 624, height: 512) : size
        let options = MKMapSnapshotter.Options()
        if isWorld {
            options.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 15, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)
            )
        } else {
            options.region = selectedZone.region
        }
        options.size = snapSize
        options.scale = isWorld ? 1 : displayScale
        options.mapType = .mutedStandard
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false
        let style: UIUserInterfaceStyle = ColorThemeManager.shared.isDarkMode ? .dark : .light
        options.traitCollection = UITraitCollection(userInterfaceStyle: style)

        let visitedIsoCodes = Set(visitedCountries.map { $0.isoCode })
        let visitedFeatures: [CountryFeature]
        if isWorld {
            visitedFeatures = features.filter { visitedIsoCodes.contains($0.isoCode) }
        } else {
            let assignments = multiContinentAssignments
            let zoneIsoCodes = Set(AchievementKind.adjustSet(selectedZone.isoCodes, forZone: selectedZone.zoneName, assignments: assignments))
            visitedFeatures = features.filter { visitedIsoCodes.contains($0.isoCode) && zoneIsoCodes.contains($0.isoCode) }
        }
        let fillUIColor = UIColor(visitedColor)
        let counterStr = zoneCounter

        MKMapSnapshotter(options: options).start { snapshot, _ in
            guard let snapshot else { DispatchQueue.main.async { isSaving = false }; return }
            let ws: CGFloat = isWorld ? size.width / snapSize.width : 1.0
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { _ in
                snapshot.image.draw(in: CGRect(origin: .zero, size: size))
                for feature in visitedFeatures {
                    for polygon in feature.polygons {
                        guard polygon.pointCount >= 3 else { continue }
                        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: polygon.pointCount)
                        polygon.getCoordinates(&coords, range: NSRange(location: 0, length: polygon.pointCount))
                        let pts = coords.map { CGPoint(x: snapshot.point(for: $0).x * ws, y: snapshot.point(for: $0).y * ws) }
                        let m: CGFloat = 50
                        guard pts.contains(where: { $0.x > -m && $0.x < size.width + m && $0.y > -m && $0.y < size.height + m }) else { continue }
                        let path = UIBezierPath()
                        path.move(to: pts[0]); pts.dropFirst().forEach { path.addLine(to: $0) }; path.close()
                        path.usesEvenOddFillRule = true
                        polygon.interiorPolygons?.forEach { hole in
                            guard hole.pointCount >= 3 else { return }
                            var hc = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: hole.pointCount)
                            hole.getCoordinates(&hc, range: NSRange(location: 0, length: hole.pointCount))
                            let hp = UIBezierPath()
                            let hpts = hc.map { CGPoint(x: snapshot.point(for: $0).x * ws, y: snapshot.point(for: $0).y * ws) }
                            hp.move(to: hpts[0]); hpts.dropFirst().forEach { hp.addLine(to: $0) }; hp.close()
                            path.append(hp)
                        }
                        fillUIColor.setFill(); path.fill()
                    }
                }
                let brandText = "Raskmap" as NSString
                let brandAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 13), .foregroundColor: UIColor.white.withAlphaComponent(0.85)]
                let brandSize = brandText.size(withAttributes: brandAttrs)
                let text = counterStr as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 20), .foregroundColor: UIColor.white]
                let ts = text.size(withAttributes: attrs)
                let pad: CGFloat = 10
                let bgW = max(ts.width, brandSize.width) + pad * 2
                let bgH = brandSize.height + 2 + ts.height + pad * 2
                let bgRect = CGRect(x: (size.width - bgW) / 2, y: size.height - bgH - 14, width: bgW, height: bgH)
                UIColor.black.withAlphaComponent(0.55).setFill()
                UIBezierPath(roundedRect: bgRect, cornerRadius: Radius.chip).fill()
                brandText.draw(at: CGPoint(x: (size.width - brandSize.width) / 2, y: bgRect.minY + pad), withAttributes: brandAttrs)
                text.draw(at: CGPoint(x: (size.width - ts.width) / 2, y: bgRect.minY + pad + brandSize.height + 2), withAttributes: attrs)
            }
            DispatchQueue.main.async {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                isSaving = false; savedToast = true
                Task { @MainActor in try? await Task.sleep(for: .seconds(1.5)); savedToast = false }
            }
        }
    }

    private func renderMap() {
        isRendering = true
        // Para mundo: snapshot pequeño (512×512, scale=1) fuerza zoom-1 = 4 tiles = mundo completo.
        // Luego escalamos manualmente al displaySize deseado.
        let isWorld = selectedZone.isWorld
        // snapSize coincide con el ratio Mercator natural de la región mundo (-75°..+85° lat, 360° lon)
        // ratio = 2π / (y(85°)-y(-75°)) = 6.283/5.159 ≈ 1.218  →  624×512
        let snapSize    = isWorld ? CGSize(width: 624, height: 512) : CGSize(width: 800, height: 800)
        let displaySize = isWorld ? CGSize(width: 780, height: 640) : CGSize(width: 800, height: 800)

        let options = MKMapSnapshotter.Options()
        if isWorld {
            options.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 15, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)
            )
        } else {
            options.region = selectedZone.region
        }
        options.size  = snapSize
        options.scale = isWorld ? 1 : displayScale
        options.mapType = .mutedStandard
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false
        let style: UIUserInterfaceStyle = ColorThemeManager.shared.isDarkMode ? .dark : .light
        options.traitCollection = UITraitCollection(userInterfaceStyle: style)

        let visitedIsoCodes = Set(visitedCountries.map { $0.isoCode })
        let visitedFeatures: [CountryFeature]
        if isWorld {
            visitedFeatures = features.filter { visitedIsoCodes.contains($0.isoCode) }
        } else {
            let assignments = multiContinentAssignments
            let zoneIsoCodes = Set(AchievementKind.adjustSet(selectedZone.isoCodes, forZone: selectedZone.zoneName, assignments: assignments))
            visitedFeatures = features.filter { visitedIsoCodes.contains($0.isoCode) && zoneIsoCodes.contains($0.isoCode) }
        }
        let fillUIColor = UIColor(visitedColor)
        let counterStr = zoneCounter

        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { snapshot, _ in
            guard let snapshot else { return }
            // Factor de escala del espacio snapshot → espacio displaySize
            let ws: CGFloat = isWorld ? displaySize.width / snapSize.width : 1.0
            let renderer = UIGraphicsImageRenderer(size: displaySize)
            let image = renderer.image { _ in
                // 1. Mapa base escalado al displaySize
                snapshot.image.draw(in: CGRect(origin: .zero, size: displaySize))

                // 2. Polígonos escalados
                for feature in visitedFeatures {
                    for polygon in feature.polygons {
                        guard polygon.pointCount >= 3 else { continue }
                        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: polygon.pointCount)
                        polygon.getCoordinates(&coords, range: NSRange(location: 0, length: polygon.pointCount))
                        let pts = coords.map { CGPoint(x: snapshot.point(for: $0).x * ws, y: snapshot.point(for: $0).y * ws) }
                        let m: CGFloat = 50
                        guard pts.contains(where: { $0.x > -m && $0.x < displaySize.width + m && $0.y > -m && $0.y < displaySize.height + m }) else { continue }

                        let path = UIBezierPath()
                        path.move(to: pts[0])
                        pts.dropFirst().forEach { path.addLine(to: $0) }
                        path.close()
                        path.usesEvenOddFillRule = true

                        polygon.interiorPolygons?.forEach { hole in
                            guard hole.pointCount >= 3 else { return }
                            var hc = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: hole.pointCount)
                            hole.getCoordinates(&hc, range: NSRange(location: 0, length: hole.pointCount))
                            let hp = UIBezierPath()
                            let hpts = hc.map { CGPoint(x: snapshot.point(for: $0).x * ws, y: snapshot.point(for: $0).y * ws) }
                            hp.move(to: hpts[0]); hpts.dropFirst().forEach { hp.addLine(to: $0) }; hp.close()
                            path.append(hp)
                        }

                        fillUIColor.setFill()
                        path.fill()
                    }
                }

                // 3. Marca de agua
                let brandText = "Raskmap" as NSString
                let brandAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 13),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.85)
                ]
                let brandSize = brandText.size(withAttributes: brandAttrs)
                let text = counterStr as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 20),
                    .foregroundColor: UIColor.white
                ]
                let ts = text.size(withAttributes: attrs)
                let pad: CGFloat = 10
                let bgW = max(ts.width, brandSize.width) + pad * 2
                let bgH = brandSize.height + 2 + ts.height + pad * 2
                let bgRect = CGRect(x: (displaySize.width - bgW) / 2, y: displaySize.height - bgH - 14, width: bgW, height: bgH)
                UIColor.black.withAlphaComponent(0.55).setFill()
                UIBezierPath(roundedRect: bgRect, cornerRadius: Radius.chip).fill()
                brandText.draw(at: CGPoint(x: (displaySize.width - brandSize.width) / 2, y: bgRect.minY + pad), withAttributes: brandAttrs)
                text.draw(at: CGPoint(x: (displaySize.width - ts.width) / 2, y: bgRect.minY + pad + brandSize.height + 2), withAttributes: attrs)
            }
            DispatchQueue.main.async { renderedImage = image; isRendering = false }
        }
    }
}

// MARK: - Añadir / editar cuadrante
struct AddQuadrantSheet: View {
    let features: [CountryFeature]
    let zone: MapExportSheet.ExportZone
    let countingModeRaw: String
    var initialQuadrant: MapQuadrant? = nil
    let onSave: (MapQuadrant) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var selectedIsoCodes: Set<String> = []
    @State private var searchText: String = ""

    private var countingMode: CountingMode { CountingMode(rawValue: countingModeRaw) ?? .all }

    private func saveAndDismiss() {
        guard !title.isEmpty, !selectedIsoCodes.isEmpty else { return }
        if let existing = initialQuadrant {
            onSave(MapQuadrant(id: existing.id, title: title, candidateIsoCodes: Array(selectedIsoCodes), position: existing.position))
        } else {
            onSave(MapQuadrant(title: title, candidateIsoCodes: Array(selectedIsoCodes)))
        }
        dismiss()
    }

    /// ISOs de países pluricontinentales — siempre seleccionables en cualquier
    /// zona (Europa/Asia/MedioOriente/etc.) independientemente de la asignación
    /// en Ajustes, para que un país como Chipre pueda meterse en cuadrantes
    /// tanto europeos como asiáticos sin restricciones.
    private static let pluriIsoCodes: Set<String> = ["RUS", "TUR", "CYP", "AZE", "GEO", "KAZ", "EGY"]

    private var flaggedFeatures: [CountryFeature] {
        features.filter {
            // En modo `all` (todos los territorios) mostramos también los que no
            // tienen bandera para que sean elegibles. En el resto de modos
            // (un/unPlus) seguimos exigiendo bandera.
            (countingMode == .all || $0.flagEmoji != nil) &&
            (zone.isoCodes.contains($0.isoCode) || Self.pluriIsoCodes.contains($0.isoCode)) &&
            countingMode.counts($0.isoCode)
        }.sorted { $0.localizedName.localizedCompare($1.localizedName) == .orderedAscending }
    }
    private var filtered: [CountryFeature] {
        guard !searchText.isEmpty else { return flaggedFeatures }
        let q = searchText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return flaggedFeatures.filter {
            $0.localizedName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Título de la lista", text: $title)
                        .font(.palatino(.body))
                }
                Section("Candidatos (\(selectedIsoCodes.count))") {
                    ForEach(filtered, id: \.isoCode) { feature in
                        Button {
                            if selectedIsoCodes.contains(feature.isoCode) {
                                selectedIsoCodes.remove(feature.isoCode)
                            } else {
                                selectedIsoCodes.insert(feature.isoCode)
                            }
                        } label: {
                            HStack {
                                FlagLabel(emoji: feature.flagEmoji ?? "🌐", size: 17)
                                Text(feature.localizedName)
                                    .font(.palatino(.body))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedIsoCodes.contains(feature.isoCode) {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .onAppear {
                if let q = initialQuadrant {
                    title = q.title
                    selectedIsoCodes = Set(q.candidateIsoCodes)
                }
            }
            .searchable(text: $searchText, prompt: "Buscar territorio…")
            .navigationTitle(initialQuadrant == nil ? "Nueva lista" : "Editar lista")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }.font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Guardar") { saveAndDismiss() }
                        .disabled(title.isEmpty || selectedIsoCodes.isEmpty)
                        .font(.palatino(.body, weight: .bold))
                }
            }
        }
    }
}

// MARK: - Detalle de cuadrante
struct QuadrantDetailSheet: View {
    let quadrant: MapQuadrant
    let features: [CountryFeature]
    let visitedIsoCodes: Set<String>
    let countingModeRaw: String
    var zoneName: String? = nil
    var multiContinentAssignments: [String: String] = [:]

    @Environment(\.dismiss) private var dismiss

    private var countingMode: CountingMode { CountingMode(rawValue: countingModeRaw) ?? .all }

    /// Candidatos filtrados por modo de conteo Y por asignaciones pluricontinentales:
    /// si un país pluri (ej. Chipre) está asignado a otra zona en Ajustes, no aparece
    /// en cuadrantes de zonas distintas. Excepción: cuadrantes UE no se filtran.
    private var activeCandidates: [String] {
        let zoneFiltered: [String]
        if let zoneName {
            zoneFiltered = AchievementKind.filterCandidatesForZone(
                quadrant.candidateIsoCodes,
                zoneName: zoneName,
                assignments: multiContinentAssignments,
                quadrantTitle: quadrant.title
            )
        } else {
            zoneFiltered = quadrant.candidateIsoCodes
        }
        let allowed = Set(zoneFiltered)
        return quadrant.candidateIsoCodes.filter { allowed.contains($0) && countingMode.counts($0) }
    }

    private var visited: [CountryFeature] {
        activeCandidates
            .filter { visitedIsoCodes.contains($0) }
            .compactMap { iso in features.first(where: { $0.isoCode == iso }) }
            .sorted { $0.localizedName.localizedCompare($1.localizedName) == .orderedAscending }
    }
    private var notVisited: [CountryFeature] {
        activeCandidates
            .filter { !visitedIsoCodes.contains($0) }
            .compactMap { iso in features.first(where: { $0.isoCode == iso }) }
            .sorted { $0.localizedName.localizedCompare($1.localizedName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if !visited.isEmpty {
                    Section {
                        ForEach(visited, id: \.isoCode) { feature in
                            HStack(spacing: 12) {
                                FlagLabel(emoji: feature.flagEmoji ?? "", size: 22)
                                Text(feature.localizedName).font(.palatino(.body))
                            }
                        }
                    }
                }
                if !notVisited.isEmpty {
                    Section {
                        ForEach(notVisited, id: \.isoCode) { feature in
                            HStack(spacing: 12) {
                                FlagLabel(emoji: feature.flagEmoji ?? "", size: 22).opacity(0.4)
                                Text(feature.localizedName)
                                    .font(.palatino(.body))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            // Título: `navigationTitle("...")` solo acepta String → cualquier
            // bandera emoji embebida saldría como emoji nativo del sistema, NO
            // como Twemoji. Para que el twemoji se renderice también en el
            // header del sheet, usamos `.principal` con `FlagAwareText`.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    FlagAwareText(
                        text: "\(quadrant.title) · \(visited.count)/\(activeCandidates.count)",
                        font: .custom("Satoshi-Bold", size: 17),
                        size: 16
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
    }
}
