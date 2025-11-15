
import SwiftUI
import SwiftData
import Combine

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
        appDelegate.modelContainer = sharedModelContainer
    }

    var body: some Scene {
        MenuBarExtra("Hosty", systemImage: "antenna.radiowaves.left.and.right") {
            MenuBarContentView(
                modelContainer: sharedModelContainer,
                editorWindowState: editorWindowState
            )
        }

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
        let descriptor = FetchDescriptor<HostProfile>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            let allProfiles = try context.fetch(descriptor)
            profiles = Array(allProfiles.prefix(5))
        } catch {
        }
    }

    func requestProfileChange(_ profile: HostProfile) {
        profileToApply = profile
        showingConfirmation = true
    }

    func applyProfile(_ profile: HostProfile) {
        let context = modelContainer.mainContext

        HostsManager.shared.applyProfileWithDNSFlush(profile) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if success {
                    for p in self.profiles {
                        p.isActive = false
                    }

                    profile.isActive = true
                    try? context.save()

                    NotificationCenter.default.post(name: NSNotification.Name("ProfileChanged"), object: nil)
                } else {
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
        if let existingWindow = NSApp.windows.first(where: { window in
            window.identifier?.rawValue.contains("editor") ?? false
        }) {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            openWindow(id: "editor")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
