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

/// Live Activity celebratoria efímera para el desbloqueo de un logro.
/// Dura ~10s y se auto-dismissa. UI: emoji grande + título + descripción.
/// El target del widget también necesita una copia de este struct (sync
/// folder de RaskmapWidget/).
struct RaskmapAchievementAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var emoji: String      // 🏆 🌍 ⭐️ etc.
        var title: String      // "¡Has visitado el mundo entero!"
        var subtitle: String   // "100 países visitados"
    }
}
