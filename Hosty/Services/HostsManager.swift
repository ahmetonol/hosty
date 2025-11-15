
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

    func readHostsFile() -> String? {
        do {
            let content = try String(contentsOfFile: hostsFilePath, encoding: .utf8)
            return content
        } catch {
            lastError = "Failed to read hosts file: \(error.localizedDescription)"
            return nil
        }
    }

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

    func applyProfileWithDNSFlush(_ profile: HostProfile, completion: @escaping (Bool, String?) -> Void) {

        guard backupHostsFile() else {
            completion(false, "Failed to backup current hosts file")
            return
        }

        let newContent = profile.generateHostsFileContent()

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("hosts_temp_\(UUID().uuidString)")

        do {
            try newContent.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            completion(false, "Failed to create temporary file: \(error.localizedDescription)")
            return
        }

        let script = """
        do shell script "cp '\(tempURL.path)' '\(hostsFilePath)' && chmod 644 '\(hostsFilePath)' && dscacheutil -flushcache && killall -HUP mDNSResponder" with administrator privileges
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)

            try? FileManager.default.removeItem(at: tempURL)

            if let error = error {
                completion(false, "Failed to apply profile: \(error[NSAppleScript.errorMessage] ?? "Unknown error")")
            } else {
                completion(true, nil)
            }
        } else {
            completion(false, "Failed to create AppleScript")
        }
    }

    func applyProfile(_ profile: HostProfile, completion: @escaping (Bool, String?) -> Void) {

        guard backupHostsFile() else {
            completion(false, "Failed to backup current hosts file")
            return
        }

        let newContent = profile.generateHostsFileContent()

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("hosts_temp_\(UUID().uuidString)")

        do {
            try newContent.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            completion(false, "Failed to create temporary file: \(error.localizedDescription)")
            return
        }

        let script = """
        do shell script "cp '\(tempURL.path)' '\(hostsFilePath)' && chmod 644 '\(hostsFilePath)'" with administrator privileges
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)

            try? FileManager.default.removeItem(at: tempURL)

            if let error = error {
                completion(false, "Failed to apply profile: \(error[NSAppleScript.errorMessage] ?? "Unknown error")")
            } else {
                completion(true, nil)
            }
        } else {
            completion(false, "Failed to create AppleScript")
        }
    }

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
