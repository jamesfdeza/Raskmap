//
//  RaskmapActivityAttributes.swift
//  RaskmapWidget
//

import ActivityKit
import Foundation

struct RaskmapTripAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var flagEmoji: String
        var tripName: String
        var daysRemaining: Int
        var transportEmoji: String
        var tripStartDate: Date?
    }
}
