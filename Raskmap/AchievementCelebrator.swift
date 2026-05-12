//
//  AchievementCelebrator.swift
//  Raskmap
//
//  Helper para disparar una Live Activity celebratoria efímera cuando el
//  usuario desbloquea un logro nuevo. La Activity dura ~10s y se
//  auto-dismissa con `dismissalPolicy: .after(...)`.
//
//  Llamada típica desde el flujo de `checkAndShowAchievementToasts()`:
//
//      AchievementCelebrator.celebrate(
//          emoji: "🌍", title: "¡Has visitado el mundo!",
//          subtitle: "193 países ONU"
//      )
//

import ActivityKit
import Foundation

enum AchievementCelebrator {

    /// Lanza una Live Activity celebratoria. No-op si el usuario no tiene
    /// el toggle de Live Activities activado o si Apple aún no autorizó
    /// (los permisos son automáticos en iOS 16.1+ salvo opt-out global).
    @MainActor
    static func celebrate(emoji: String, title: String, subtitle: String = "") {
        // Soporte ActivityKit desde iOS 16.1.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = RaskmapAchievementAttributes()
        let state = RaskmapAchievementAttributes.ContentState(
            emoji: emoji, title: title, subtitle: subtitle
        )
        do {
            let activity = try Activity<RaskmapAchievementAttributes>.request(
                attributes: attrs,
                content: .init(state: state, staleDate: Date().addingTimeInterval(10))
            )
            // Auto-dismiss tras 10s — la Activity desaparece elegantemente
            // sin requerir que el usuario la cierre manualmente.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(10))
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        } catch {
            // Silencioso — si no se puede crear la Activity (cuota, otros
            // motivos), el toast in-app + haptic ya celebran el logro.
            #if DEBUG
            print("⚠️ Achievement LA failed: \(error)")
            #endif
        }
    }
}
