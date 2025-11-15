
import SwiftUI
import SwiftData

struct SettingsContentView: View {
    enum SettingsPage: String, CaseIterable {
        case general = "General"
        case backups = "Backups"
        case about = "About"

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .backups: return "clock.arrow.circlepath"
            case .about: return "info.circle"
            }
        }
    }

    @State private var selectedPage: SettingsPage = .general

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsPage.allCases, id: \.self, selection: $selectedPage) { page in
                Label(page.rawValue, systemImage: page.icon)
                    .tag(page)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 180, max: 180)
        } detail: {
            switch selectedPage {
            case .general:
                GeneralPreferencesView()
            case .backups:
                BackupPreferencesView()
            case .about:
                AboutPreferencesView()
            }
        }
        .frame(width: 700, height: 500)
    }
}

struct GeneralPreferencesView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showNotifications") private var showNotifications = true
    @AppStorage("autoBackup") private var autoBackup = true

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                Toggle("Show notifications", isOn: $showNotifications)
                Toggle("Auto backup before applying profile", isOn: $autoBackup)
            } header: {
                Text("General")
            }
        }
        .formStyle(.grouped)
        .scenePadding()
        .frame(width: 500)
        .navigationTitle("General")
    }
}

struct BackupPreferencesView: View {
    @StateObject private var hostsManager = HostsManager.shared
    @State private var backups: [URL] = []
    @State private var showingRestoreAlert = false
    @State private var backupToRestore: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Backup History")
                .font(.headline)

            if backups.isEmpty {
                ContentUnavailableView(
                    "No Backups",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Backups are automatically created when you apply a profile")
                )
            } else {
                List {
                    ForEach(backups, id: \.self) { backup in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(backup.lastPathComponent)
                                    .font(.system(.body, design: .monospaced))

                                if let date = getBackupDate(from: backup) {
                                    Text(date, format: .dateTime)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Button("Restore") {
                                backupToRestore = backup
                                showingRestoreAlert = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .listStyle(.inset)
            }

            HStack {
                Button("Create Backup Now") {
                    createBackup()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Refresh") {
                    loadBackups()
                }
                .buttonStyle(.borderless)
            }
        }
        .scenePadding()
        .frame(width: 500)
        .navigationTitle("Backups")
        .onAppear {
            loadBackups()
        }
        .alert("Restore Backup", isPresented: $showingRestoreAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Restore", role: .destructive) {
                if let backup = backupToRestore {
                    restoreBackup(backup)
                }
            }
        } message: {
            Text("This will replace your current hosts file with the selected backup. Your current hosts file will be backed up first.")
        }
    }

    private func loadBackups() {
        backups = hostsManager.getBackups()
    }

    private func createBackup() {
        if hostsManager.backupHostsFile() {
            loadBackups()

            let notification = NSUserNotification()
            notification.title = "Backup Created"
            notification.informativeText = "Hosts file backed up successfully."
            NSUserNotificationCenter.default.deliver(notification)
        }
    }

    private func restoreBackup(_ url: URL) {
        hostsManager.restoreBackup(from: url) { success, error in
            DispatchQueue.main.async {
                let notification = NSUserNotification()
                if success {
                    notification.title = "Backup Restored"
                    notification.informativeText = "Hosts file has been restored successfully."
                } else {
                    notification.title = "Restore Failed"
                    notification.informativeText = error ?? "Unknown error"
                }
                NSUserNotificationCenter.default.deliver(notification)

                loadBackups()
            }
        }
    }

    private func getBackupDate(from url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
    }
}

struct AboutPreferencesView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Hosty")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Version 1.0.0")
                .foregroundStyle(.secondary)

            Text("macOS Host File Manager")
                .font(.headline)

            Spacer()
        }
        .scenePadding()
        .frame(width: 500)
        .navigationTitle("About")
    }
}

#Preview {
    GeneralPreferencesView()
}
