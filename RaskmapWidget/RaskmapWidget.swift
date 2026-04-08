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
    let mode: WCountingMode
    let visited: Int
    let bgColor: Color
}

// MARK: - Provider

struct RaskmapProvider: AppIntentTimelineProvider {
    typealias Intent = RaskmapIntent
    typealias Entry  = RaskmapEntry

    func placeholder(in context: Context) -> RaskmapEntry {
        RaskmapEntry(date: .now, mode: .un, visited: 42, bgColor: colorFromShared())
    }

    func snapshot(for configuration: RaskmapIntent, in context: Context) async -> RaskmapEntry {
        makeEntry(configuration)
    }

    func timeline(for configuration: RaskmapIntent, in context: Context) async -> Timeline<RaskmapEntry> {
        let entry = makeEntry(configuration)
        let next  = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func makeEntry(_ configuration: RaskmapIntent) -> RaskmapEntry {
        let mode = WCountingMode(rawValue: configuration.mode.rawValue) ?? .un
        let visited = intFromShared("widget_visited_\(mode.rawValue)")
        return RaskmapEntry(date: .now, mode: mode, visited: visited, bgColor: colorFromShared())
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

// MARK: - View

struct RaskmapWidgetView: View {
    let entry: RaskmapEntry

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("\(entry.visited)")
                .font(.custom("Palatino-Bold", size: 56))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Spacer().frame(height: 4)
            Text(entry.mode.visitedLabel)
                .font(.custom("Palatino", size: 12))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .lineLimit(2)
            Spacer()
            Text(entry.mode.label)
                .font(.custom("Palatino", size: 10))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 14)
        .containerBackground(entry.bgColor, for: .widget)
    }
}

// MARK: - Widget

struct RaskmapWidget: Widget {
    let kind = "RaskmapWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: RaskmapIntent.self,
            provider: RaskmapProvider()
        ) { entry in
            RaskmapWidgetView(entry: entry)
        }
        .configurationDisplayName("Raskmap")
        .description("Países o territorios visitados.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    RaskmapWidget()
} timeline: {
    RaskmapEntry(date: .now, mode: .un,     visited: 14, bgColor: colorFromShared())
    RaskmapEntry(date: .now, mode: .unPlus, visited: 15, bgColor: colorFromShared())
    RaskmapEntry(date: .now, mode: .all,    visited: 18, bgColor: colorFromShared())
}
