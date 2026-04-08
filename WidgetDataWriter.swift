//
//  WidgetDataWriter.swift
//  Raskmap  ← target PRINCIPAL
//

import Foundation
import WidgetKit

private let appGroupID = "group.com.jaime.raskmap"

struct WidgetDataWriter {

    static func sync(countries: [Country]) {
        guard let store = UserDefaults(suiteName: appGroupID) else { return }

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
        guard let store = UserDefaults(suiteName: appGroupID) else { return }
        store.set(hex, forKey: "widget_bg_color")
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func syncFontFamily(_ family: String) {
        guard let store = UserDefaults(suiteName: appGroupID) else { return }
        store.set(family, forKey: "appFontFamily")
    }
}
