//
//  AwardsSheets.swift
//  Raskmap
//
//  Medallero personal y premios:
//  · PersonalAwardModel (@Model SwiftData) — premio personal del usuario.
//  · MedalleroSheet — pantalla principal del medallero.
//  · PersonalListSheet — gestión de listas personales.
//  · PersonalAwardSheet — editor de un premio personal.
//
//  Extraído de ContentView.swift durante Fase D.
//

import SwiftUI
import SwiftData

// MARK: - Medallero sheet
@Model
class PersonalAwardModel {
    var id: UUID = UUID()
    var sortOrder: Int = 0
    var title: String = ""
    var gold: String = ""
    var silver: String = ""
    var bronze: String = ""
    var extrasRaw: String = "[]"
    var createdAt: Date = Date()

    init(sortOrder: Int = 0) { self.sortOrder = sortOrder }

    var extras: [String] {
        get { (try? JSONDecoder().decode([String].self, from: Data(extrasRaw.utf8))) ?? [] }
        set { extrasRaw = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]" }
    }
}

struct MedalleroSheet: View {
    @Binding var topTable: String
    let allFeatures: [CountryFeature]
    let visitedIsoCodes: Set<String>

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PersonalAwardModel.sortOrder) private var personalAwards: [PersonalAwardModel]
    @State private var editingSpot: ProfileSheet.TopSpot? = nil
    @State private var editingAward: PersonalAwardModel? = nil
    @State private var showAlphabet: Bool = false
    @State private var showSubscription: Bool = false
    @AppStorage("countingMode") private var countingModeRaw: String = CountingMode.all.rawValue
    @AppStorage("isRaskmapPro") private var isRaskmapPro: Bool = false
    @AppStorage("personalList1Title") private var list1Title: String = ""
    @AppStorage("personalList1Content") private var list1Content: String = ""
    @State private var showList1: Bool = false
    @State private var showSubjectiveCategories: Bool = false

    private func tableDict() -> [String: String] {
        guard let data = topTable.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }
    private func tableFlag(region: ProfileSheet.TopRegion, medal: ProfileSheet.MedalSlot) -> String? {
        tableDict()[region.rawValue + "_" + medal.rawValue]
    }
    private func setTableFlag(_ emoji: String?, region: ProfileSheet.TopRegion, medal: ProfileSheet.MedalSlot) {
        var dict = tableDict()
        let key = region.rawValue + "_" + medal.rawValue
        if let emoji { dict[key] = emoji } else { dict.removeValue(forKey: key) }
        let data = (try? JSONEncoder().encode(dict)) ?? Data()
        topTable = String(data: data, encoding: .utf8) ?? "{}"
    }
    private func allUsedTableFlags() -> Set<String> { Set(tableDict().values) }
    private func visitedFeaturesForRegion(_ region: ProfileSheet.TopRegion) -> [CountryFeature] {
        allFeatures
            .filter { visitedIsoCodes.contains($0.isoCode) && region.isoCodes.contains($0.isoCode) }
            .sorted { $0.localizedName.localizedCompare($1.localizedName) == .orderedAscending }
    }

    @ViewBuilder
    private func awardSlot(_ award: PersonalAwardModel?) -> some View {
        if let award {
            Button { editingAward = award } label: {
                VStack(alignment: .leading, spacing: 3) {
                    FlagAwareText(text: award.title.isEmpty ? "Premio" : award.title,
                                  font: .palatino(.caption, weight: .bold),
                                  size: 14)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text("🥇").font(.system(size: 10))
                        FlagAwareText(text: award.gold.isEmpty ? "—" : award.gold,
                                      font: .palatino(.caption2),
                                      size: 11,
                                      foreground: .secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 4) {
                        Text("🥈").font(.system(size: 10))
                        FlagAwareText(text: award.silver.isEmpty ? "—" : award.silver,
                                      font: .palatino(.caption2),
                                      size: 11,
                                      foreground: .secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 4) {
                        Text("🥉").font(.system(size: 10))
                        FlagAwareText(text: award.bronze.isEmpty ? "—" : award.bronze,
                                      font: .palatino(.caption2),
                                      size: 11,
                                      foreground: .secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: Radius.cell))
            }
            .buttonStyle(.plain)
        } else {
            Button {
                let newAward = PersonalAwardModel(sortOrder: personalAwards.count)
                modelContext.insert(newAward)
                editingAward = newAward
            } label: {
                Image(systemName: "plus")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
            }
            .buttonStyle(.plain)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Text("").frame(width: 88)
                            ForEach([ProfileSheet.MedalSlot.gold, .silver, .bronze], id: \.id) { medal in
                                Text(medal.emoji).font(.title2).frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 8)
                        Divider()
                        ForEach(ProfileSheet.TopRegion.allCases) { region in
                            VStack(spacing: 0) {
                                HStack(spacing: 0) {
                                    Text(region.rawValue)
                                        .font(.palatino(.caption, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 88, alignment: .leading)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                    ForEach([ProfileSheet.MedalSlot.gold, .silver, .bronze], id: \.id) { medal in
                                        let emoji = tableFlag(region: region, medal: medal)
                                        Button {
                                            editingSpot = ProfileSheet.TopSpot(region: region, medal: medal)
                                        } label: {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: Radius.cell)
                                                    .fill(Color(.systemGray5))
                                                    .frame(width: 52, height: 52)
                                                if let emoji {
                                                    FlagLabel(emoji: emoji, size: 34)
                                                } else {
                                                    Image(systemName: "plus")
                                                        .font(.system(size: 16, weight: .light))
                                                        .foregroundStyle(Color(.systemGray3))
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                                .padding(.vertical, 6)
                                if region != ProfileSheet.TopRegion.allCases.last {
                                    Divider().padding(.leading, 88)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.sheet))
                    .padding(.horizontal, 12)
                // ── Premios personales (2 slots) ──
                let awardSlots: [PersonalAwardModel?] = (0..<2).map { i in i < personalAwards.count ? personalAwards[i] : nil }
                HStack(spacing: 8) {
                    awardSlot(awardSlots[0])
                    awardSlot(awardSlots[1])
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
                .padding(.top, 4)
                }
                .padding(.top, 16)
                // ── Categorías personales + Lista personal 1 (mismo card, con separador) ──
                VStack(spacing: 0) {
                    Button { showSubjectiveCategories = true } label: {
                        HStack {
                            Label("Categorías personales", systemImage: "trophy")
                                .font(.palatino(.body))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 16)
                    Button { showList1 = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "list.bullet")
                                .font(.palatino(.body))
                                .foregroundStyle(.primary)
                            FlagAwareText(text: list1Title.isEmpty ? "Lista personal" : list1Title,
                                          font: .palatino(.body),
                                          size: 18)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }
            .navigationTitle("Premios personales")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAlphabet = true } label: {
                        Image(systemName: "abc").font(.body)
                    }
                }
            }
        }
        .sheet(isPresented: $showAlphabet) {
            FlagAlphabetSheet(
                allFeatures: allFeatures,
                visitedIsoCodes: visitedIsoCodes,
                countingModeRaw: countingModeRaw
            )
        }
        .sheet(isPresented: $showSubscription) {
            SubscriptionSheet()
        }
        .sheet(item: $editingSpot) { spot in
            TableFlagPickerSheet(
                spot: spot,
                features: visitedFeaturesForRegion(spot.region),
                currentEmoji: tableFlag(region: spot.region, medal: spot.medal),
                usedEmojis: allUsedTableFlags(),
                onSelect: { emoji in setTableFlag(emoji, region: spot.region, medal: spot.medal) },
                onClear: { setTableFlag(nil, region: spot.region, medal: spot.medal) }
            )
        }
        .sheet(item: $editingAward) { award in
            PersonalAwardSheet(
                award: award,
                onDelete: {
                    modelContext.delete(award)
                    editingAward = nil
                }
            )
        }
        .sheet(isPresented: $showList1) {
            PersonalListSheet(title: $list1Title, content: $list1Content)
        }
        .sheet(isPresented: $showSubjectiveCategories) {
            SubjectiveCategoriesSheet(
                allFeatures: allFeatures,
                visitedIsoCodes: visitedIsoCodes
            )
        }
        .appColorScheme()
    }
}

// MARK: - Personal List Sheet
struct PersonalListSheet: View {
    @Binding var title: String
    @Binding var content: String
    @Environment(\.dismiss) private var dismiss
    @State private var titleDraft: String = ""
    @State private var contentDraft: String = ""
    @FocusState private var contentFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Título de la lista", text: $titleDraft)
                    .font(.palatino(.title3, weight: .bold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                Divider()
                TextEditor(text: $contentDraft)
                    .font(.palatino(.body))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .focused($contentFocused)
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Guardar") {
                        title = titleDraft
                        content = contentDraft
                        dismiss()
                    }
                    .font(.palatino(.body, weight: .bold))
                }
            }
        }
        .onAppear {
            titleDraft = title
            contentDraft = content
        }
        .presentationDetents([.large])
    }
}

// MARK: - Personal Award Sheet
struct PersonalAwardSheet: View {
    let award: PersonalAwardModel
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var gold: String
    @State private var silver: String
    @State private var bronze: String
    @State private var extras: [String]
    @State private var showDeleteConfirm = false

    private let maxExtras = 5

    init(award: PersonalAwardModel, onDelete: @escaping () -> Void) {
        self.award = award
        self.onDelete = onDelete
        _title = State(initialValue: award.title)
        _gold = State(initialValue: award.gold)
        _silver = State(initialValue: award.silver)
        _bronze = State(initialValue: award.bronze)
        _extras = State(initialValue: award.extras)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Título")
                            .font(.palatino(.body))
                            .foregroundStyle(.secondary)
                        TextField("Nombre del premio", text: $title)
                            .font(.palatino(.body))
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section(header: Text("Medallas").font(.palatino(.caption))) {
                    HStack {
                        Text("🥇")
                        TextField("Oro", text: $gold)
                            .font(.palatino(.body))
                    }
                    HStack {
                        Text("🥈")
                        TextField("Plata", text: $silver)
                            .font(.palatino(.body))
                    }
                    HStack {
                        Text("🥉")
                        TextField("Bronce", text: $bronze)
                            .font(.palatino(.body))
                    }
                }
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Eliminar premio")
                                .font(.palatino(.body))
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(title.isEmpty ? "Premio personal" : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }.font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Guardar") {
                        award.title = title
                        award.gold = gold
                        award.silver = silver
                        award.bronze = bronze
                        award.extras = extras.filter { !$0.isEmpty }
                        dismiss()
                    }
                    .font(.palatino(.body, weight: .bold))
                }
            }
            .alert("¿Eliminar este premio?", isPresented: $showDeleteConfirm) {
                Button("Eliminar", role: .destructive) { onDelete() }
                Button("Cancelar", role: .cancel) {}
            }
        }
        .appColorScheme()
    }
}
