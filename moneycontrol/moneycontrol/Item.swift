//
//  Item.swift
//  moneycontrol
//
//  Created by Artur Kolynets on 01.12.2025.
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
