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
        RaskmapWidgetControl()
        RaskmapLiveActivity()
    }
}
