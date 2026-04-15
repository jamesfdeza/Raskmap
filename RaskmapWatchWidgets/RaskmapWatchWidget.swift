//
//  RaskmapWatchWidget.swift
//  RaskmapWatchWidgets
//

import WidgetKit
import SwiftUI

private let appGroupID = "group.com.jaime.raskmap"
private var sharedDefaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

// MARK: - Entry

struct WatchEntry: TimelineEntry {
    let date: Date
    let flag: String
    let days: Int
    let tripName: String
    let visitedUN: Int
    let isPro: Bool
}

// MARK: - Provider

struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry {
        WatchEntry(date: .now, flag: "🇯🇵", days: 12, tripName: "Tokio", visitedUN: 42, isPro: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        let entry = makeEntry()
        let next  = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> WatchEntry {
        let flag      = sharedDefaults?.string(forKey: "widget_next_flag") ?? ""
        let days      = sharedDefaults?.integer(forKey: "widget_next_days") ?? -1
        let tripName  = sharedDefaults?.string(forKey: "widget_next_name") ?? ""
        let visitedUN = sharedDefaults?.integer(forKey: "widget_visited_un") ?? 0
        let isPro     = sharedDefaults?.bool(forKey: "widget_is_pro") ?? false
        return WatchEntry(
            date: .now,
            flag: flag.isEmpty ? "✈️" : flag,
            days: days,
            tripName: tripName,
            visitedUN: visitedUN,
            isPro: isPro
        )
    }
}

// MARK: - Circular: próximo viaje (bandera)

struct WatchCircularView: View {
    let entry: WatchEntry

    var body: some View {
        if !entry.isPro {
            Image(systemName: "lock.fill")
                .font(.system(size: 14))
                .containerBackground(.clear, for: .widget)
        } else if entry.days < 0 {
            Text("✈️")
                .font(.system(size: 24))
                .containerBackground(.clear, for: .widget)
        } else {
            ZStack {
                Text(entry.flag)
                    .font(.system(size: 28))
            }
            .containerBackground(.clear, for: .widget)
        }
    }
}

// MARK: - Rectangular: próximo viaje (bandera + días + nombre)

struct WatchRectangularView: View {
    let entry: WatchEntry

    var body: some View {
        if !entry.isPro {
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                Text("Pro")
                    .font(.system(size: 12, weight: .medium))
            }
            .containerBackground(.clear, for: .widget)
        } else if entry.days < 0 {
            HStack(spacing: 6) {
                Text("✈️").font(.system(size: 20))
                Text("Sin viaje")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .containerBackground(.clear, for: .widget)
        } else {
            HStack(spacing: 8) {
                Text(entry.flag)
                    .font(.system(size: 26))
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.days == 1 ? "1 día" : "\(entry.days) días")
                        .font(.system(size: 15, weight: .bold))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    if !entry.tripName.isEmpty {
                        Text(entry.tripName)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Próximo viaje")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .containerBackground(.clear, for: .widget)
        }
    }
}

// MARK: - Circular: países visitados (ONU)

struct WatchCounterView: View {
    let entry: WatchEntry

    var body: some View {
        Gauge(value: Double(entry.visitedUN), in: 0...193) {
            EmptyView()
        } currentValueLabel: {
            Text("\(entry.visitedUN)")
                .font(.system(size: 14, weight: .bold))
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircular)
        .containerBackground(.clear, for: .widget)
    }
}

// MARK: - Widgets

struct RaskmapWatchNextWidget: Widget {
    let kind = "RaskmapWatchNext"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchProvider()) { entry in
            WatchCircularView(entry: entry)
        }
        .configurationDisplayName("Próximo viaje")
        .description("Bandera del próximo destino.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct RaskmapWatchNextRectWidget: Widget {
    let kind = "RaskmapWatchNextRect"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchProvider()) { entry in
            WatchRectangularView(entry: entry)
        }
        .configurationDisplayName("Próximo viaje")
        .description("Bandera, días y nombre del próximo viaje.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct RaskmapWatchCounterWidget: Widget {
    let kind = "RaskmapWatchCounter"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchProvider()) { entry in
            WatchCounterView(entry: entry)
        }
        .configurationDisplayName("Países visitados")
        .description("Contador de países ONU visitados.")
        .supportedFamilies([.accessoryCircular])
    }
}
