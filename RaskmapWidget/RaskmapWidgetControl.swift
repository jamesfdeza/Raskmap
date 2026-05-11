//
//  RaskmapWidgetControl.swift
//  RaskmapWidget
//
//  Created by Jaime Fernández Arenas on 13/3/26.
//
//  ⚠️ Placeholder de Xcode (Control Widget de Centro de Control con un Timer
//  de ejemplo). NO está añadido al WidgetBundle por ahora porque la API
//  `ControlWidget` requiere iOS 18.0+, y nuestro deployment target es 17.0.
//
//  Si en el futuro quieres exponer un control real para Raskmap en el Centro
//  de Control, descomenta `RaskmapWidgetControl()` en RaskmapWidgetBundle.swift
//  y sube el deployment target del widget a iOS 18.0.
//

import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct RaskmapWidgetControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "RealDev.Raskmap.RaskmapWidget",
            provider: Provider()
        ) { value in
            ControlWidgetToggle(
                "Start Timer",
                isOn: value,
                action: StartTimerIntent()
            ) { isRunning in
                Label(isRunning ? "On" : "Off", systemImage: "timer")
            }
        }
        .displayName("Timer")
        .description("A an example control that runs a timer.")
    }
}

@available(iOS 18.0, *)
extension RaskmapWidgetControl {
    struct Provider: ControlValueProvider {
        var previewValue: Bool {
            false
        }

        func currentValue() async throws -> Bool {
            let isRunning = true // Check if the timer is running
            return isRunning
        }
    }
}

@available(iOS 18.0, *)
struct StartTimerIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Start a timer"

    @Parameter(title: "Timer is running")
    var value: Bool

    func perform() async throws -> some IntentResult {
        // Start / stop the timer based on `value`.
        return .result()
    }
}
