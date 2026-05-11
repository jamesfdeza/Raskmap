//
//  SmallWidgets.swift
//  Raskmap
//
//  Widgets pequeños reutilizables:
//  · FlowLayoutCentered — flow layout horizontal centrado de emojis.
//  · VisitCountPickerSheet — picker numérico simple para visit count.
//  · RangeDatePicker — UIViewRepresentable wrapping de UICalendarView
//    para rango de fechas (multi-day selection).
//
//  Self-contained: no acceden a state privado de ContentView.
//
//  Extraído de ContentView.swift durante Fase D.
//

import SwiftUI
import UIKit
import SwiftData

struct FlowLayoutCentered: View {
    let emojis: [String]
    let year: Int
    let isLeft: Bool
    /// Máximo de banderas por línea — el grid del año actual usa 5 para que las
    /// columnas Finalizados/Próximos quepan en mitad del ancho del perfil sin
    /// recortar emojis. Para años pasados se permite hasta 10 por línea (ancho
    /// completo).
    var perRow: Int = 5
    var body: some View {
        let rows = stride(from: 0, to: emojis.count, by: perRow).map {
            Array(emojis[$0..<min($0 + perRow, emojis.count)])
        }
        VStack(alignment: .center, spacing: 4) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    ForEach(Array(rows[i].enumerated()), id: \.offset) { _, e in
                        FlagLabel(emoji: e, size: 22)
                    }
                }
            }
        }
    }
}


// MARK: - Selector de visitas manuales
struct VisitCountPickerSheet: View {
    @Bindable var country: Country
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Text("Visitas manuales").font(.palatino(.title3, weight: .bold))
                HStack(spacing: 24) {
                    Button {
                        if country.visitCount > 0 { country.visitCount -= 1; modelContext.saveOrWarn() }
                    } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 44)).foregroundStyle(.red)
                    }
                    Text("\(country.visitCount)").font(.system(size: 64, weight: .bold, design: .rounded))
                    Button {
                        country.visitCount += 1; modelContext.saveOrWarn()
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 44)).foregroundStyle(.blue)
                    }
                }
                Spacer()
            }
            .navigationTitle("Contador")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}


// MARK: - Selector de rango de fechas (calendario nativo)
struct RangeDatePicker: UIViewRepresentable {
    @Binding var dateFrom: Date
    @Binding var dateTo: Date?
    @Binding var pickingFrom: Bool
    var minDate: Date? = nil
    var maxDate: Date? = nil

    func makeUIView(context: Context) -> UICalendarView {
        let v = UICalendarView()
        v.calendar = Calendar.current
        v.locale = Locale(identifier: "es_ES")
        v.fontDesign = .rounded
        let sel = UICalendarSelectionSingleDate(delegate: context.coordinator)
        v.selectionBehavior = sel
        context.coordinator.calendarView = v
        context.coordinator.singleSel = sel
        context.coordinator.parent = self
        return v
    }

    func updateUIView(_ v: UICalendarView, context: Context) {
        context.coordinator.parent = self
        let cal = Calendar.current
        let showDate = pickingFrom ? dateFrom : (dateTo ?? dateFrom)
        let targetComps = cal.dateComponents([.year, .month, .day], from: showDate)
        context.coordinator.singleSel?.selectedDate = targetComps
        // Navegar al mes correcto solo cuando cambia el tab activo (no en cada re-render)
        let coord = context.coordinator
        if coord.lastPickingFrom != pickingFrom {
            coord.lastPickingFrom = pickingFrom
            let visible = v.visibleDateComponents
            if visible.year != targetComps.year || visible.month != targetComps.month {
                v.setVisibleDateComponents(
                    DateComponents(year: targetComps.year, month: targetComps.month, day: 1),
                    animated: true
                )
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, UICalendarSelectionSingleDateDelegate {
        var parent: RangeDatePicker!
        weak var calendarView: UICalendarView?
        weak var singleSel: UICalendarSelectionSingleDate?
        var lastPickingFrom: Bool = true

        func dateSelection(_ selection: UICalendarSelectionSingleDate,
                           didSelectDate dateComponents: DateComponents?) {
            guard let comps = dateComponents,
                  let date = Calendar.current.date(from: comps) else { return }
            let cal = Calendar.current
            if parent.pickingFrom {
                parent.dateFrom = date
                // Default: vuelta al día siguiente (si no supera maxDate).
                // Fallback: si el cálculo falla (edge case de calendario), +86400s.
                let nextDay = cal.date(byAdding: .day, value: 1, to: date)
                            ?? date.addingTimeInterval(86_400)
                if let max = parent.maxDate {
                    parent.dateTo = nextDay <= max ? nextDay : nil
                } else {
                    parent.dateTo = nextDay
                }
                parent.pickingFrom = false
            } else {
                if date < parent.dateFrom {
                    parent.dateFrom = date
                    let nextDay = cal.date(byAdding: .day, value: 1, to: date)
                                ?? date.addingTimeInterval(86_400)
                    if let max = parent.maxDate {
                        parent.dateTo = nextDay <= max ? nextDay : nil
                    } else {
                        parent.dateTo = nextDay
                    }
                } else if date == parent.dateFrom {
                    parent.dateTo = nil
                } else {
                    parent.dateTo = date
                }
            }
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate,
                           canSelectDate dateComponents: DateComponents?) -> Bool {
            guard let comps = dateComponents,
                  let date = Calendar.current.date(from: comps) else { return false }
            let day = Calendar.current.startOfDay(for: date)
            if let min = parent.minDate, day < min { return false }
            if let max = parent.maxDate, day > max { return false }
            return true
        }
    }
}
