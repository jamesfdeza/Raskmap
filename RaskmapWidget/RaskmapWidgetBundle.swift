//
//  RaskmapWidgetBundle.swift
//  RaskmapWidget
//

import WidgetKit
import SwiftUI

@main
struct RaskmapWidgetBundle: WidgetBundle {
    var body: some Widget {
        RaskmapWidget()
        RaskmapFlightWidget()
        RaskmapLockPctWidget()
        RaskmapLockNextWidget()
        RaskmapLockInlineWidget()
        RaskmapWatchFlagsWidget()
        // RaskmapWidgetControl() — solo iOS 18+. Es un Control Widget
        // (Centro de Control) placeholder de Xcode (Timer ejemplo, sin
        // funcionalidad real Raskmap). Lo dejamos definido en el archivo
        // bajo @available(iOS 18.0, *) por si en el futuro queremos
        // implementar un control de Centro de Control real.
        RaskmapLiveActivity()
        RaskmapAchievementLiveActivity()
    }
}
