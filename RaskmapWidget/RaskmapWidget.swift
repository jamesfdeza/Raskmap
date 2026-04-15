//
//  RaskmapWidget.swift
//  RaskmapWidget
//

import WidgetKit
import SwiftUI
import AppIntents

private let appGroupID = "group.com.jaime.raskmap"

private var sharedDefaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

// MARK: - App Group helpers

func intFromShared(_ key: String) -> Int {
    sharedDefaults?.integer(forKey: key) ?? 0
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
}

// MARK: - Intent

enum IntentMode: String, AppEnum {
    case un     = "un"
    case unPlus = "unPlus"
    case all    = "all"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Modo de conteo"
    static var caseDisplayRepresentations: [IntentMode: DisplayRepresentation] = [
        .un:     "ONU (193)",
        .unPlus: "ONU + obs. (195)",
        .all:    "Todos (244)"
    ]
}

struct RaskmapIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Modo de conteo"
    static var description = IntentDescription("Elige qué territorios contar en el widget.")

    @Parameter(title: "Modo", default: .un)
    var mode: IntentMode
}

// MARK: - Entry

struct RaskmapEntry: TimelineEntry {
    let date: Date
    let transport: String   // emoji, "" = no trip
    let tripFlag: String
    let tripName: String
    let tripTitle: String   // custom trip title, "" = use tripName
    let daysRemaining: Int  // -1 = no trip
    let tripDateFrom: Date?
    let bgColor: Color
    let visitedCount: Int      // countries visited (mode from settings)
    let countingMode: WCountingMode
    let upcomingFlags: String  // concatenated flag emojis for upcoming trips
    let bookingRef: String     // localizador vuelo, "" = no disponible
}

// MARK: - Provider

struct RaskmapProvider: TimelineProvider {
    typealias Entry = RaskmapEntry

    func placeholder(in context: Context) -> RaskmapEntry {
        RaskmapEntry(date: .now, transport: "✈️", tripFlag: "🇯🇵",
                     tripName: "Japón", tripTitle: "",
                     daysRemaining: 42,
                     tripDateFrom: Calendar.current.date(byAdding: .day, value: 42, to: .now),
                     bgColor: colorFromShared(),
                     visitedCount: 42, countingMode: .un, upcomingFlags: "🇯🇵🇫🇷🇩🇪",
                     bookingRef: "ABC123")
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
        let flag      = sharedDefaults?.string(forKey: "widget_next_flag") ?? ""
        let days      = sharedDefaults?.integer(forKey: "widget_next_days") ?? -1
        let name      = sharedDefaults?.string(forKey: "widget_next_name") ?? ""
        let transport = sharedDefaults?.string(forKey: "widget_next_transport") ?? ""
        let dateFromTS = sharedDefaults?.double(forKey: "widget_next_date") ?? 0
        let dateFrom: Date? = dateFromTS > 0 ? Date(timeIntervalSince1970: dateFromTS) : nil
        let modeRaw   = sharedDefaults?.string(forKey: "widget_counting_mode") ?? "un"
        let mode      = WCountingMode(rawValue: modeRaw) ?? .un
        let visited   = sharedDefaults?.integer(forKey: "widget_visited_\(mode.rawValue)") ?? 0
        let upcoming  = sharedDefaults?.string(forKey: "widget_all_flags") ?? ""
        let booking   = sharedDefaults?.string(forKey: "widget_next_booking") ?? ""
        let title     = sharedDefaults?.string(forKey: "widget_next_title") ?? ""
        return RaskmapEntry(date: .now,
                            transport: transport.isEmpty ? "✈️" : transport,
                            tripFlag: flag.isEmpty ? "🌍" : flag,
                            tripName: name,
                            tripTitle: title,
                            daysRemaining: days,
                            tripDateFrom: dateFrom,
                            bgColor: colorFromShared(),
                            visitedCount: visited,
                            countingMode: mode,
                            upcomingFlags: upcoming,
                            bookingRef: booking)
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

// MARK: - Days label helper

private func daysLabel(_ days: Int) -> String {
    if days == 1 { return "1 día" }
    if days <= 99 { return "\(days) días" }
    let months = max(1, days / 30)
    return "+\(months) meses"
}

// MARK: - View helpers

private let widgetDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "es_ES")
    f.dateFormat = "EEE, d MMM yyyy"
    return f
}()

private let raskmapBlue = Color(red: 0x53/255.0, green: 0xA3/255.0, blue: 0xFE/255.0)

// MARK: - Small widget

private struct RaskmapSmallView: View {
    let entry: RaskmapEntry

    var body: some View {
        if entry.daysRemaining < 0 {
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
            let displayName = entry.tripTitle.isEmpty ? entry.tripName : entry.tripTitle
            ZStack(alignment: .topLeading) {
                Text(entry.transport)
                    .font(.system(size: 26))
                if !entry.bookingRef.isEmpty {
                    Text("#\(entry.bookingRef)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(entry.tripFlag).font(.system(size: 14))
                        Text(displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(raskmapBlue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Text(daysLabel(entry.daysRemaining))
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if let d = entry.tripDateFrom {
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

// MARK: - Medium widget

private struct RaskmapMediumView: View {
    let entry: RaskmapEntry

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                // Left: transport emoji
                ZStack {
                    if entry.daysRemaining < 0 {
                        Text("✈️").font(.system(size: 40))
                    } else {
                        Text(entry.transport).font(.system(size: 40))
                    }
                }
                .frame(maxHeight: .infinity)
                .frame(width: 70)

                // Divider
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 1)
                    .padding(.vertical, 10)

                // Right: trip info
                if entry.daysRemaining < 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sin próximo viaje")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("Añade un viaje planificado\npara verlo aquí")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.leading, 14)
                } else {
                    let displayName = entry.tripTitle.isEmpty ? entry.tripName : entry.tripTitle
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text(entry.tripFlag).font(.system(size: 18))
                            Text(displayName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(raskmapBlue)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        Text(daysLabel(entry.daysRemaining))
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        if let d = entry.tripDateFrom {
                            Text(widgetDateFormatter.string(from: d))
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.leading, 14)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if entry.daysRemaining >= 0, !entry.bookingRef.isEmpty {
                Text("#\(entry.bookingRef)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .padding(.trailing, 15)
                    .padding(.top, 5)
            }
        }
        .padding(5)
        .containerBackground(entry.bgColor, for: .widget)
    }
}

// MARK: - Large widget

private struct RaskmapLargeView: View {
    let entry: RaskmapEntry

    var body: some View {
        ZStack(alignment: .topTrailing) {
          VStack(alignment: .leading, spacing: 0) {
            // Top: próximo viaje (like small but more room)
            if entry.daysRemaining < 0 {
                HStack(spacing: 10) {
                    Text("✈️").font(.system(size: 36))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sin próximo viaje")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("Añade un viaje planificado")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            } else {
                let displayName = entry.tripTitle.isEmpty ? entry.tripName : entry.tripTitle
                ZStack(alignment: .topLeading) {
                    Text(entry.transport).font(.system(size: 32))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text(entry.tripFlag).font(.system(size: 18))
                            Text(displayName)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(raskmapBlue)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        Text(daysLabel(entry.daysRemaining))
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        if let d = entry.tripDateFrom {
                            Text(widgetDateFormatter.string(from: d))
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 48)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
            }

            // Divider
            Rectangle()
                .fill(.white.opacity(0.25))
                .frame(height: 1)
                .padding(.bottom, 12)

            // Países visitados
            HStack(spacing: 8) {
                Text("🌍")
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entry.visitedCount) \(entry.countingMode == .un ? "países" : "territorios") visitados")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.2))
                                .frame(height: 6)
                            Capsule()
                                .fill(.white.opacity(0.85))
                                .frame(width: geo.size.width * min(Double(entry.visitedCount) / Double(entry.countingMode.total), 1.0), height: 6)
                        }
                    }
                    .frame(height: 6)
                    Text("de \(entry.countingMode.total) \(entry.countingMode.label)")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.bottom, 14)

            // Próximos destinos
            if !entry.upcomingFlags.isEmpty {
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(height: 1)
                    .padding(.bottom, 10)

                Text("Próximos destinos")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 4)

                Text(entry.upcomingFlags)
                    .font(.system(size: 26))
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

          if entry.daysRemaining >= 0, !entry.bookingRef.isEmpty {
              Text("#\(entry.bookingRef)")
                  .font(.system(size: 13, weight: .semibold, design: .monospaced))
                  .foregroundStyle(.white.opacity(0.75))
                  .lineLimit(1)
          }
        }
        .padding(16)
        .containerBackground(entry.bgColor, for: .widget)
    }
}

// MARK: - Main widget dispatcher

struct RaskmapWidgetView: View {
    let entry: RaskmapEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium: RaskmapMediumView(entry: entry)
        case .systemLarge:  RaskmapLargeView(entry: entry)
        default:            RaskmapSmallView(entry: entry)
        }
    }
}

// MARK: - Totales por modo

extension WCountingMode {
    var total: Int {
        switch self {
        case .un:     return 193
        case .unPlus: return 195
        case .all:    return 249
        }
    }
}

// MARK: - Lock screen: porcentaje

struct LockPctEntry: TimelineEntry {
    let date: Date
    let visited: Int
    let total: Int
    let isPro: Bool
    var pct: Double { total > 0 ? Double(visited) / Double(total) * 100.0 : 0.0 }
}

struct LockPctProvider: AppIntentTimelineProvider {
    typealias Intent = RaskmapIntent
    typealias Entry  = LockPctEntry

    func placeholder(in context: Context) -> LockPctEntry {
        LockPctEntry(date: .now, visited: 42, total: 193, isPro: true)
    }
    func snapshot(for configuration: RaskmapIntent, in context: Context) async -> LockPctEntry {
        makeEntry(configuration)
    }
    func timeline(for configuration: RaskmapIntent, in context: Context) async -> Timeline<LockPctEntry> {
        let entry = makeEntry(configuration)
        let next  = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        return Timeline(entries: [entry], policy: .after(next))
    }
    private func makeEntry(_ configuration: RaskmapIntent) -> LockPctEntry {
        let mode    = WCountingMode(rawValue: configuration.mode.rawValue) ?? .un
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
        AppIntentConfiguration(kind: kind, intent: RaskmapIntent.self, provider: LockPctProvider()) { entry in
            LockPctView(entry: entry)
        }
        .configurationDisplayName("% del mundo")
        .description("Porcentaje del mundo visitado.")
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: - Lock screen: próximo viaje

struct LockNextEntry: TimelineEntry {
    let date: Date
    let flag: String
    let days: Int
    let name: String
    let isPro: Bool
}

struct LockNextProvider: TimelineProvider {
    func placeholder(in context: Context) -> LockNextEntry {
        LockNextEntry(date: .now, flag: "🇯🇵", days: 12, name: "Tokio", isPro: true)
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
        let isPro = sharedDefaults?.bool(forKey: "widget_is_pro") ?? false
        return LockNextEntry(date: .now, flag: flag.isEmpty ? "✈️" : flag, days: days, name: name, isPro: isPro)
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
                    Text("Próximo viaje")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
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
        .description("Bandera y días hasta el próximo viaje.")
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Lock screen encima del reloj: inline cuenta atrás

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

// MARK: - Watch/lock screen: todas las banderas próximas

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
            Text(entry.flags)
                .font(.system(size: 22))
                .minimumScaleFactor(0.4)
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

// MARK: - Widget pantalla principal

struct RaskmapWidget: Widget {
    let kind = "RaskmapWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RaskmapProvider()) { entry in
            RaskmapWidgetView(entry: entry)
        }
        .configurationDisplayName("Próximo viaje")
        .description("Días hasta tu próximo viaje planificado.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    RaskmapWidget()
} timeline: {
    RaskmapEntry(date: .now, transport: "✈️", tripFlag: "🇯🇵", tripName: "Japón", tripTitle: "Viaje Tokio",
                 daysRemaining: 42, tripDateFrom: Calendar.current.date(byAdding: .day, value: 42, to: .now),
                 bgColor: colorFromShared(), visitedCount: 42, countingMode: .un, upcomingFlags: "🇯🇵🇫🇷🇩🇪", bookingRef: "ABC123")
    RaskmapEntry(date: .now, transport: "🚂", tripFlag: "🇫🇷", tripName: "Francia", tripTitle: "",
                 daysRemaining: 1, tripDateFrom: Calendar.current.date(byAdding: .day, value: 1, to: .now),
                 bgColor: colorFromShared(), visitedCount: 42, countingMode: .un, upcomingFlags: "🇫🇷🇩🇪", bookingRef: "")
    RaskmapEntry(date: .now, transport: "✈️", tripFlag: "🌍", tripName: "", tripTitle: "",
                 daysRemaining: -1, tripDateFrom: nil,
                 bgColor: colorFromShared(), visitedCount: 42, countingMode: .un, upcomingFlags: "", bookingRef: "")
}

#Preview(as: .systemMedium) {
    RaskmapWidget()
} timeline: {
    RaskmapEntry(date: .now, transport: "✈️", tripFlag: "🇯🇵", tripName: "Japón", tripTitle: "Viaje Tokio",
                 daysRemaining: 42, tripDateFrom: Calendar.current.date(byAdding: .day, value: 42, to: .now),
                 bgColor: colorFromShared(), visitedCount: 42, countingMode: .un, upcomingFlags: "🇯🇵🇫🇷🇩🇪", bookingRef: "ABC123")
}

#Preview(as: .systemLarge) {
    RaskmapWidget()
} timeline: {
    RaskmapEntry(date: .now, transport: "✈️", tripFlag: "🇯🇵", tripName: "Japón", tripTitle: "Viaje Tokio",
                 daysRemaining: 42, tripDateFrom: Calendar.current.date(byAdding: .day, value: 42, to: .now),
                 bgColor: colorFromShared(), visitedCount: 42, countingMode: .un, upcomingFlags: "🇯🇵🇫🇷🇩🇪🇮🇹🇪🇸", bookingRef: "XY7890")
}
