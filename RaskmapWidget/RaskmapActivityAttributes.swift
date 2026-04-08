//
//  RaskmapActivityAttributes.swift
//  RaskmapWidget
//

import ActivityKit

struct RaskmapTripAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var flagEmoji: String
        var tripName: String
        var daysRemaining: Int
    }
}
