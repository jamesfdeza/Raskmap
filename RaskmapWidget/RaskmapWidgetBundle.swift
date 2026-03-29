//
//  RaskmapWidgetBundle.swift
//  RaskmapWidget
//
//  Created by Jaime Fernández Arenas on 13/3/26.
//

import WidgetKit
import SwiftUI

@main
struct RaskmapWidgetBundle: WidgetBundle {
    var body: some Widget {
        RaskmapWidget()
        RaskmapWidgetControl()
    }
}
