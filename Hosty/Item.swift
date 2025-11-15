//
//  Item.swift
//  Hosty
//
//  Created by AHMET ÖNOL on 15.11.2025.
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
