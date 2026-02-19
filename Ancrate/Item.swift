//
//  Item.swift
//  NotesToDo
//
//  Created by Volodymyr Boichentsov on 20/10/2025.
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
