//
//  SubjectiveSheets.swift
//  Raskmap
//
//  Sheets de categorías subjetivas (medallero personal) y picker de
//  banderas por categoría:
//  · SubjectiveCategory (enum) — todas las categorías disponibles.
//  · SubjectiveCategoriesSheet — vista principal con asignaciones.
//  · SubjectiveFlagPickerSheet — selector multi-bandera por categoría.
//  · FlagAlphabetSheet — buscador alfabético de banderas (helper).
//
//  Self-contained con @AppStorage.
//
//  Extraído de ContentView.swift durante Fase D.
//

import SwiftUI

// MARK: - Categorías subjetivas (medallero)

enum SubjectiveCategory: String, CaseIterable, Identifiable {
    case overrated, underrated, cleanest, dirtiest, safestNight, mostDangerous,
         friendliestLocals, rudestTourists, bestStreetFood, cultureShock,
         hardestLanguage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overrated:          return "Sobrevalorados"
        case .underrated:         return "Infravalorados"
        case .dirtiest:           return "Más sucios"
        case .safestNight:        return "Más seguros de noche"
        case .mostDangerous:      return "Más peligrosos"
        case .friendliestLocals:  return "Locales más amables"
        case .rudestTourists:     return "Locales más maleducados"
        case .bestStreetFood:     return "Mejor comida callejera"
        case .cultureShock:       return "Mayor choque cultural"
        case .hardestLanguage:    return "Idioma más difícil"
        case .cleanest:           return "Más limpios"
        }
    }

    /// Emoji decorativo para la fila — aporta color sin depender de SF Symbols.
    var emoji: String {
        switch self {
        case .overrated:          return "📣"
        case .underrated:         return "💎"
        case .dirtiest:           return "🗑️"
        case .safestNight:        return "🌙"
        case .mostDangerous:      return "⚠️"
        case .friendliestLocals:  return "🤗"
        case .rudestTourists:     return "🙄"
        case .bestStreetFood:     return "🌮"
        case .cultureShock:       return "🌀"
        case .hardestLanguage:    return "🗣️"
        case .cleanest:           return "✨"
        }
    }
}

struct SubjectiveCategoriesSheet: View {
    let allFeatures: [CountryFeature]
    let visitedIsoCodes: Set<String>

    @Environment(\.dismiss) private var dismiss
    @AppStorage("subjectiveCategoriesTable") private var tableRaw: String = "{}"
    @AppStorage("subjectiveCategoriesOrder") private var orderRaw: String = "[]"
    @State private var editing: EditTarget? = nil
    @State private var isReordering: Bool = false

    struct EditTarget: Identifiable {
        let category: SubjectiveCategory
        let medal: ProfileSheet.MedalSlot
        var id: String { category.rawValue + "_" + medal.rawValue }
    }

    private func decodeOrder() -> [SubjectiveCategory] {
        let stored: [String]
        if let data = orderRaw.data(using: .utf8),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            stored = arr
        } else {
            stored = []
        }
        var seen = Set<String>()
        var ordered: [SubjectiveCategory] = []
        for raw in stored {
            if let cat = SubjectiveCategory(rawValue: raw), seen.insert(raw).inserted {
                ordered.append(cat)
            }
        }
        for cat in SubjectiveCategory.allCases where seen.insert(cat.rawValue).inserted {
            ordered.append(cat)
        }
        return ordered
    }
    private func saveOrder(_ cats: [SubjectiveCategory]) {
        let arr = cats.map(\.rawValue)
        let data = (try? JSONEncoder().encode(arr)) ?? Data()
        orderRaw = String(data: data, encoding: .utf8) ?? "[]"
    }

    // MARK: - Persistencia en AppStorage
    private func tableDict() -> [String: String] {
        guard let data = tableRaw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }
    private func key(_ cat: SubjectiveCategory, _ medal: ProfileSheet.MedalSlot) -> String {
        cat.rawValue + "_" + medal.rawValue
    }
    private func flag(_ cat: SubjectiveCategory, _ medal: ProfileSheet.MedalSlot) -> String? {
        tableDict()[key(cat, medal)]
    }
    private func setFlag(_ emoji: String?, cat: SubjectiveCategory, medal: ProfileSheet.MedalSlot) {
        var dict = tableDict()
        let k = key(cat, medal)
        if let emoji { dict[k] = emoji } else { dict.removeValue(forKey: k) }
        let data = (try? JSONEncoder().encode(dict)) ?? Data()
        tableRaw = String(data: data, encoding: .utf8) ?? "{}"
    }
    /// Banderas ya usadas en esta categoría (para evitar duplicados dentro
    /// de la misma fila). Entre categorías sí se permiten repetidas.
    private func usedEmojisInCategory(_ cat: SubjectiveCategory) -> Set<String> {
        let dict = tableDict()
        var used: Set<String> = []
        for m in [ProfileSheet.MedalSlot.gold, .silver, .bronze] {
            if let v = dict[key(cat, m)] { used.insert(v) }
        }
        return used
    }

    /// Features visitadas, ordenadas alfabéticamente.
    private var visitedFeatures: [CountryFeature] {
        allFeatures
            .filter { visitedIsoCodes.contains($0.isoCode) }
            .sorted { $0.localizedName.localizedCompare($1.localizedName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isReordering {
                    List {
                        ForEach(decodeOrder()) { cat in
                            HStack(spacing: 10) {
                                Text(cat.emoji).font(.system(size: 18))
                                Text(cat.title).font(.palatino(.body, weight: .bold))
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .onMove { indices, newOffset in
                            var current = decodeOrder()
                            current.move(fromOffsets: indices, toOffset: newOffset)
                            saveOrder(current)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .environment(\.editMode, .constant(.active))
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(decodeOrder()) { cat in
                                categoryRow(cat)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle("Categorías personales")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isReordering ? "Listo" : "Editar") {
                        withAnimation { isReordering.toggle() }
                    }
                    .font(.palatino(.body, weight: isReordering ? .bold : .regular))
                }
            }
        }
        .sheet(item: $editing) { target in
            SubjectiveFlagPickerSheet(
                category: target.category,
                medal: target.medal,
                features: visitedFeatures,
                currentEmoji: flag(target.category, target.medal),
                usedEmojis: usedEmojisInCategory(target.category),
                onSelect: { emoji in setFlag(emoji, cat: target.category, medal: target.medal) },
                onClear: { setFlag(nil, cat: target.category, medal: target.medal) }
            )
        }
        .appColorScheme()
    }

    @ViewBuilder
    private func categoryRow(_ cat: SubjectiveCategory) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(cat.emoji).font(.system(size: 18))
                Text(cat.title)
                    .font(.palatino(.body, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
            }
            HStack(spacing: 10) {
                ForEach([ProfileSheet.MedalSlot.gold, .silver, .bronze], id: \.id) { medal in
                    let emoji = flag(cat, medal)
                    Button {
                        editing = EditTarget(category: cat, medal: medal)
                    } label: {
                        VStack(spacing: 4) {
                            Text(medal.emoji).font(.system(size: 14))
                            ZStack {
                                RoundedRectangle(cornerRadius: Radius.cell)
                                    .fill(Color(.systemGray5))
                                    .frame(height: 62)
                                if let emoji {
                                    FlagLabel(emoji: emoji, size: 40)
                                } else {
                                    Image(systemName: "plus")
                                        .font(.system(size: 18, weight: .light))
                                        .foregroundStyle(Color(.systemGray3))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.section))
    }
}

struct SubjectiveFlagPickerSheet: View {
    let category: SubjectiveCategory
    let medal: ProfileSheet.MedalSlot
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
                            Image(systemName: "flag.slash")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("No tienes países visitados que coincidan.")
                                .font(.palatino(.subheadline))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 60)
                        .padding(.horizontal, 32)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(filtered, id: \.isoCode) { feature in
                                let emoji    = feature.flagEmoji ?? "🌐"
                                let isChosen = emoji == currentEmoji
                                // Usado = está en otra medalla de ESTA categoría.
                                // Entre categorías se permite repetir.
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
            .navigationTitle("\(medal.emoji) \(category.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .appColorScheme()
    }
}

// MARK: - Banderas por letra
struct FlagAlphabetSheet: View {
    let allFeatures: [CountryFeature]
    let visitedIsoCodes: Set<String>
    let countingModeRaw: String

    @Environment(\.dismiss) private var dismiss
    @AppStorage("isRaskmapPro") private var isRaskmapPro: Bool = false
    @State private var showSubscription: Bool = false

    private var countingMode: CountingMode { CountingMode(rawValue: countingModeRaw) ?? .all }

    private struct AlphaGroup: Identifiable {
        let id: String          // the letter
        let items: [(iso: String, flag: String, name: String)]
        let hasAnyCountry: Bool
    }

    private var groups: [AlphaGroup] {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { String($0) }
        let allCountable = allFeatures.filter { countingMode.counts($0.isoCode) && $0.flagEmoji != nil }
        let visited = allCountable
            .filter { visitedIsoCodes.contains($0.isoCode) }
            .sorted { $0.localizedName.localizedCompare($1.localizedName) == .orderedAscending }

        var visitedDict: [String: [(String, String, String)]] = [:]
        for f in visited {
            let letter = String(f.localizedName.uppercased().first ?? "?")
            // f.flagEmoji está garantizado != nil por filter previo, pero
            // usamos ?? "🌐" defensivamente por si el filter cambia.
            visitedDict[letter, default: []].append((f.isoCode, f.flagEmoji ?? "🌐", f.localizedName))
        }
        var existsSet: Set<String> = []
        for f in allCountable {
            let letter = String(f.localizedName.uppercased().first ?? "?")
            existsSet.insert(letter)
        }
        return letters.map { letter in
            AlphaGroup(id: letter, items: visitedDict[letter] ?? [], hasAnyCountry: existsSet.contains(letter))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.id)
                                .font(.palatino(.largeTitle, weight: .bold))
                                .padding(.horizontal, 20)
                            if group.items.isEmpty {
                                Text(group.hasAnyCountry ? "Sin visitar" : "No existen")
                                    .font(.palatino(.caption))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 20)
                            } else {
                                let rows = stride(from: 0, to: group.items.count, by: 8).map {
                                    Array(group.items[$0..<min($0 + 8, group.items.count)])
                                }
                                ForEach(rows.indices, id: \.self) { r in
                                    HStack(spacing: 4) {
                                        ForEach(rows[r], id: \.iso) { item in
                                            FlagLabel(emoji: item.flag, size: 22)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 16)
                .blur(radius: isRaskmapPro ? 0 : 10)
                .allowsHitTesting(isRaskmapPro)
                .overlay(alignment: .top) {
                    if !isRaskmapPro {
                        Button { showSubscription = true } label: {
                            VStack(spacing: 10) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.purple)
                                Text("Función Pro")
                                    .font(.palatino(.body, weight: .bold))
                                    .foregroundStyle(.purple)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(countingMode == .all ? "Territorios visitados" : "Países visitados")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .sheet(isPresented: $showSubscription) { SubscriptionSheet() }
        .presentationDetents([.large])
        .appColorScheme()
    }
}
