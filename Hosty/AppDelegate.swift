
import SwiftUI
import SwiftData
import UserNotifications
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var modelContainer: ModelContainer?

    func applicationDidFinishLaunching(_ notification: Notification) {

        requestNotificationPermission()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self, let container = self.modelContainer else {
                return
            }

            self.createOriginalHostsProfile(container: container)

            self.syncActiveProfileWithHostsFile(container: container)
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
            } else {
            }
        }
    }

    private func createOriginalHostsProfile(container: ModelContainer) {
        let context = container.mainContext

        let descriptor = FetchDescriptor<HostProfile>(
            predicate: #Predicate { $0.name == "Original Hosts" }
        )

        do {
            let existing = try context.fetch(descriptor)
            if !existing.isEmpty {
                let activeDescriptor = FetchDescriptor<HostProfile>(
                    predicate: #Predicate { $0.isActive }
                )
                let activeProfiles = try context.fetch(activeDescriptor)

                if activeProfiles.isEmpty, let original = existing.first {
                    original.isActive = true
                    try context.save()
                }
                return
            }

            let activeDescriptor = FetchDescriptor<HostProfile>(
                predicate: #Predicate { $0.isActive }
            )
            let hasActiveProfile = !(try context.fetch(activeDescriptor).isEmpty)

            let originalProfile = HostProfile(name: "Original Hosts", isActive: !hasActiveProfile)

            if let hostsContent = HostsManager.shared.readHostsFile() {
                let lines = hostsContent.components(separatedBy: .newlines)

                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)

                    if trimmed.isEmpty {
                        continue
                    }

                    if trimmed.hasPrefix("#") {
                        continue
                    }

                    var workingLine = trimmed
                    var comment = ""

                    if let commentIndex = trimmed.firstIndex(of: "#") {
                        comment = String(trimmed[commentIndex...])
                            .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                        workingLine = String(trimmed[..<commentIndex])
                            .trimmingCharacters(in: .whitespaces)
                    }

                    let parts = workingLine.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                    guard parts.count >= 2 else {
                        continue
                    }

                    let ipAddress = parts[0]
                    let domains = Array(parts[1...])

                    let isSystemEntry = (ipAddress == "127.0.0.1" && domains.contains("localhost")) ||
                                       (ipAddress == "255.255.255.255" && domains.contains("broadcasthost")) ||
                                       (ipAddress == "::1" && domains.contains("localhost"))

                    let entry = HostEntry(
                        ipAddress: ipAddress,
                        domains: domains,
                        isEnabled: true,
                        comment: comment,
                        isSystemEntry: isSystemEntry
                    )

                    entry.profile = originalProfile
                    originalProfile.entries.append(entry)
                    context.insert(entry)
                }
            }

            context.insert(originalProfile)
            try context.save()

        } catch {
        }
    }

    private func syncActiveProfileWithHostsFile(container: ModelContainer) {
        let context = container.mainContext

        let activeDescriptor = FetchDescriptor<HostProfile>(
            predicate: #Predicate { $0.isActive }
        )

        do {
            let activeProfiles = try context.fetch(activeDescriptor)
            guard let activeProfile = activeProfiles.first else {
                return
            }

            if activeProfile.name == "Original Hosts" {
                return
            }

            guard let hostsContent = HostsManager.shared.readHostsFile() else {
                return
            }

            var hostsEntries: [HostEntry] = []
            let lines = hostsContent.components(separatedBy: .newlines)

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if trimmed.isEmpty || trimmed.hasPrefix("#") {
                    continue
                }

                var workingLine = trimmed
                var comment = ""

                if let commentIndex = trimmed.firstIndex(of: "#") {
                    comment = String(trimmed[commentIndex...])
                        .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                    workingLine = String(trimmed[..<commentIndex])
                        .trimmingCharacters(in: .whitespaces)
                }

                let parts = workingLine.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                guard parts.count >= 2 else { continue }

                let ipAddress = parts[0]
                let domains = Array(parts[1...])

                let isSystemEntry = (ipAddress == "127.0.0.1" && domains.contains("localhost")) ||
                                   (ipAddress == "255.255.255.255" && domains.contains("broadcasthost")) ||
                                   (ipAddress == "::1" && domains.contains("localhost"))

                let entry = HostEntry(
                    ipAddress: ipAddress,
                    domains: domains,
                    isEnabled: true,
                    comment: comment,
                    isSystemEntry: isSystemEntry
                )

                hostsEntries.append(entry)
            }

            for entry in activeProfile.entries {
                context.delete(entry)
            }
            activeProfile.entries.removeAll()

            for entry in hostsEntries {
                entry.profile = activeProfile
                activeProfile.entries.append(entry)
                context.insert(entry)
            }

            activeProfile.updatedAt = Date()
            try context.save()

        } catch {
        }
    }

}
