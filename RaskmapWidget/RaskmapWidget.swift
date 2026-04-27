//
//  RaskmapWidget.swift
//  RaskmapWidget
//

import WidgetKit
import SwiftUI

private let appGroupID = "group.com.jaime.raskmap"

private var sharedDefaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

// MARK: - App Group helpers

func intFromShared(_ key: String) -> Int {
    sharedDefaults?.integer(forKey: key) ?? 0
}

func stringFromShared(_ key: String) -> String {
    sharedDefaults?.string(forKey: key) ?? ""
}

// MARK: - Modo de conteo

enum WCountingMode: String, CaseIterable {
    case un     = "un"
    case unPlus = "unPlus"
    case all    = "all"

    var label: String {
        switch self {
        case .un:     return "ONU"
        case .unPlus: return "ONU + obs."
        case .all:    return "Todos"
        }
    }

    var visitedLabel: String {
        switch self {
        case .un: return "Países visitados"
        default:  return "Territorios visitados"
        }
    }

    var shortLabel: String {
        switch self {
        case .un:     return "ONU"
        case .unPlus: return "ONU+OBS"
        case .all:    return "TODOS"
        }
    }

    var total: Int {
        switch self {
        case .un:     return 193
        case .unPlus: return 195
        case .all:    return 249
        }
    }
}

// MARK: - Entry

struct RaskmapEntry: TimelineEntry {
    let date: Date
    let mode: WCountingMode
    let visited: Int
    let visitedUN: Int
    let visitedUNPlus: Int
    let visitedAll: Int
    let bgColor: Color
    let nextFlag: String
    let nextDays: Int
    let nextName: String
    let nextTitle: String
    let nextTransport: String
    let nextDateFrom: Date?
    let nextBookingRef: String
    let upcomingFlags: String
    let topVisitedFlags: String
}

// MARK: - Provider

struct RaskmapProvider: TimelineProvider {
    typealias Entry = RaskmapEntry

    func placeholder(in context: Context) -> RaskmapEntry {
        RaskmapEntry(
            date: .now, mode: .un, visited: 42,
            visitedUN: 42, visitedUNPlus: 45, visitedAll: 48,
            bgColor: colorFromShared(),
            nextFlag: "🇯🇵", nextDays: 18, nextName: "Tokio", nextTitle: "",
            nextTransport: "✈️",
            nextDateFrom: Calendar.current.date(byAdding: .day, value: 18, to: .now),
            nextBookingRef: "ABC123",
            upcomingFlags: "🇯🇵🇩🇪🇫🇷🇮🇹🇬🇧🇪🇸",
            topVisitedFlags: "🇪🇸🇫🇷🇮🇹🇺🇸🇯🇵🇩🇪🇵🇹🇳🇱"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (RaskmapEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RaskmapEntry>) -> Void) {
        let entry = makeEntry()
        let next  = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> RaskmapEntry {
        let modeRaw = stringFromShared("widget_counting_mode")
        let mode = WCountingMode(rawValue: modeRaw) ?? .un
        let visited = intFromShared("widget_visited_\(mode.rawValue)")
        let dateFromTS = sharedDefaults?.double(forKey: "widget_next_date") ?? 0
        let dateFrom: Date? = dateFromTS > 0 ? Date(timeIntervalSince1970: dateFromTS) : nil
        return RaskmapEntry(
            date: .now,
            mode: mode,
            visited: visited,
            visitedUN:     intFromShared("widget_visited_un"),
            visitedUNPlus: intFromShared("widget_visited_unPlus"),
            visitedAll:    intFromShared("widget_visited_all"),
            bgColor: colorFromShared(),
            nextFlag:      stringFromShared("widget_next_flag"),
            nextDays:      sharedDefaults?.object(forKey: "widget_next_days") as? Int ?? -1,
            nextName:      stringFromShared("widget_next_name"),
            nextTitle:     stringFromShared("widget_next_title"),
            nextTransport: stringFromShared("widget_next_transport"),
            nextDateFrom:  dateFrom,
            nextBookingRef: stringFromShared("widget_next_booking"),
            upcomingFlags:   stringFromShared("widget_all_flags"),
            topVisitedFlags: stringFromShared("widget_top_visited_flags")
        )
    }
}

// MARK: - Color helper

private func colorFromShared() -> Color {
    let hex = sharedDefaults?.string(forKey: "widget_bg_color") ?? "#EE6E7D"
    let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: clean).scanHexInt64(&int)
    let r = Double((int >> 16) & 0xFF) / 255
    let g = Double((int >> 8)  & 0xFF) / 255
    let b = Double(int & 0xFF)          / 255
    return Color(red: r, green: g, blue: b)
}

// MARK: - Helpers

private func daysLabel(_ days: Int) -> String {
    if days == 1 { return "1 día" }
    if days <= 99 { return "\(days) días" }
    let months = max(1, days / 30)
    return "+\(months) meses"
}

private let widgetDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "es_ES")
    f.dateFormat = "EEE, d MMM yyyy"
    return f
}()

private let raskmapBlue = Color(red: 0x53/255.0, green: 0xA3/255.0, blue: 0xFE/255.0)

// MARK: - Views

struct RaskmapWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RaskmapEntry

    var body: some View {
        switch family {
        case .systemSmall:  SmallView(entry: entry)
        case .systemMedium: MediumView(entry: entry)
        case .systemLarge:  LargeView(entry: entry)
        default:            SmallView(entry: entry)
        }
    }
}

// MARK: - Small (próximo viaje)

private struct SmallView: View {
    let entry: RaskmapEntry

    var body: some View {
        if entry.nextDays < 0 || entry.nextFlag.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("✈️").font(.system(size: 28))
                Spacer()
                Text("Sin próximo\nviaje")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(15)
            .containerBackground(entry.bgColor, for: .widget)
        } else {
            let displayName = entry.nextTitle.isEmpty ? entry.nextName : entry.nextTitle
            ZStack(alignment: .topLeading) {
                Text(entry.nextTransport.isEmpty ? "✈️" : entry.nextTransport)
                    .font(.system(size: 26))
                if !entry.nextBookingRef.isEmpty {
                    Text("#\(entry.nextBookingRef)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        FlagLabel(emoji: entry.nextFlag, size: 14)
                        Text(displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(raskmapBlue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Text(daysLabel(entry.nextDays))
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if let d = entry.nextDateFrom {
                        Text(widgetDateFormatter.string(from: d))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(15)
            .containerBackground(entry.bgColor, for: .widget)
        }
    }
}

// MARK: - Medium

private struct MediumView: View {
    let entry: RaskmapEntry

    private var upcomingFlagsSkippingFirst: String {
        String(entry.upcomingFlags.dropFirst())
    }

    /// Formatea `nextDateFrom` como "vie · 15 may" (corto, locale es).
    private var formattedNextDate: String? {
        guard let d = entry.nextDateFrom else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEE · d MMM"
        return f.string(from: d).lowercased()
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Text("PRÓXIMO VIAJE")
                        .font(.custom("Satoshi-Bold", size: 9))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.75))
                    if !entry.nextTransport.isEmpty {
                        Text(entry.nextTransport)
                            .font(.system(size: 11))
                            .opacity(0.75)
                    }
                    if !entry.nextBookingRef.isEmpty {
                        Text("· #\(entry.nextBookingRef)")
                            .font(.custom("Satoshi-Bold", size: 9))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }

                if entry.nextDays >= 0, !entry.nextFlag.isEmpty {
                    HStack(alignment: .center, spacing: 12) {
                        FlagLabel(emoji: entry.nextFlag, size: 52)
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.nextName.isEmpty ? "—" : entry.nextName)
                                .font(.custom("Satoshi-Bold", size: 19))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                            HStack(spacing: 4) {
                                Text("en")
                                    .font(.custom("Satoshi-Regular", size: 11))
                                    .foregroundStyle(.white.opacity(0.7))
                                Text("\(entry.nextDays)")
                                    .font(.custom("Satoshi-Bold", size: 17))
                                    .monospacedDigit()
                                    .foregroundStyle(.white)
                                Text(entry.nextDays == 1 ? "DÍA" : "DÍAS")
                                    .font(.custom("Satoshi-Bold", size: 9))
                                    .tracking(1.2)
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            if let dateLabel = formattedNextDate {
                                Text(dateLabel)
                                    .font(.custom("Satoshi-Regular", size: 10))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(1)
                            }
                        }
                    }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        Text("🗺️")
                            .font(.system(size: 44))
                            .opacity(0.85)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sin viajes")
                                .font(.custom("Satoshi-Bold", size: 17))
                                .foregroundStyle(.white)
                            Text("planea el siguiente")
                                .font(.custom("Satoshi-Regular", size: 11))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }

                Spacer(minLength: 0)

                if !upcomingFlagsSkippingFirst.isEmpty {
                    HStack(alignment: .center, spacing: 8) {
                        Text("PRÓXIMOS")
                            .font(.custom("Satoshi-Bold", size: 8))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.55))
                        FlagStrip(flags: String(upcomingFlagsSkippingFirst.prefix(6)), size: 17, spacing: 5)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 20)
            .padding(.trailing, 4)
            .padding(.vertical, 18)

            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 0.5)
                .padding(.vertical, 22)

            VStack(spacing: 4) {
                Spacer()
                Text("\(entry.visited)")
                    .font(.custom("Palatino-Bold", size: 52))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(entry.mode.visitedLabel)
                    .font(.custom("Palatino", size: 10))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Spacer()
                Text(entry.mode.label)
                    .font(.custom("Palatino", size: 9))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(width: 104)
            .padding(.vertical, 18)
            .padding(.horizontal, 8)
        }
        .containerBackground(entry.bgColor, for: .widget)
    }
}

// MARK: - Large

private struct LargeView: View {
    let entry: RaskmapEntry

    /// Misma formateo que MediumView — "vie · 15 may".
    private var formattedNextDate: String? {
        guard let d = entry.nextDateFrom else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEE · d MMM"
        return f.string(from: d).lowercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                if entry.nextDays >= 0, !entry.nextFlag.isEmpty {
                    FlagLabel(emoji: entry.nextFlag, size: 60)
                        .shadow(color: .black.opacity(0.3), radius: 5, y: 2)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text("PRÓXIMO VIAJE")
                                .font(.custom("Satoshi-Bold", size: 10))
                                .tracking(1.8)
                                .foregroundStyle(.white.opacity(0.75))
                            if !entry.nextTransport.isEmpty {
                                Text(entry.nextTransport)
                                    .font(.system(size: 11))
                                    .opacity(0.75)
                            }
                        }
                        Text(entry.nextName.isEmpty ? "—" : entry.nextName)
                            .font(.custom("Satoshi-Bold", size: 24))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        if let dateLabel = formattedNextDate {
                            Text(dateLabel)
                                .font(.custom("Satoshi-Regular", size: 11))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 6)

                    VStack(alignment: .center, spacing: 0) {
                        Text("\(entry.nextDays)")
                            .font(.custom("Satoshi-Bold", size: 42))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text(entry.nextDays == 1 ? "DÍA" : "DÍAS")
                            .font(.custom("Satoshi-Bold", size: 10))
                            .tracking(1.6)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                } else {
                    Text("🗺️")
                        .font(.system(size: 48))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SIN VIAJES PLANEADOS")
                            .font(.custom("Satoshi-Bold", size: 10))
                            .tracking(1.6)
                            .foregroundStyle(.white.opacity(0.75))
                        Text("Planea el siguiente")
                            .font(.custom("Satoshi-Bold", size: 20))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(height: 0.5)
                .padding(.horizontal, 16)

            HStack(spacing: 0) {
                statCell(value: entry.visitedUN, label: "ONU")
                divider
                statCell(value: entry.visitedUNPlus, label: "ONU+OBS")
                divider
                statCell(value: entry.visitedAll, label: "TODOS")
            }
            .padding(.vertical, 14)

            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(height: 0.5)
                .padding(.horizontal, 16)

            // Tres flag-strips: PRÓXIMOS, MÁS VISITADOS y NUEVOS DESTINOS — el
            // tercero usa el mismo dataset de "más visitados" pero invertido
            // (los más recientes/menos repetidos quedan al final del string),
            // así rellenamos visualmente la zona inferior antes vacía.
            VStack(alignment: .leading, spacing: 12) {
                let upcomingRest = String(entry.upcomingFlags.dropFirst())
                flagStrip(title: "PRÓXIMOS", flags: upcomingRest, placeholder: "Sin viajes futuros")
                flagStrip(title: "MÁS VISITADOS", flags: entry.topVisitedFlags, placeholder: "Registra tu primer viaje")
                flagStrip(title: "NUEVOS",
                          flags: String(entry.topVisitedFlags.reversed()),
                          placeholder: "Sin destinos recientes")
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 14)

            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(height: 0.5)
                .padding(.horizontal, 16)

            // Footer minimal — fija el contenido al fondo del widget en vez
            // de dejar `Spacer` vacío. Muestra modo de conteo + booking ref
            // si hay viaje próximo + branding suave.
            HStack(spacing: 8) {
                Text(entry.mode.shortLabel)
                    .font(.custom("Satoshi-Bold", size: 9))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.55))
                if !entry.nextBookingRef.isEmpty {
                    Text("·")
                        .font(.custom("Satoshi-Bold", size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("PNR \(entry.nextBookingRef)")
                        .font(.custom("Satoshi-Bold", size: 9))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer()
                Text("RASKMAP")
                    .font(.custom("Satoshi-Bold", size: 9))
                    .tracking(2.0)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .containerBackground(entry.bgColor, for: .widget)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.18))
            .frame(width: 0.5, height: 36)
    }

    @ViewBuilder
    private func statCell(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.custom("Palatino-Bold", size: 26))
                .foregroundStyle(.white)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.custom("Satoshi-Bold", size: 9))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func flagStrip(title: String, flags: String, placeholder: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.custom("Satoshi-Bold", size: 9))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 84, alignment: .leading)
            if flags.isEmpty {
                Text(placeholder)
                    .font(.custom("Satoshi-Regular", size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            } else {
                FlagStrip(flags: String(flags.prefix(9)), size: 18, spacing: 4)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Widget

struct RaskmapWidget: Widget {
    let kind = "RaskmapWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RaskmapProvider()) { entry in
            RaskmapWidgetView(entry: entry)
        }
        .configurationDisplayName("Raskmap")
        .description("Próximo viaje y resumen de visitados.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Lock screen: porcentaje (accessoryCircular)

struct LockPctEntry: TimelineEntry {
    let date: Date
    let visited: Int
    let total: Int
    let isPro: Bool
    var pct: Double { total > 0 ? Double(visited) / Double(total) * 100.0 : 0.0 }
}

struct LockPctProvider: TimelineProvider {
    func placeholder(in context: Context) -> LockPctEntry {
        LockPctEntry(date: .now, visited: 42, total: 193, isPro: true)
    }
    func getSnapshot(in context: Context, completion: @escaping (LockPctEntry) -> Void) {
        completion(makeEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LockPctEntry>) -> Void) {
        let entry = makeEntry()
        let next  = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
    private func makeEntry() -> LockPctEntry {
        let modeRaw = sharedDefaults?.string(forKey: "widget_counting_mode") ?? "un"
        let mode    = WCountingMode(rawValue: modeRaw) ?? .un
        let visited = intFromShared("widget_visited_\(mode.rawValue)")
        let isPro   = sharedDefaults?.bool(forKey: "widget_is_pro") ?? false
        return LockPctEntry(date: .now, visited: visited, total: mode.total, isPro: isPro)
    }
}

struct LockPctView: View {
    let entry: LockPctEntry
    var body: some View {
        if entry.isPro {
            Gauge(value: Double(entry.visited), in: 0...Double(entry.total)) {
                EmptyView()
            } currentValueLabel: {
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", entry.pct))
                        .font(.system(size: 14, weight: .bold))
                        .minimumScaleFactor(0.7)
                    Text("%")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .gaugeStyle(.accessoryCircular)
            .containerBackground(.clear, for: .widget)
        } else {
            Image(systemName: "lock.fill")
                .font(.system(size: 20))
                .containerBackground(.clear, for: .widget)
        }
    }
}

struct RaskmapLockPctWidget: Widget {
    let kind = "RaskmapLockPct"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LockPctProvider()) { entry in
            LockPctView(entry: entry)
        }
        .configurationDisplayName("% del mundo")
        .description("Porcentaje del mundo visitado.")
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: - Lock screen: próximo viaje (rectangular + inline)

struct LockNextEntry: TimelineEntry {
    let date: Date
    let flag: String
    let days: Int
    let name: String
    /// Título custom del viaje (`Trip.title` / `country.plannedTitle`). Vacío = usar `name` como fallback.
    let title: String
    let isPro: Bool
}

struct LockNextProvider: TimelineProvider {
    func placeholder(in context: Context) -> LockNextEntry {
        LockNextEntry(date: .now, flag: "🇯🇵", days: 12, name: "Tokio", title: "Viaje Tokio", isPro: true)
    }
    func getSnapshot(in context: Context, completion: @escaping (LockNextEntry) -> Void) {
        completion(makeEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LockNextEntry>) -> Void) {
        let entry = makeEntry()
        let next  = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
    private func makeEntry() -> LockNextEntry {
        let flag  = sharedDefaults?.string(forKey: "widget_next_flag") ?? ""
        let days  = sharedDefaults?.integer(forKey: "widget_next_days") ?? -1
        let name  = sharedDefaults?.string(forKey: "widget_next_name") ?? ""
        let title = sharedDefaults?.string(forKey: "widget_next_title") ?? ""
        let isPro = sharedDefaults?.bool(forKey: "widget_is_pro") ?? false
        return LockNextEntry(date: .now, flag: flag.isEmpty ? "✈️" : flag, days: days, name: name, title: title, isPro: isPro)
    }
}

struct LockNextView: View {
    let entry: LockNextEntry
    var body: some View {
        if !entry.isPro {
            Image(systemName: "lock.fill")
                .font(.system(size: 20))
                .containerBackground(.clear, for: .widget)
        } else if entry.days < 0 {
            VStack(spacing: 2) {
                Text("✈️").font(.system(size: 22))
                Text("Sin viaje").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .containerBackground(.clear, for: .widget)
        } else {
            HStack(spacing: 8) {
                Text("🔜").font(.system(size: 30))
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.days == 1 ? "1 día" : "\(entry.days) días")
                        .font(.system(size: 16, weight: .bold))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    // Título del viaje si lo hay; si no, nombre del país (sin bandera).
                    // Fallback final "Próximo viaje" solo si no hay ningún dato.
                    let label: String = {
                        if !entry.title.isEmpty { return entry.title }
                        if !entry.name.isEmpty  { return entry.name }
                        return "Próximo viaje"
                    }()
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .containerBackground(.clear, for: .widget)
        }
    }
}

struct RaskmapLockNextWidget: Widget {
    let kind = "RaskmapLockNext"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LockNextProvider()) { entry in
            LockNextView(entry: entry)
        }
        .configurationDisplayName("Próximo viaje")
        .description("Días hasta el próximo evento.")
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Lock screen encima del reloj (accessoryInline)

struct LockInlineView: View {
    let entry: LockNextEntry
    var body: some View {
        if !entry.isPro {
            Label("Pro", systemImage: "lock.fill")
                .containerBackground(.clear, for: .widget)
        } else if entry.days < 0 {
            Label("Sin próximo viaje", systemImage: "airplane")
                .containerBackground(.clear, for: .widget)
        } else {
            let destination = entry.name.isEmpty ? "próximo viaje" : entry.name
            Text("Quedan \(entry.days) \(entry.days == 1 ? "día" : "días") · \(destination)")
                .containerBackground(.clear, for: .widget)
        }
    }
}

struct RaskmapLockInlineWidget: Widget {
    let kind = "RaskmapLockInline"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LockNextProvider()) { entry in
            LockInlineView(entry: entry)
        }
        .configurationDisplayName("Cuenta atrás viaje")
        .description("Días restantes hasta el próximo viaje, encima del reloj.")
        .supportedFamilies([.accessoryInline])
    }
}

// MARK: - Lock screen: banderas próximos viajes (accessoryRectangular)

struct WatchFlagsEntry: TimelineEntry {
    let date: Date
    let flags: String  // concatenated emoji string, e.g. "🇯🇵🇫🇷🇩🇪"
    let isPro: Bool
}

struct WatchFlagsProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchFlagsEntry {
        WatchFlagsEntry(date: .now, flags: "🇯🇵🇫🇷🇩🇪", isPro: true)
    }
    func getSnapshot(in context: Context, completion: @escaping (WatchFlagsEntry) -> Void) {
        completion(makeEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchFlagsEntry>) -> Void) {
        let entry = makeEntry()
        let next  = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
    private func makeEntry() -> WatchFlagsEntry {
        let flags = sharedDefaults?.string(forKey: "widget_all_flags") ?? ""
        let isPro = sharedDefaults?.bool(forKey: "widget_is_pro") ?? false
        return WatchFlagsEntry(date: .now, flags: flags, isPro: isPro)
    }
}

struct WatchFlagsView: View {
    let entry: WatchFlagsEntry
    var body: some View {
        if !entry.isPro {
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14))
                Text("Pro")
                    .font(.system(size: 13, weight: .medium))
            }
            .containerBackground(.clear, for: .widget)
        } else if entry.flags.isEmpty {
            HStack(spacing: 4) {
                Text("✈️").font(.system(size: 18))
                Text("Sin próximos viajes")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .containerBackground(.clear, for: .widget)
        } else {
            FlagStrip(flags: entry.flags, size: 22, spacing: 5)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
                .containerBackground(.clear, for: .widget)
        }
    }
}

struct RaskmapWatchFlagsWidget: Widget {
    let kind = "RaskmapWatchFlags"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchFlagsProvider()) { entry in
            WatchFlagsView(entry: entry)
        }
        .configurationDisplayName("Próximos viajes")
        .description("Banderas de todos los próximos viajes.")
        .supportedFamilies([.accessoryRectangular])
    }
}

#Preview(as: .systemSmall) {
    RaskmapWidget()
} timeline: {
    RaskmapEntry(
        date: .now, mode: .un, visited: 14,
        visitedUN: 14, visitedUNPlus: 15, visitedAll: 18,
        bgColor: colorFromShared(),
        nextFlag: "🇯🇵", nextDays: 12, nextName: "Tokio", nextTitle: "",
        nextTransport: "✈️",
        nextDateFrom: Calendar.current.date(byAdding: .day, value: 12, to: .now),
        nextBookingRef: "ABC123",
        upcomingFlags: "🇯🇵🇩🇪🇫🇷🇮🇹🇬🇧",
        topVisitedFlags: "🇪🇸🇫🇷🇮🇹🇺🇸🇯🇵"
    )
}

#Preview(as: .systemMedium) {
    RaskmapWidget()
} timeline: {
    RaskmapEntry(
        date: .now, mode: .un, visited: 42,
        visitedUN: 42, visitedUNPlus: 45, visitedAll: 48,
        bgColor: colorFromShared(),
        nextFlag: "🇯🇵", nextDays: 18, nextName: "Tokio", nextTitle: "",
        nextTransport: "✈️",
        nextDateFrom: Calendar.current.date(byAdding: .day, value: 18, to: .now),
        nextBookingRef: "ABC123",
        upcomingFlags: "🇯🇵🇩🇪🇫🇷🇮🇹🇬🇧🇪🇸",
        topVisitedFlags: "🇪🇸🇫🇷🇮🇹🇺🇸🇯🇵"
    )
}

#Preview(as: .systemLarge) {
    RaskmapWidget()
} timeline: {
    RaskmapEntry(
        date: .now, mode: .un, visited: 42,
        visitedUN: 42, visitedUNPlus: 45, visitedAll: 48,
        bgColor: colorFromShared(),
        nextFlag: "🇯🇵", nextDays: 18, nextName: "Tokio", nextTitle: "",
        nextTransport: "✈️",
        nextDateFrom: Calendar.current.date(byAdding: .day, value: 18, to: .now),
        nextBookingRef: "ABC123",
        upcomingFlags: "🇯🇵🇩🇪🇫🇷🇮🇹🇬🇧🇪🇸",
        topVisitedFlags: "🇪🇸🇫🇷🇮🇹🇺🇸🇯🇵🇩🇪🇵🇹🇳🇱"
    )
}
