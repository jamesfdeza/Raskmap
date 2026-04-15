//
//  WidgetDataWriter.swift
//  Raskmap  ← target PRINCIPAL
//

import Foundation
import WidgetKit

private let appGroupID = "group.com.jaime.raskmap"

struct WidgetDataWriter {

    private static let store: UserDefaults? = UserDefaults(suiteName: appGroupID)

    static func sync(countries: [Country]) {
        guard let store else { return }

        let visitedIsoCodes = Set(countries
            .filter { $0.status == .visited || $0.status == .lived }
            .map { $0.isoCode })

        let un = visitedIsoCodes.filter {
            CountingMode.unMembers.contains($0)
        }.count

        let unPlus = visitedIsoCodes.filter {
            CountingMode.unMembers.contains($0) || CountingMode.unObservers.contains($0)
        }.count

        let all = visitedIsoCodes.count

        store.set(un,     forKey: "widget_visited_un")
        store.set(unPlus, forKey: "widget_visited_unPlus")
        store.set(all,    forKey: "widget_visited_all")

        WidgetCenter.shared.reloadAllTimelines()
    }

    static func syncColor(hex: String) {
        guard let store else { return }
        store.set(hex, forKey: "widget_bg_color")
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func syncNextTrip(flag: String?, days: Int?, name: String? = nil,
                             transport: String? = nil, dateFrom: Date? = nil,
                             bookingRef: String? = nil, title: String? = nil) {
        guard let store else { return }
        store.set(flag ?? "", forKey: "widget_next_flag")
        store.set(days ?? -1, forKey: "widget_next_days")
        store.set(name ?? "", forKey: "widget_next_name")
        store.set(transport ?? "", forKey: "widget_next_transport")
        store.set(bookingRef ?? "", forKey: "widget_next_booking")
        store.set(title ?? "", forKey: "widget_next_title")
        if let d = dateFrom {
            store.set(d.timeIntervalSince1970, forKey: "widget_next_date")
        } else {
            store.removeObject(forKey: "widget_next_date")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func syncFontFamily(_ family: String) {
        guard let store else { return }
        store.set(family, forKey: "appFontFamily")
    }

    static func syncPro(_ isPro: Bool) {
        guard let store else { return }
        store.set(isPro, forKey: "widget_is_pro")
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func syncCountingMode(_ mode: String) {
        guard let store else { return }
        store.set(mode, forKey: "widget_counting_mode")
    }

    static func syncAllFlags(_ flags: String) {
        guard let store else { return }
        store.set(flags, forKey: "widget_all_flags")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
