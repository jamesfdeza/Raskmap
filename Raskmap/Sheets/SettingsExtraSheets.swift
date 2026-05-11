//
//  SettingsExtraSheets.swift
//  Raskmap
//
//  Helpers y sheets accesibles desde SettingsSheet:
//  · TripNotifications (enum) — recordatorios locales 7d/1d/0d antes
//    del viaje. requestAuthorization, reschedule, cancelAll.
//  · ExportDataSheet — export GDPR Art. 20 (JSON/CSV) + share.
//  · Color hex initializer extension.
//  · WidgetHomeColorSheet — picker color de fondo del widget home.
//
//  Extraído de ContentView.swift durante Fase D.
//

import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

// MARK: - Notificaciones locales de viajes próximos
//
// Recordatorios automáticos: 7 días antes, 1 día antes y el día del viaje.
// El usuario debe haber concedido permiso (lo pedimos al activar el toggle
// en Ajustes). Las notificaciones se reprograman cuando cambian los trips.

enum TripNotifications {

    /// Pide permiso si aún no está concedido. Devuelve true si quedó concedido.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    /// Borra todos los recordatorios y los re-genera para los trips futuros del
    /// próximo año. Idempotente; llamar siempre que cambien los datos.
    static func reschedule(trips: [Trip], featuresByIso: [String: CountryFeature]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let now = Date()
        let oneYearFromNow = Calendar.current.date(byAdding: .year, value: 1, to: now) ?? now
        for trip in trips where !trip.isSegmentChild {
            let day = Calendar.current.startOfDay(for: trip.dateFrom)
            guard day > now, day < oneYearFromNow else { continue }
            schedule(trip: trip, featuresByIso: featuresByIso, daysBefore: 7)
            schedule(trip: trip, featuresByIso: featuresByIso, daysBefore: 1)
            schedule(trip: trip, featuresByIso: featuresByIso, daysBefore: 0)
        }
    }

    private static func schedule(trip: Trip, featuresByIso: [String: CountryFeature], daysBefore: Int) {
        let cal = Calendar.current
        guard let triggerDay = cal.date(byAdding: .day, value: -daysBefore, to: trip.dateFrom) else { return }
        // 9:00 AM hora local del día anterior al evento.
        var comps = cal.dateComponents([.year, .month, .day], from: triggerDay)
        comps.hour = 9; comps.minute = 0
        guard let when = cal.date(from: comps), when > Date() else { return }

        let countryName = featuresByIso[trip.isoCode]?.localizedName ?? trip.isoCode
        let flag = featuresByIso[trip.isoCode]?.flagEmoji ?? "✈️"
        let title: String
        let body: String
        switch daysBefore {
        case 0:
            title = "¡Hoy empieza tu viaje!"
            body = "\(flag) Buen viaje a \(countryName)"
        case 1:
            title = "Mañana viajas"
            body = "\(flag) Tu viaje a \(countryName) empieza mañana"
        case 7:
            title = "En una semana"
            body = "\(flag) Tu viaje a \(countryName) empieza en 7 días"
        default:
            title = "Próximo viaje"
            body = "\(flag) \(countryName)"
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: when), repeats: false)
        let id = "trip_\(trip.isoCode)_\(Int(trip.dateFrom.timeIntervalSince1970))_d\(daysBefore)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

// MARK: - Export de datos (GDPR Art. 20 portabilidad)
struct ExportDataSheet: View {
    let countriesProvider: () -> [Country]
    let tripsProvider: () -> [Trip]

    @Environment(\.dismiss) private var dismiss
    @State private var generatedURL: URL? = nil
    @State private var format: ExportFormat = .json
    @State private var isGenerating: Bool = false
    @State private var errorMessage: String? = nil

    /// Enum nonisolated para poder leer `format` y `format.ext` desde
    /// Task.detached sin hop a MainActor (proyecto tiene
    /// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor).
    nonisolated enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
        case json = "JSON"
        case csv  = "CSV"
        var id: String { rawValue }
        var ext: String { rawValue.lowercased() }
        var description: String {
            switch self {
            case .json: return "Estructurado, completo (incluye segmentos y aerolíneas)"
            case .csv:  return "Tabular, una fila por viaje (compatible con Excel/Numbers)"
            }
        }
    }

    private let accent = BrandColor.accent

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle().fill(accent.opacity(0.12)).frame(width: 44, height: 44)
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Exportar tus datos")
                            .font(.custom("Satoshi-Bold", size: 18))
                        Text("Genera un archivo con tus países, viajes y preferencias para guardarlo o moverlo.")
                            .font(.palatino(.subheadline))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)

                Text("FORMATO")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.0)
                    .padding(.horizontal, 24)

                VStack(spacing: 0) {
                    ForEach(ExportFormat.allCases) { f in
                        Button { format = f } label: {
                            HStack(spacing: 12) {
                                Image(systemName: format == f ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(format == f ? accent : Color(.systemGray3))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.rawValue).font(.custom("Satoshi-Bold", size: 15))
                                    Text(f.description).font(.palatino(.caption)).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if f != ExportFormat.allCases.last { Divider().padding(.leading, 50) }
                    }
                }
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.card))
                .padding(.horizontal, 20)

                Button {
                    generateAndShare()
                } label: {
                    HStack(spacing: 8) {
                        if isGenerating { ProgressView().tint(.white) }
                        else { Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .semibold)) }
                        Text(isGenerating ? "Generando…" : "Generar y compartir")
                            .font(.custom("Satoshi-Bold", size: 15))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(accent, in: RoundedRectangle(cornerRadius: Radius.card))
                }
                .buttonStyle(.plain)
                .disabled(isGenerating)
                .padding(.horizontal, 20)

                if let err = errorMessage {
                    Text(err).font(.palatino(.caption)).foregroundStyle(.red)
                        .padding(.horizontal, 20)
                }
                Spacer()
            }
            .padding(.top, 12)
            .navigationTitle("Exportar datos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .appColorScheme()
    }

    private func generateAndShare() {
        isGenerating = true
        errorMessage = nil
        let countries = countriesProvider()
        let trips = tripsProvider()
        // Capturamos `format` en contexto MainActor (ExportFormat es Sendable +
        // nonisolated) antes de Task.detached. Acceder a `self.format` desde
        // el Task no compilaría: la View es @MainActor por default del
        // proyecto y el Task corre fuera del actor.
        let capturedFormat = format
        Task.detached(priority: .userInitiated) {
            do {
                let url = try Self.writeExport(format: capturedFormat, countries: countries, trips: trips)
                await MainActor.run {
                    isGenerating = false
                    generatedURL = url
                    presentShare(url: url)
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = "No se pudo generar el archivo: \(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor
    private func presentShare(url: URL) {
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // Buscar el presenting view controller activo (sheet anidado).
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let key = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else { return }
        var top = key.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        top?.present(av, animated: true)
    }

    /// `nonisolated` para poder llamarse desde Task.detached sin await en
    /// Swift 6 strict concurrency. La struct ExportDataSheet es @MainActor
    /// por ser SwiftUI View, pero esta función es pura (no toca estado UI).
    nonisolated private static func writeExport(format: ExportFormat, countries: [Country], trips: [Trip]) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = tmp.appendingPathComponent("raskmap-export-\(stamp).\(format.ext)")
        let data: Data
        switch format {
        case .json: data = try buildJSON(countries: countries, trips: trips)
        case .csv:  data = buildCSV(trips: trips).data(using: .utf8) ?? Data()
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    nonisolated private static func buildJSON(countries: [Country], trips: [Trip]) throws -> Data {
        let dfISO = ISO8601DateFormatter()
        let countryDicts: [[String: Any]] = countries.map { c in
            [
                "isoCode": c.isoCode,
                "name": c.name,
                "status": c.statusRaw,
                "visitCount": c.visitCount,
                "hasLived": c.hasLived,
                "plannedDate": c.plannedDate.map { dfISO.string(from: $0) } ?? NSNull(),
                "plannedDateTo": c.plannedDateTo.map { dfISO.string(from: $0) } ?? NSNull(),
                "transport": c.transport ?? NSNull(),
                "plannedTitle": c.plannedTitle ?? NSNull()
            ]
        }
        let tripDicts: [[String: Any]] = trips.map { t in
            var dict: [String: Any] = [
                "isoCode": t.isoCode,
                "title": t.title ?? NSNull(),
                "dateFrom": dfISO.string(from: t.dateFrom),
                "dateTo": t.dateTo.map { dfISO.string(from: $0) } ?? NSNull(),
                "transport": t.transport ?? NSNull(),
                "hasLayover": t.hasLayover,
                "isSegmentChild": t.isSegmentChild,
                "segmentGroupID": t.segmentGroupID ?? NSNull(),
                "tripAirports": t.tripAirports.map { ["iata": $0.iata, "count": $0.count] },
                "tripAirlines": t.tripAirlines.map { ["name": $0.name, "count": $0.count] }
            ]
            // Segments embebidos (si hay).
            if !t.tripSegments.isEmpty {
                dict["segments"] = t.tripSegments.map { seg -> [String: Any] in
                    [
                        "transport": seg.transport,
                        "isoCodes": seg.isoCodes,
                        "dateFrom": dfISO.string(from: seg.dateFrom),
                        "dateTo": seg.dateTo.map { dfISO.string(from: $0) } ?? NSNull(),
                        "airports": (seg.airports ?? []).map { ["iata": $0.iata, "count": $0.count] },
                        "returnAirports": (seg.returnAirports ?? []).map { ["iata": $0.iata, "count": $0.count] },
                        "airlines": (seg.airlines ?? []).map { ["name": $0.name, "count": $0.count] },
                        "visitedLayoverISOs": seg.visitedLayoverISOs ?? []
                    ]
                }
            }
            return dict
        }
        let root: [String: Any] = [
            "app": "Raskmap",
            "exportedAt": dfISO.string(from: Date()),
            "version": 1,
            "countries": countryDicts,
            "trips": tripDicts
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    nonisolated private static func buildCSV(trips: [Trip]) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        var lines: [String] = []
        lines.append("isoCode,title,dateFrom,dateTo,transport,airports,airlines,isSegmentChild")
        for t in trips {
            let title = t.title?.replacingOccurrences(of: ",", with: " ") ?? ""
            let airports = t.tripAirports.map { "\($0.iata)x\($0.count)" }.joined(separator: ";")
            let airlines = t.tripAirlines.map { "\($0.name.replacingOccurrences(of: ",", with: " "))x\($0.count)" }.joined(separator: ";")
            lines.append([
                t.isoCode,
                "\"\(title)\"",
                df.string(from: t.dateFrom),
                t.dateTo.map(df.string(from:)) ?? "",
                t.transport ?? "",
                "\"\(airports)\"",
                "\"\(airlines)\"",
                t.isSegmentChild ? "1" : "0"
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}


// MARK: - Info sheet genérica (FAQ, Novedades, Widgets)
// MARK: - Color hex helper

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int & 0xFF)          / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Widget home color picker

struct WidgetHomeColorSheet: View {
    @AppStorage("widgetBgColorHex") private var savedHex: String = "#EE6E7D"
    @State private var selectedHex: String = "#EE6E7D"
    @State private var isApplying: Bool = false
    @Environment(\.dismiss) private var dismiss

    private let palette: [(name: String, hex: String)] = [
        ("Rosa",      "#EE6E7D"),
        ("Azul",      "#53A3FE"),
        ("Verde mar", "#1ABC9C"),
        ("Morado",    "#9B59B6"),
        ("Naranja",   "#E67E22"),
        ("Verde",     "#27AE60"),
        ("Rojo",      "#C0392B"),
        ("Índigo",    "#3949AB"),
        ("Marino",    "#2C3E50"),
        ("Negro",     "#1C1C1E"),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Mini widget preview — layout idéntico al widget real (small)
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sheet)
                        .fill(Color(hex: selectedHex))
                        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
                    ZStack(alignment: .topLeading) {
                        Text("✈️")
                            .font(.system(size: 26))
                        Text("#ABC123")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text("🇯🇵").font(.system(size: 14))
                                Text("Viaje Tokio")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color(red: 0x53/255.0, green: 0xA3/255.0, blue: 0xFE/255.0))
                                    .lineLimit(1)
                            }
                            Text("42 días")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(.white)
                            Text("lun., 15 jun. 2026")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(15)
                }
                .frame(width: 160, height: 160)
                .padding(.top, 16)
                .animation(.easeInOut(duration: 0.2), value: selectedHex)

                // Color palette
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 18) {
                    ForEach(palette, id: \.hex) { item in
                        Button {
                            selectedHex = item.hex
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: item.hex))
                                    .frame(width: 52, height: 52)
                                    .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 2)
                                if selectedHex == item.hex {
                                    Circle()
                                        .strokeBorder(.white, lineWidth: 3)
                                        .frame(width: 52, height: 52)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 32)

                // Tamaños disponibles
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tamaños disponibles")
                        .font(.palatino(.footnote, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)

                    VStack(spacing: 0) {
                        ForEach([
                            ("square", "Pequeño", "Transporte, destino, días y fecha"),
                            ("rectangle.split.2x1", "Mediano", "Icono + destino con más detalle"),
                            ("square.grid.2x2", "Grande", "Próximo viaje, países visitados y próximos destinos")
                        ], id: \.1) { icon, size, desc in
                            HStack(spacing: 12) {
                                Image(systemName: icon)
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(size)
                                        .font(.palatino(.subheadline, weight: .bold))
                                    Text(desc)
                                        .font(.palatino(.caption))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            if size != "Grande" {
                                Divider().padding(.leading, 60)
                            }
                        }
                    }
                }

                Spacer()

                Button {
                    savedHex = selectedHex
                    WidgetDataWriter.syncColor(hex: selectedHex)
                    isApplying = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        isApplying = false
                        dismiss()
                    }
                } label: {
                    Text("Aceptar")
                        .font(.palatino(.body, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: Radius.cell))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .disabled(isApplying)
            }
            .navigationTitle("Pantalla principal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
            .overlay {
                if isApplying {
                    ZStack {
                        Color.black.opacity(0.45).ignoresSafeArea()
                        VStack(spacing: 20) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(1.4)
                                .tint(.white)
                            Text("Aplicando color…")
                                .font(.palatino(.body, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .onAppear { selectedHex = savedHex }
        .appColorScheme()
    }
}
