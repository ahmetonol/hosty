//
//  HostEntry.swift
//  Hosty
//
//  Created by AHMET ÖNOL on 15.11.2025.
//

import Foundation
import SwiftData

@Model
final class HostEntry {
    var id: UUID
    var ipAddress: String
    var domains: [String] // Artık birden fazla domain olabilir
    var isEnabled: Bool
    var comment: String
    var isSystemEntry: Bool // macOS sistem entry'si mi (localhost, broadcasthost, vb)
    var profile: HostProfile?

    init(ipAddress: String = "", domains: [String] = [], isEnabled: Bool = true, comment: String = "", isSystemEntry: Bool = false) {
        self.id = UUID()
        self.ipAddress = ipAddress
        self.domains = domains
        self.isEnabled = isEnabled
        self.comment = comment
        self.isSystemEntry = isSystemEntry
    }

    var formattedEntry: String {
        let domainsString = domains.joined(separator: " ")
        if comment.isEmpty {
            return isEnabled ? "\(ipAddress)\t\(domainsString)" : "# \(ipAddress)\t\(domainsString)"
        } else {
            return isEnabled ? "\(ipAddress)\t\(domainsString) # \(comment)" : "# \(ipAddress)\t\(domainsString) # \(comment)"
        }
    }
}
