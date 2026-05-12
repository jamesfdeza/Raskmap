//
//  RaskmapLiveActivity.swift
//  RaskmapWidget
//

import ActivityKit
import WidgetKit
import SwiftUI

private let accent      = Color(red: 64/255,  green: 114/255, blue: 212/255)
private let accentSoft  = Color(red: 120/255, green: 156/255, blue: 224/255)

private let darkBg = LinearGradient(
    colors: [
        Color(red: 0.05, green: 0.07, blue: 0.14),
        Color(red: 0.08, green: 0.10, blue: 0.22)
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

// MARK: - Widget

struct RaskmapLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RaskmapTripAttributes.self) { context in

            // MARK: Lock screen / notification banner — estilo boarding pass
            HStack(alignment: .center, spacing: 0) {

                // Left block — flag + name
                HStack(spacing: 12) {
                    FlagLabel(emoji: context.state.flagEmoji, size: 40)
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text("PRÓXIMO VIAJE")
                                .font(.custom("Satoshi-Bold", size: 9))
                                .tracking(1.8)
                                .foregroundStyle(accent)
                            Text(context.state.transportEmoji)
                                .font(.system(size: 10))
                                .opacity(0.75)
                        }
                        Text(context.state.tripName)
                            .font(.custom("Satoshi-Bold", size: 17))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .padding(.leading, 18)

                Spacer(minLength: 10)

                // Vertical separator + countdown en días (mostrar siempre
                // daysRemaining estático). Antes usábamos
                // Text(timerInterval:countsDown:) pero eso renderiza HH:MM:SS;
                // el usuario quiere días que faltan, no horas.
                HStack(spacing: 14) {
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 0.5, height: 40)

                    VStack(alignment: .center, spacing: 0) {
                        Text("\(context.state.daysRemaining)")
                            .font(.custom("Satoshi-Bold", size: 34))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text(context.state.daysRemaining == 1 ? "DÍA" : "DÍAS")
                            .font(.custom("Satoshi-Bold", size: 9))
                            .tracking(1.6)
                            .foregroundStyle(accent)
                    }
                }
                .padding(.trailing, 20)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .containerBackground(darkBg, for: .widget)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 10) {
                        FlagLabel(emoji: context.state.flagEmoji, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("PRÓXIMO")
                                .font(.custom("Satoshi-Bold", size: 8))
                                .tracking(1.4)
                                .foregroundStyle(accent)
                            Text(context.state.transportEmoji)
                                .font(.system(size: 14))
                                .opacity(0.8)
                        }
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(context.state.daysRemaining)")
                            .font(.custom("Satoshi-Bold", size: 30))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text(context.state.daysRemaining == 1 ? "DÍA" : "DÍAS")
                            .font(.custom("Satoshi-Bold", size: 9))
                            .tracking(1.5)
                            .foregroundStyle(accent)
                    }
                    .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.tripName)
                        .font(.custom("Satoshi-Bold", size: 14))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            } compactLeading: {
                FlagLabel(emoji: context.state.flagEmoji, size: 16)
            } compactTrailing: {
                let days = context.state.daysRemaining
                Text(days > 99 ? "+\(days / 30)m" : "\(days)d")
                    .font(.custom("Satoshi-Bold", size: 13))
                    .foregroundStyle(accent)
                    .monospacedDigit()
            } minimal: {
                FlagLabel(emoji: context.state.flagEmoji, size: 16)
            }
        }
    }
}

// MARK: - Live Activity celebratoria para logros desbloqueados

private let achievementGoldBg = LinearGradient(
    colors: [
        Color(red: 0.95, green: 0.75, blue: 0.30),  // dorado
        Color(red: 0.85, green: 0.55, blue: 0.18)   // ámbar oscuro
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

struct RaskmapAchievementLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RaskmapAchievementAttributes.self) { context in
            // Lock screen / notification banner — premio centrado
            HStack(spacing: 14) {
                Text(context.state.emoji)
                    .font(.system(size: 44))
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("LOGRO DESBLOQUEADO")
                        .font(.custom("Satoshi-Bold", size: 9))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(context.state.title)
                        .font(.custom("Satoshi-Bold", size: 18))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if !context.state.subtitle.isEmpty {
                        Text(context.state.subtitle)
                            .font(.custom("Satoshi-Regular", size: 13))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .containerBackground(achievementGoldBg, for: .widget)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.emoji)
                        .font(.system(size: 36))
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("LOGRO")
                        .font(.custom("Satoshi-Bold", size: 9))
                        .tracking(1.4)
                        .foregroundStyle(.orange)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.title)
                            .font(.custom("Satoshi-Bold", size: 14))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if !context.state.subtitle.isEmpty {
                            Text(context.state.subtitle)
                                .font(.custom("Satoshi-Regular", size: 11))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                Text(context.state.emoji).font(.system(size: 16))
            } compactTrailing: {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            } minimal: {
                Text(context.state.emoji).font(.system(size: 14))
            }
        }
    }
}
