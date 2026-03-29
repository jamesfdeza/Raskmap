//
//  WidgetDataWriter.swift
//  Raskmap  ← target PRINCIPAL
//

import Foundation
import WidgetKit

struct WidgetDataWriter {

    static func sync(countries: [Country]) {
        let store = NSUbiquitousKeyValueStore.default

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
        store.synchronize()

        WidgetCenter.shared.reloadAllTimelines()
    }
}
