//
//
//  EditorView.swift
//  Hosty
//
//  Created by AHMET ÖNOL on 15.11.2025.
//

import SwiftUI
import SwiftData

struct EditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HostProfile.name) private var profiles: [HostProfile]
    
    @State private var selectedProfile: HostProfile?
    @State private var showingAddProfile = false
    @State private var showingDeleteAlert = false
    @State private var profileToDelete: HostProfile?
    
    var body: some View {
        NavigationSplitView {
            // SIDEBAR - Profil Listesi
            ProfileSidebarView(
                profiles: profiles,
                selectedProfile: $selectedProfile,
                showingAddProfile: $showingAddProfile,
                showingDeleteAlert: $showingDeleteAlert,
                profileToDelete: $profileToDelete
            )
        } detail: {
            // DETAIL - Host Entry Editor
            if let profile = selectedProfile {
                HostEntryEditorView(profile: profile)
            } else {
                ContentUnavailableView(
                    "No Profile Selected",
                    systemImage: "sidebar.left",
                    description: Text("Select a profile from the sidebar to view and edit its host entries")
                )
            }
        }
        .navigationTitle("Hosty")
        .sheet(isPresented: $showingAddProfile) {
            AddProfileSheet(isPresented: $showingAddProfile, onProfileCreated: { newProfile in
                selectedProfile = newProfile
            })
        }
        .alert("Delete Profile", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let profile = profileToDelete {
                    deleteProfile(profile)
                }
            }
        } message: {
            if let profile = profileToDelete {
                Text("Are you sure you want to delete '\(profile.name)'? This action cannot be undone.")
            }
        }
        .onAppear {
            // İlk profili seç
            if selectedProfile == nil, let first = profiles.first {
                selectedProfile = first
            }
        }
    }
    
    private func deleteProfile(_ profile: HostProfile) {
        withAnimation {
            modelContext.delete(profile)
            try? modelContext.save()
            
            // Eğer silinen profil seçiliyse, başka bir profili seç
            if selectedProfile?.id == profile.id {
                selectedProfile = profiles.first
            }
        }
    }
}

// MARK: - Profile Sidebar
struct ProfileSidebarView: View {
    let profiles: [HostProfile]
    @Binding var selectedProfile: HostProfile?
    @Binding var showingAddProfile: Bool
    @Binding var showingDeleteAlert: Bool
    @Binding var profileToDelete: HostProfile?
    
    var body: some View {
        List(selection: $selectedProfile) {
            ForEach(profiles) { profile in
                HStack {
                    Image(systemName: profile.isActive ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(profile.isActive ? .green : .secondary)
                    
                    Text(profile.name)
                        .fontWeight(profile.isActive ? .semibold : .regular)
                    
                    Spacer()
                    
                    Text("\(profile.entries.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(profile)
                .contextMenu {
                    if profile.name != "Original Hosts" && !profile.isActive {
                        Button("Delete", role: .destructive) {
                            profileToDelete = profile
                            showingDeleteAlert = true
                        }
                    } else if profile.isActive {
                        Text("Active Profile (Cannot Delete)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Protected Profile")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Profiles")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddProfile = true }) {
                    Label("Add Profile", systemImage: "plus")
                }
            }
        }
    }
}

// MARK: - Add Profile Sheet
struct AddProfileSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool
    var onProfileCreated: ((HostProfile) -> Void)?

    @State private var profileName = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Profile Name", text: $profileName)
            }
            .formStyle(.grouped)
            .navigationTitle("New Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createProfile()
                    }
                    .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(width: 450, height: 150)
    }

    private func createProfile() {
        let profile = HostProfile(name: profileName.trimmingCharacters(in: .whitespaces))

        modelContext.insert(profile)
        try? modelContext.save()

        // Yeni profili seçmek için callback'i çağır
        onProfileCreated?(profile)

        isPresented = false
    }
}

#Preview {
    EditorView()
        .modelContainer(for: [HostProfile.self, HostEntry.self], inMemory: true)
}
