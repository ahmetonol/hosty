//
//
//  HostsManager.swift
//  Hosty
//
//  Created by AHMET ÖNOL on 15.11.2025.
//

import Foundation
import AppKit
import Combine

class HostsManager: ObservableObject {
    static let shared = HostsManager()

    private let hostsFilePath = "/etc/hosts"
    private let backupDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("Hosty")
        .appendingPathComponent("Backups")

    @Published var lastError: String?

    private init() {
        createBackupDirectoryIfNeeded()
    }

    private func createBackupDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: backupDirectory.path) {
            try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        }
    }

    // Read current hosts file
    func readHostsFile() -> String? {
        do {
            let content = try String(contentsOfFile: hostsFilePath, encoding: .utf8)
            return content
        } catch {
            lastError = "Failed to read hosts file: \(error.localizedDescription)"
            return nil
        }
    }

    // Backup current hosts file
    func backupHostsFile() -> Bool {
        guard let content = readHostsFile() else { return false }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let backupFileName = "hosts_backup_\(timestamp).txt"
        let backupURL = backupDirectory.appendingPathComponent(backupFileName)

        do {
            try content.write(to: backupURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            lastError = "Failed to create backup: \(error.localizedDescription)"
            return false
        }
    }

    // Apply profile WITH DNS cache flush
    func applyProfileWithDNSFlush(_ profile: HostProfile, completion: @escaping (Bool, String?) -> Void) {
        print("🔵 Applying profile with DNS flush: \(profile.name)")

        // First, backup current hosts file
        guard backupHostsFile() else {
            print("❌ Backup failed")
            completion(false, "Failed to backup current hosts file")
            return
        }

        print("✅ Backup created")

        let newContent = profile.generateHostsFileContent()
        print("📝 Generated content (\(newContent.count) bytes)")

        // Create temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("hosts_temp_\(UUID().uuidString)")

        do {
            try newContent.write(to: tempURL, atomically: true, encoding: .utf8)
            print("✅ Temp file created at: \(tempURL.path)")
        } catch {
            print("❌ Failed to create temp file: \(error)")
            completion(false, "Failed to create temporary file: \(error.localizedDescription)")
            return
        }

        // Use AppleScript with DNS flush
        let script = """
        do shell script "cp '\(tempURL.path)' '\(hostsFilePath)' && chmod 644 '\(hostsFilePath)' && dscacheutil -flushcache && killall -HUP mDNSResponder" with administrator privileges
        """

        print("🔧 Running AppleScript with DNS flush...")

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)

            if let error = error {
                print("❌ AppleScript error: \(error)")
                completion(false, "Failed to apply profile: \(error[NSAppleScript.errorMessage] ?? "Unknown error")")
            } else {
                print("✅ AppleScript succeeded - hosts file updated and DNS cache flushed")
                completion(true, nil)
            }
        } else {
            print("❌ Failed to create AppleScript")
            completion(false, "Failed to create AppleScript")
        }
    }

    // Apply profile to hosts file with admin privileges (WITHOUT DNS flush)
    func applyProfile(_ profile: HostProfile, completion: @escaping (Bool, String?) -> Void) {
        print("🔵 Applying profile: \(profile.name)")
        
        // First, backup current hosts file
        guard backupHostsFile() else {
            print("❌ Backup failed")
            completion(false, "Failed to backup current hosts file")
            return
        }
        
        print("✅ Backup created")

        let newContent = profile.generateHostsFileContent()
        print("📝 Generated content (\(newContent.count) bytes):")
        print(newContent)

        // Create temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("hosts_temp_\(UUID().uuidString)")

        do {
            try newContent.write(to: tempURL, atomically: true, encoding: .utf8)
            print("✅ Temp file created at: \(tempURL.path)")
        } catch {
            print("❌ Failed to create temp file: \(error)")
            completion(false, "Failed to create temporary file: \(error.localizedDescription)")
            return
        }

        // Use AppleScript to request admin privileges and copy file
        let script = """
        do shell script "cp '\(tempURL.path)' '\(hostsFilePath)' && chmod 644 '\(hostsFilePath)'" with administrator privileges
        """

        print("🔧 Running AppleScript...")

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)

            if let error = error {
                print("❌ AppleScript error: \(error)")
                completion(false, "Failed to apply profile: \(error[NSAppleScript.errorMessage] ?? "Unknown error")")
            } else {
                print("✅ AppleScript succeeded - hosts file updated")
                print("✅ Profile applied successfully")
                print("⚠️  Browser'ları yeniden başlatmanız gerekebilir")
                completion(true, nil)
            }
        } else {
            print("❌ Failed to create AppleScript")
            completion(false, "Failed to create AppleScript")
        }
    }

    // Get list of backups
    func getBackups() -> [URL] {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
            return files.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return date1 > date2
            }
        } catch {
            return []
        }
    }

    // Restore from backup
    func restoreBackup(from url: URL, completion: @escaping (Bool, String?) -> Void) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("hosts_restore_\(UUID().uuidString)")
            try content.write(to: tempURL, atomically: true, encoding: .utf8)

            let script = """
            do shell script "cp '\(tempURL.path)' '\(hostsFilePath)' && chmod 644 '\(hostsFilePath)'" with administrator privileges
            """

            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)

                try? FileManager.default.removeItem(at: tempURL)

                if let error = error {
                    completion(false, "Failed to restore backup: \(error[NSAppleScript.errorMessage] ?? "Unknown error")")
                } else {
                    print("✅ Backup restored")
                    completion(true, nil)
                }
            } else {
                completion(false, "Failed to create AppleScript")
            }
        } catch {
            completion(false, "Failed to read backup file: \(error.localizedDescription)")
        }
    }
}
