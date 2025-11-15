//
//  HostyApp.swift
//  Hosty
//
//  Created by AHMET ÖNOL on 15.11.2025.
//

import SwiftUI
import SwiftData
import Combine

// Global state for tracking editor window
class EditorWindowState: ObservableObject {
    @Published var isOpen = false
}

@main
struct HostyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var editorWindowState = EditorWindowState()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            HostProfile.self,
            HostEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // ModelContainer'ı HEMEN AppDelegate'e aktar
        appDelegate.modelContainer = sharedModelContainer
        print("✅ ModelContainer set in AppDelegate")
    }

    var body: some Scene {
        // Menu Bar Extra - Modern SwiftUI way for macOS 13+
        MenuBarExtra("Hosty", systemImage: "antenna.radiowaves.left.and.right") {
            MenuBarContentView(
                modelContainer: sharedModelContainer,
                editorWindowState: editorWindowState
            )
        }

        // Editor window
        WindowGroup("Hosty Editor", id: "editor") {
            EditorView()
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    editorWindowState.isOpen = true
                }
                .onDisappear {
                    editorWindowState.isOpen = false
                }
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 900, height: 650)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        // Settings window
        Settings {
            TabView {
                GeneralPreferencesView()
                    .tabItem {
                        Label("General", systemImage: "gearshape")
                    }

                BackupPreferencesView()
                    .tabItem {
                        Label("Backups", systemImage: "clock.arrow.circlepath")
                    }

                AboutPreferencesView()
                    .tabItem {
                        Label("About", systemImage: "info.circle")
                    }
            }
            .padding(20)
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - Menu Bar Content
@MainActor
class MenuBarViewModel: ObservableObject {
    @Published var profiles: [HostProfile] = []
    @Published var showingConfirmation = false
    @Published var profileToApply: HostProfile?

    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        loadProfiles()
    }

    func loadProfiles() {
        let context = modelContainer.mainContext
        // Sort by updatedAt descending, limit to 5
        let descriptor = FetchDescriptor<HostProfile>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            let allProfiles = try context.fetch(descriptor)
            profiles = Array(allProfiles.prefix(5))
        } catch {
            print("Failed to load profiles: \(error)")
        }
    }

    func requestProfileChange(_ profile: HostProfile) {
        profileToApply = profile
        showingConfirmation = true
    }

    func applyProfile(_ profile: HostProfile) {
        let context = modelContainer.mainContext

        // Apply to hosts first, only update active status if successful
        HostsManager.shared.applyProfileWithDNSFlush(profile) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if success {
                    // Only if hosts file was successfully updated, change active profile
                    for p in self.profiles {
                        p.isActive = false
                    }

                    profile.isActive = true
                    try? context.save()

                    print("✅ Profile activated: \(profile.name)")

                    // Notify AppDelegate to update status item title
                    NotificationCenter.default.post(name: NSNotification.Name("ProfileChanged"), object: nil)
                } else {
                    // Failed - show error if needed
                    print("❌ Failed to apply profile: \(error ?? "Unknown error")")
                }

                self.loadProfiles()
            }
        }
    }
}

struct MenuBarContentView: View {
    @StateObject private var viewModel: MenuBarViewModel
    @ObservedObject var editorWindowState: EditorWindowState
    @Environment(\.openWindow) private var openWindow

    init(modelContainer: ModelContainer, editorWindowState: EditorWindowState) {
        _viewModel = StateObject(wrappedValue: MenuBarViewModel(modelContainer: modelContainer))
        self.editorWindowState = editorWindowState
    }

    var body: some View {
        Group {
            // Recent Profiles Header
            Text("Recent Profiles")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            ForEach(viewModel.profiles) { profile in
                Button(action: {
                    viewModel.requestProfileChange(profile)
                }) {
                    HStack {
                        Text(profile.name)
                        if profile.isActive {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .disabled(profile.isActive)
            }

            Divider()

            Button("Open Editor") {
                openEditor()
            }
            .disabled(editorWindowState.isOpen)

            SettingsLink {
                Text("Preferences...")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit Hosty") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .onChange(of: viewModel.showingConfirmation) { _, isShowing in
            if isShowing {
                showConfirmationDialog()
            }
        }
    }

    private func showConfirmationDialog() {
        guard let profile = viewModel.profileToApply else { return }

        let alert = NSAlert()
        alert.messageText = "Apply Profile"
        alert.informativeText = "Changes will be applied to hosts file and DNS cache will be cleared. Do you confirm?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            viewModel.applyProfile(profile)
        }

        viewModel.showingConfirmation = false
        viewModel.profileToApply = nil
    }

    private func openEditor() {
        // First check if editor window already exists (don't check visibility)
        if let existingWindow = NSApp.windows.first(where: { window in
            window.identifier?.rawValue.contains("editor") ?? false
        }) {
            // Window exists, just bring it to front
            print("✅ Found existing editor, bringing to front")
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // No window exists, open new one
            print("🆕 Opening new editor window")
            openWindow(id: "editor")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
