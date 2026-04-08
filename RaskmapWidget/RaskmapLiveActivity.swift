//
//  RaskmapLiveActivity.swift
//  RaskmapWidget
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Font helper

private func liveActivityFont(size: CGFloat, bold: Bool) -> Font {
    let family = UserDefaults(suiteName: "group.com.jaime.raskmap")?.string(forKey: "appFontFamily") ?? "satoshi"
    if family == "palatino" {
        return .custom(bold ? "Palatino-Bold" : "Palatino", size: size)
    }
    return .system(size: size, weight: bold ? .bold : .regular)
}

// MARK: - Widget

struct RaskmapLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RaskmapTripAttributes.self) { context in
            HStack(spacing: 12) {
                Text(context.state.flagEmoji)
                    .font(liveActivityFont(size: 32, bold: false))
                Text("Quedan \(context.state.daysRemaining) \(context.state.daysRemaining == 1 ? "día" : "días")")
                    .font(liveActivityFont(size: 17, bold: true))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
            .containerBackground(.clear, for: .widget)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.flagEmoji)
                        .font(.system(size: 40))
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(context.state.daysRemaining)")
                            .font(.custom("Palatino-Bold", size: 30))
                            .monospacedDigit()
                        Text(context.state.daysRemaining == 1 ? "día" : "días")
                            .font(.custom("Palatino", size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.tripName)
                        .font(.custom("Palatino-Bold", size: 14))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Próximo viaje")
                        .font(.custom("Palatino", size: 11))
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Text(context.state.flagEmoji)
                    .font(.system(size: 16))
            } compactTrailing: {
                Text("\(context.state.daysRemaining)d")
                    .font(.custom("Palatino-Bold", size: 13))
                    .monospacedDigit()
            } minimal: {
                Text(context.state.flagEmoji)
                    .font(.system(size: 16))
            }
        }
    }
}
