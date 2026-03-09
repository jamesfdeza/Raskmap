//
//  Item.swift
//  Raskmap
//
//  Created by Jaime Fernández Arenas on 9/3/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
