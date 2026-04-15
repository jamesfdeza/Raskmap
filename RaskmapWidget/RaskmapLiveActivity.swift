//
//  RaskmapLiveActivity.swift
//  RaskmapWidget
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Helpers

private func liveActivityFont(size: CGFloat, bold: Bool) -> Font {
    return .system(size: size, weight: bold ? .bold : .regular)
}


// MARK: - Widget

struct RaskmapLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RaskmapTripAttributes.self) { context in
            HStack(spacing: 0) {
                Text(context.state.flagEmoji)
                    .font(.system(size: 40))
                    .frame(width: 64)
                    .padding(.leading, 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.tripName)
                        .font(liveActivityFont(size: 14, bold: true))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("Quedan \(context.state.daysRemaining) \(context.state.daysRemaining == 1 ? "día" : "días")")
                        .font(liveActivityFont(size: 18, bold: true))
                        .foregroundStyle(.white)
                }
                .padding(.leading, 8)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .containerBackground(
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.06, blue: 0.20), Color(red: 0.93, green: 0.43, blue: 0.49)],
                    startPoint: .leading, endPoint: .trailing
                ),
                for: .widget
            )
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
                            .font(.system(size: 30, weight: .bold))
                            .monospacedDigit()
                        Text(context.state.daysRemaining == 1 ? "día" : "días")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.tripName)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Próximo viaje")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Text(context.state.flagEmoji)
                    .font(.system(size: 16))
            } compactTrailing: {
                let days = context.state.daysRemaining
                Text(days > 99 ? "+\(days / 30)m" : "\(days)d")
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
            } minimal: {
                Text(context.state.flagEmoji)
                    .font(.system(size: 16))
            }
        }
    }
}
