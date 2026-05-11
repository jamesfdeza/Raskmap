//
//  SettingsSubSheets.swift
//  Raskmap
//
//  Sheets informativos / de ayuda accesibles desde SettingsSheet:
//  · SettingsInfoSheet — info genérica (modos de conteo, etc.)
//  · LegalInfoSheet — política de privacidad, términos, créditos, etc.
//  · WidgetLockScreenSheet — guía de widgets de Lock Screen
//  · WidgetWatchSheet — guía de complicaciones Apple Watch
//
//  Todos son self-contained (reciben title/icon/content, ningún acceso
//  a state privado de ContentView). Extraídos durante Fase D.
//

import SwiftUI

// MARK: - SettingsInfoSheet

struct SettingsInfoSheet: View {
    let title: String
    let icon: String
    let content: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: icon)
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                        .padding(.top, 32)
                    Text(content)
                        .font(.palatino(.body))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer(minLength: 48)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .presentationDetents([.medium])
        .appColorScheme()
    }
}

// MARK: - LegalInfoSheet

struct LegalInfoSheet: View {
    let title: String
    let icon: String
    let content: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: icon)
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                        .padding(.top, 32)
                    // `FlagAwareLongText` rendea con Twemoji cualquier
                    // bandera embebida en el texto manteniendo line wrapping
                    // nativo. Si el contenido no tiene banderas (caso de la
                    // sección legal actual) cae a `Text` plano sin overhead.
                    FlagAwareLongText(text: content,
                                      font: .palatino(.body),
                                      foreground: .primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                    Spacer(minLength: 48)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
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

// MARK: - Widget Lock Screen info sheet

struct WidgetLockScreenSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct WidgetRow: Identifiable {
        let id = UUID()
        let shape: String
        let name: String
        let desc: String
    }

    private let widgets: [WidgetRow] = [
        WidgetRow(shape: "circle", name: "% del mundo (circular)",
                  desc: "Gauge circular que muestra el porcentaje del mundo que has visitado. Se configura con el modo de conteo (ONU, ONU+obs. o Todos)."),
        WidgetRow(shape: "rectangle", name: "Próximo viaje (rectangular)",
                  desc: "Muestra la bandera del país y los días que quedan hasta tu próximo viaje."),
        WidgetRow(shape: "minus", name: "Cuenta atrás (encima del reloj)",
                  desc: "Línea de texto con los días restantes y el nombre del destino. Aparece encima de la hora en la pantalla de bloqueo."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "lock.display")
                        .font(.system(size: 44))
                        .foregroundStyle(.blue)
                        .padding(.top, 28)
                    Text("Añade estos widgets en la pantalla de bloqueo manteniéndola pulsada y tocando \"Personalizar\".")
                        .font(.palatino(.subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    VStack(spacing: 0) {
                        ForEach(Array(widgets.enumerated()), id: \.element.id) { idx, w in
                            HStack(spacing: 12) {
                                Image(systemName: w.shape)
                                    .font(.system(size: 16))
                                    .foregroundStyle(.blue)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(w.name)
                                        .font(.palatino(.body, weight: .bold))
                                    Text(w.desc)
                                        .font(.palatino(.subheadline))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 24).padding(.vertical, 8)
                            if idx < widgets.count - 1 {
                                Divider().padding(.leading, 60)
                            }
                        }
                    }
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
                    .padding(.horizontal, 20)
                    Spacer(minLength: 32)
                }
            }
            .navigationTitle("Pantalla de bloqueo")
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

// MARK: - Widget Apple Watch info sheet

struct WidgetWatchSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct WidgetRow: Identifiable {
        let id = UUID()
        let shape: String
        let name: String
        let desc: String
    }

    private let widgets: [WidgetRow] = [
        WidgetRow(shape: "circle", name: "Próximo viaje (circular)",
                  desc: "Muestra la bandera del próximo destino como complicación circular en tu esfera de Apple Watch."),
        WidgetRow(shape: "rectangle", name: "Próximo viaje (rectangular)",
                  desc: "Bandera, días restantes y nombre del próximo destino. Ideal para esferas con complicación grande."),
        WidgetRow(shape: "circle.fill", name: "Países visitados (circular)",
                  desc: "Gauge circular con el número de países ONU que has visitado respecto al total de 193."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "applewatch")
                        .font(.system(size: 44))
                        .foregroundStyle(.blue)
                        .padding(.top, 28)
                    Text("Añade las complicaciones de Raskmap en tu esfera de Apple Watch desde la app Watch o pulsando la esfera.")
                        .font(.palatino(.subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    VStack(spacing: 0) {
                        ForEach(Array(widgets.enumerated()), id: \.element.id) { idx, w in
                            HStack(spacing: 12) {
                                Image(systemName: w.shape)
                                    .font(.system(size: 16))
                                    .foregroundStyle(.blue)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(w.name)
                                        .font(.palatino(.body, weight: .bold))
                                    Text(w.desc)
                                        .font(.palatino(.subheadline))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 24).padding(.vertical, 8)
                            if idx < widgets.count - 1 {
                                Divider().padding(.leading, 60)
                            }
                        }
                    }
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
                    .padding(.horizontal, 20)
                    Spacer(minLength: 32)
                }
            }
            .navigationTitle("Apple Watch")
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
