//
//  RaskmapWatchWidgetBundle.swift
//  RaskmapWatchWidgets
//

import WidgetKit
import SwiftUI

@main
struct RaskmapWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        RaskmapWatchNextWidget()
        RaskmapWatchNextRectWidget()
        RaskmapWatchCounterWidget()
    }
}
