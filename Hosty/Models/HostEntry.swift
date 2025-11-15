
import Foundation
import SwiftData

@Model
final class HostEntry {
    var id: UUID
    var ipAddress: String
    var domains: [String]
    var isEnabled: Bool
    var comment: String
    var isSystemEntry: Bool
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
