//
//  RaskmapActivityAttributes.swift
//  Raskmap
//

import ActivityKit
import Foundation

struct RaskmapTripAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var flagEmoji: String
        var tripName: String
        var daysRemaining: Int
        var transportEmoji: String
        /// Fecha objetivo del viaje. Si está presente, la Live Activity puede
        /// renderizar `Text(timerInterval:)` para que la cuenta atrás
        /// retropulsée sin necesidad de updates push del cliente.
        var tripStartDate: Date?
    }
}
