//
//  AppDelegate.swift
//  Hosty
//
//  Created by AHMET ÖNOL on 15.11.2025.
//

import SwiftUI
import SwiftData
import UserNotifications
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var modelContainer: ModelContainer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 Application did finish launching")

        // Notification izni iste
        requestNotificationPermission()

        // ModelContainer hazır olana kadar bekle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self, let container = self.modelContainer else {
                print("❌ ModelContainer not ready")
                return
            }

            print("✅ ModelContainer ready")

            // Original hosts profilini oluştur
            self.createOriginalHostsProfile(container: container)

            // Aktif profili hosts dosyasından güncelle
            self.syncActiveProfileWithHostsFile(container: container)
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("❌ Notification permission error: \(error)")
            } else {
                print("✅ Notification permission granted: \(granted)")
            }
        }
    }

    private func createOriginalHostsProfile(container: ModelContainer) {
        let context = container.mainContext
        
        // Original Hosts profili var mı kontrol et
        let descriptor = FetchDescriptor<HostProfile>(
            predicate: #Predicate { $0.name == "Original Hosts" }
        )
        
        do {
            let existing = try context.fetch(descriptor)
            if !existing.isEmpty {
                print("✅ Original Hosts profile already exists")
                // Zaten var, ama hiç aktif profil yoksa bunu aktif yap
                let activeDescriptor = FetchDescriptor<HostProfile>(
                    predicate: #Predicate { $0.isActive }
                )
                let activeProfiles = try context.fetch(activeDescriptor)
                
                if activeProfiles.isEmpty, let original = existing.first {
                    original.isActive = true
                    try context.save()
                    print("✅ Original Hosts set as active (no other active profile)")
                }
                return
            }
            
            print("🔧 Creating Original Hosts profile...")
            
            // Hiç aktif profil yoksa, Original Hosts'u aktif yap
            let activeDescriptor = FetchDescriptor<HostProfile>(
                predicate: #Predicate { $0.isActive }
            )
            let hasActiveProfile = !(try context.fetch(activeDescriptor).isEmpty)
            
            let originalProfile = HostProfile(name: "Original Hosts", isActive: !hasActiveProfile)
            
            // Mevcut hosts dosyasını oku
            if let hostsContent = HostsManager.shared.readHostsFile() {
                print("📄 Reading current hosts file...")
                // Hosts dosyasını parse et
                let lines = hostsContent.components(separatedBy: .newlines)
                
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    
                    // Boş satır ise atla
                    if trimmed.isEmpty {
                        continue
                    }
                    
                    // Sadece yorum satırı ise atla
                    if trimmed.hasPrefix("#") {
                        continue
                    }
                    
                    // IP ve domain'i ayır
                    var workingLine = trimmed
                    var comment = ""

                    // Yorum varsa ayır (ama satır başında # varsa yorum satırıdır, zaten yukarıda atlandı)
                    if let commentIndex = trimmed.firstIndex(of: "#") {
                        comment = String(trimmed[commentIndex...])
                            .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                        workingLine = String(trimmed[..<commentIndex])
                            .trimmingCharacters(in: .whitespaces)
                    }

                    // Boşluklara göre böl (tab veya space)
                    let parts = workingLine.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                    guard parts.count >= 2 else {
                        print("⚠️ Skipping invalid line (not enough parts): \(trimmed)")
                        continue
                    }

                    let ipAddress = parts[0]
                    let domains = Array(parts[1...]) // İlk elemandan sonraki tüm elemanlar domain

                    // macOS sistem entry'lerini işaretle
                    let isSystemEntry = (ipAddress == "127.0.0.1" && domains.contains("localhost")) ||
                                       (ipAddress == "255.255.255.255" && domains.contains("broadcasthost")) ||
                                       (ipAddress == "::1" && domains.contains("localhost"))

                    // Tek bir entry oluştur, tüm domainler ile
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
            
            print("✅ Original Hosts profile created with \(originalProfile.entries.count) entries (Active: \(originalProfile.isActive))")
        } catch {
            print("❌ Failed to create Original Hosts profile: \(error)")
        }
    }
    
    private func syncActiveProfileWithHostsFile(container: ModelContainer) {
        let context = container.mainContext

        // Aktif profili bul
        let activeDescriptor = FetchDescriptor<HostProfile>(
            predicate: #Predicate { $0.isActive }
        )

        do {
            let activeProfiles = try context.fetch(activeDescriptor)
            guard let activeProfile = activeProfiles.first else {
                print("ℹ️ No active profile to sync")
                return
            }

            // Original Hosts profilini atlama
            if activeProfile.name == "Original Hosts" {
                print("ℹ️ Active profile is Original Hosts, no sync needed")
                return
            }

            print("🔄 Syncing active profile '\(activeProfile.name)' with hosts file...")

            // Mevcut hosts dosyasını oku
            guard let hostsContent = HostsManager.shared.readHostsFile() else {
                print("❌ Could not read hosts file")
                return
            }

            // Hosts dosyasını parse et
            var hostsEntries: [HostEntry] = []
            let lines = hostsContent.components(separatedBy: .newlines)

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // Boş satır veya sadece yorum ise atla
                if trimmed.isEmpty || trimmed.hasPrefix("#") {
                    continue
                }

                // IP ve domain'i ayır
                var workingLine = trimmed
                var comment = ""

                // Yorum varsa ayır
                if let commentIndex = trimmed.firstIndex(of: "#") {
                    comment = String(trimmed[commentIndex...])
                        .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                    workingLine = String(trimmed[..<commentIndex])
                        .trimmingCharacters(in: .whitespaces)
                }

                // Boşluklara göre böl (tab veya space)
                let parts = workingLine.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                guard parts.count >= 2 else { continue }

                let ipAddress = parts[0]
                let domains = Array(parts[1...]) // İlk elemandan sonraki tüm elemanlar domain

                // macOS sistem entry'lerini işaretle
                let isSystemEntry = (ipAddress == "127.0.0.1" && domains.contains("localhost")) ||
                                   (ipAddress == "255.255.255.255" && domains.contains("broadcasthost")) ||
                                   (ipAddress == "::1" && domains.contains("localhost"))

                // Tek bir entry oluştur, tüm domainler ile
                let entry = HostEntry(
                    ipAddress: ipAddress,
                    domains: domains,
                    isEnabled: true,
                    comment: comment,
                    isSystemEntry: isSystemEntry
                )

                hostsEntries.append(entry)
            }

            // Aktif profildeki mevcut entryleri sil
            for entry in activeProfile.entries {
                context.delete(entry)
            }
            activeProfile.entries.removeAll()

            // Yeni entryleri ekle
            for entry in hostsEntries {
                entry.profile = activeProfile
                activeProfile.entries.append(entry)
                context.insert(entry)
            }

            activeProfile.updatedAt = Date()
            try context.save()

            print("✅ Active profile synced: \(hostsEntries.count) entries")
        } catch {
            print("❌ Failed to sync active profile: \(error)")
        }
    }

    // Removed applicationShouldHandleReopen - not needed for menu bar apps
    // The app runs in the menu bar and doesn't need to reopen windows on dock click
}
