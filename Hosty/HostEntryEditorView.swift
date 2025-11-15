
import SwiftUI
import SwiftData

struct HostEntryEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var profile: HostProfile

    @State private var showingAddEntry = false
    @State private var editingEntry: HostEntry?
    @State private var searchText = ""
    @State private var showingApplyConfirmation = false
    @State private var showingActiveProfileChangeConfirmation = false
    @State private var pendingAction: (() -> Void)?
    @FocusState private var isSearchFocused: Bool

    var filteredEntries: [HostEntry] {
        let entries: [HostEntry]
        if searchText.isEmpty {
            entries = profile.entries
        } else {
            entries = profile.entries.filter { entry in
                entry.ipAddress.localizedCaseInsensitiveContains(searchText) ||
                entry.domains.contains(where: { $0.localizedCaseInsensitiveContains(searchText) }) ||
                entry.comment.localizedCaseInsensitiveContains(searchText)
            }
        }

        let systemEntries = entries.filter { $0.isSystemEntry }
        let userEntries = entries.filter { !$0.isSystemEntry }
        return systemEntries + userEntries
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    HStack {
                        Text(profile.name)
                            .font(.title)
                            .fontWeight(.bold)
                    }

                    Text("Last updated: \(profile.updatedAt, format: .dateTime)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !profile.isActive {
                    Button {
                        showingApplyConfirmation = true
                    } label: {
                        Label("Apply Profile", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(profile.entries.isEmpty)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Active")
                    }
                    .font(.callout)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.green, in: Capsule())
                }
            }
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            HStack(spacing: 12) {
                Button {
                    showingAddEntry = true
                } label: {
                    Label("Add Entry", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.primary)
                .disabled(profile.name == "Original Hosts")

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))

                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($isSearchFocused)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(isSearchFocused ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                .frame(width: 220)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.regularMaterial)

            Divider()

            List {
                if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Entries" : "No Results",
                        systemImage: searchText.isEmpty ? "list.bullet" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "Add your first host entry" : "Try a different search term")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredEntries) { entry in
                        HostEntryRow(entry: entry)
                            .onTapGesture(count: 2) {
                                if !entry.isSystemEntry {
                                    editingEntry = entry
                                }
                            }
                            .contextMenu {
                                if !entry.isSystemEntry {
                                    Button {
                                        editingEntry = entry
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }

                                    Button {
                                        toggleEntry(entry)
                                    } label: {
                                        Label(
                                            entry.isEnabled ? "Disable" : "Enable",
                                            systemImage: entry.isEnabled ? "pause.circle" : "play.circle"
                                        )
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        deleteEntry(entry)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                } else {
                                    Text("System Entry (Read-Only)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !entry.isSystemEntry {
                                    Button(role: .destructive) {
                                        deleteEntry(entry)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }

                                    Button {
                                        toggleEntry(entry)
                                    } label: {
                                        Label(
                                            entry.isEnabled ? "Disable" : "Enable",
                                            systemImage: entry.isEnabled ? "pause.circle" : "play.circle"
                                        )
                                    }
                                    .tint(entry.isEnabled ? .orange : .green)
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                if !entry.isSystemEntry {
                                    Button {
                                        editingEntry = entry
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                            }
                    }
                }
            }
            .listStyle(.inset)
        }
        .sheet(isPresented: $showingAddEntry) {
            AddHostEntrySheet(profile: profile, isPresented: $showingAddEntry, onSave: {
                if profile.isActive {
                    pendingAction = {
                        self.applyProfileAndFlushDNS()
                    }
                    showingActiveProfileChangeConfirmation = true
                }
            })
        }
        .sheet(item: $editingEntry) { entry in
            EditHostEntrySheet(entry: entry, isPresented: .init(
                get: { editingEntry != nil },
                set: { if !$0 { editingEntry = nil } }
            ), onSave: {
                if profile.isActive {
                    pendingAction = {
                        self.applyProfileAndFlushDNS()
                    }
                    showingActiveProfileChangeConfirmation = true
                }
            })
        }
        .alert("Apply Profile", isPresented: $showingApplyConfirmation) {
            Button("Cancel", role: .cancel) {
            }
            Button("Apply") {
                applyProfileAndFlushDNS()
            }
        } message: {
            Text("Changes will be applied to hosts file and DNS cache will be cleared. Do you confirm?")
        }
        .alert("Apply Changes to Hosts File?", isPresented: $showingActiveProfileChangeConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
            Button("Apply") {
                pendingAction?()
                pendingAction = nil
            }
        } message: {
            Text("This will update the system hosts file and clear DNS cache. Do you want to apply?")
        }
    }

    private func toggleEntry(_ entry: HostEntry) {
        if profile.isActive {
            pendingAction = {
                withAnimation {
                    entry.isEnabled.toggle()
                    self.profile.updatedAt = Date()
                    try? self.modelContext.save()
                }
                self.applyProfileAndFlushDNS()
            }
            showingActiveProfileChangeConfirmation = true
        } else {
            withAnimation {
                entry.isEnabled.toggle()
                profile.updatedAt = Date()
                try? modelContext.save()
            }
        }
    }

    private func deleteEntry(_ entry: HostEntry) {
        if profile.isActive {
            pendingAction = {
                withAnimation {
                    self.modelContext.delete(entry)
                    self.profile.updatedAt = Date()
                    try? self.modelContext.save()
                }
                self.applyProfileAndFlushDNS()
            }
            showingActiveProfileChangeConfirmation = true
        } else {
            withAnimation {
                modelContext.delete(entry)
                profile.updatedAt = Date()
                try? modelContext.save()
            }
        }
    }

    private func applyProfileAndFlushDNS() {
        let context = modelContext

        HostsManager.shared.applyProfileWithDNSFlush(profile) { success, error in
            DispatchQueue.main.async {
                if success {
                    let descriptor = FetchDescriptor<HostProfile>()

                    do {
                        let allProfiles = try context.fetch(descriptor)
                        for p in allProfiles {
                            p.isActive = false
                        }

                        self.profile.isActive = true
                        try context.save()

                        self.syncSystemEntriesFromHostsFile()

                        NotificationCenter.default.post(name: NSNotification.Name("ProfileChanged"), object: nil)
                    } catch {
                    }
                } else {
                }
            }
        }
    }

    private func syncSystemEntriesFromHostsFile() {
        let existingSystemEntries = profile.entries.filter { $0.isSystemEntry }
        for entry in existingSystemEntries {
            modelContext.delete(entry)
        }

        guard let hostsContent = HostsManager.shared.readHostsFile() else {
            return
        }

        let lines = hostsContent.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            let parts = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }

            let ipAddress = parts[0]
            let domains = Array(parts[1...])

            let isSystemEntry = (ipAddress == "127.0.0.1" && domains.contains("localhost")) ||
                               (ipAddress == "255.255.255.255" && domains.contains("broadcasthost")) ||
                               (ipAddress == "::1" && domains.contains("localhost"))

            if isSystemEntry {
                let entry = HostEntry(
                    ipAddress: ipAddress,
                    domains: domains,
                    isEnabled: true,
                    comment: "",
                    isSystemEntry: true
                )
                entry.profile = profile
                profile.entries.append(entry)
                modelContext.insert(entry)
            }
        }

        profile.updatedAt = Date()
        try? modelContext.save()
    }
}

struct HostEntryRow: View {
    let entry: HostEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isEnabled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(entry.isEnabled ? .green : .secondary)

            Text(entry.ipAddress)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(entry.isSystemEntry ? .secondary : (entry.isEnabled ? .primary : .secondary))
                .frame(width: 140, alignment: .leading)

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
                .font(.caption)

            Text(entry.domains.joined(separator: " "))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(entry.isSystemEntry ? .secondary : (entry.isEnabled ? .primary : .secondary))
                .lineLimit(1)

            Spacer()

            if entry.isSystemEntry {
                Text("System")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }

            if !entry.comment.isEmpty {
                Text(entry.comment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .opacity(entry.isSystemEntry ? 0.7 : (entry.isEnabled ? 1.0 : 0.6))
    }
}

struct AddHostEntrySheet: View {
    @Environment(\.modelContext) private var modelContext
    let profile: HostProfile
    @Binding var isPresented: Bool
    var onSave: (() -> Void)? = nil

    @State private var ipAddress = ""
    @State private var domains: [String] = []
    @State private var newDomain = ""
    @State private var comment = ""
    @State private var isEnabled = true

    @FocusState private var focusedField: Field?

    enum Field {
        case ipAddress, newDomain, comment
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("IP Address", text: $ipAddress)
                    .focused($focusedField, equals: .ipAddress)

                Section("Domains") {
                    HStack {
                        TextField("Add domain", text: $newDomain)
                            .focused($focusedField, equals: .newDomain)
                            .onSubmit {
                                addDomain()
                            }

                        Button(action: addDomain) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if !domains.isEmpty {
                        ForEach(domains, id: \.self) { domain in
                            HStack {
                                Text(domain)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Button(action: {
                                    removeDomain(domain)
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                TextField("Comment (Optional)", text: $comment)
                    .focused($focusedField, equals: .comment)

                Toggle("Enabled", isOn: $isEnabled)
            }
            .formStyle(.grouped)
            .navigationTitle("New Host Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addEntry()
                    }
                    .disabled(!isValidEntry)
                }
            }
        }
        .frame(width: 450, height: 400)
        .onAppear {
            focusedField = .ipAddress
        }
    }

    private func addDomain() {
        let trimmedDomain = newDomain.trimmingCharacters(in: .whitespaces)
        guard !trimmedDomain.isEmpty, !domains.contains(trimmedDomain) else { return }

        domains.append(trimmedDomain)
        newDomain = ""
        focusedField = .newDomain
    }

    private func removeDomain(_ domain: String) {
        domains.removeAll { $0 == domain }
    }

    private var isValidEntry: Bool {
        !ipAddress.trimmingCharacters(in: .whitespaces).isEmpty &&
        !domains.isEmpty
    }

    private func addEntry() {
        let entry = HostEntry(
            ipAddress: ipAddress.trimmingCharacters(in: .whitespaces),
            domains: domains,
            isEnabled: isEnabled,
            comment: comment.trimmingCharacters(in: .whitespaces)
        )

        entry.profile = profile
        profile.entries.append(entry)
        profile.updatedAt = Date()

        modelContext.insert(entry)
        try? modelContext.save()

        isPresented = false

        onSave?()
    }
}

struct EditHostEntrySheet: View {
    @Environment(\.modelContext) private var modelContext
    let entry: HostEntry
    @Binding var isPresented: Bool
    var onSave: (() -> Void)? = nil

    @State private var ipAddress = ""
    @State private var domains: [String] = []
    @State private var comment = ""
    @State private var isEnabled = true
    @State private var newDomain = ""
    @FocusState private var focusedField: Field?

    enum Field {
        case ipAddress, newDomain, comment
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("IP Address", text: $ipAddress)
                    .focused($focusedField, equals: .ipAddress)

                Section("Domains") {
                    HStack {
                        TextField("Add domain", text: $newDomain)
                            .focused($focusedField, equals: .newDomain)
                            .onSubmit {
                                addDomain()
                            }

                        Button(action: addDomain) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if !domains.isEmpty {
                        ForEach(domains, id: \.self) { domain in
                            HStack {
                                Text(domain)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Button(action: {
                                    removeDomain(domain)
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                TextField("Comment (Optional)", text: $comment)
                    .focused($focusedField, equals: .comment)

                Toggle("Enabled", isOn: $isEnabled)
            }
            .formStyle(.grouped)
            .frame(width: 500, height: 400)
            .navigationTitle("Edit Host Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEntry()
                    }
                    .disabled(!isValidEntry)
                }
            }
        }
        .onAppear {
            ipAddress = entry.ipAddress
            domains = entry.domains
            comment = entry.comment
            isEnabled = entry.isEnabled
        }
    }

    private func addDomain() {
        let trimmedDomain = newDomain.trimmingCharacters(in: .whitespaces)
        guard !trimmedDomain.isEmpty, !domains.contains(trimmedDomain) else { return }

        domains.append(trimmedDomain)
        newDomain = ""
        focusedField = .newDomain
    }

    private func removeDomain(_ domain: String) {
        domains.removeAll { $0 == domain }
    }

    private var isValidEntry: Bool {
        !ipAddress.trimmingCharacters(in: .whitespaces).isEmpty &&
        !domains.isEmpty
    }

    private func saveEntry() {
        entry.ipAddress = ipAddress.trimmingCharacters(in: .whitespaces)
        entry.domains = domains
        entry.comment = comment.trimmingCharacters(in: .whitespaces)
        entry.isEnabled = isEnabled

        if let profile = entry.profile {
            profile.updatedAt = Date()
        }
        try? modelContext.save()
        isPresented = false

        onSave?()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: HostProfile.self, HostEntry.self, configurations: config)

    let profile = HostProfile(name: "Development")
    let entry1 = HostEntry(ipAddress: "127.0.0.1", domains: ["localhost.dev", "app.local"], comment: "Local development")
    let entry2 = HostEntry(ipAddress: "192.168.1.100", domains: ["api.local", "staging.local"], isEnabled: false, comment: "Test API")

    entry1.profile = profile
    entry2.profile = profile
    profile.entries = [entry1, entry2]

    container.mainContext.insert(profile)

    return HostEntryEditorView(profile: profile)
        .modelContainer(container)
}
