import SwiftUI
import SwiftData

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Vault.createdAt, order: .reverse) private var vaults: [Vault]
    @Binding var selectedVault: Vault?
    
    @State private var vaultManager = VaultManager.shared
    @State private var showingAddVault = false
    @State private var newVaultName = ""
    @State private var newVaultPassword = ""
    @State private var selectedFolderURL: URL?
    
    @State private var showingChangePassword = false
    @State private var vaultToChangePassword: Vault?
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var changePasswordError: String?
    
    @State private var showingDeleteAlert = false
    @State private var vaultToDelete: Vault?
    
    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedVault) {
                Section("Your Vaults") {
                    ForEach(vaults) { vault in
                        NavigationLink(value: vault) {
                            HStack {
                                Label(vault.name, systemImage: isUnlocked(vault) ? "lock.open.fill" : "lock.fill")
                                Spacer()
                                if isUnlocked(vault) {
                                    Circle()
                                        .fill(.green)
                                        .frame(width: 8, height: 8)
                                        .shadow(color: .green.opacity(0.5), radius: 2)
                                }
                            }
                            .foregroundStyle(isUnlocked(vault) ? .primary : .secondary)
                        }
                        .contextMenu {
                            Button {
                                vaultToChangePassword = vault
                                showingChangePassword = true
                            } label: {
                                Label("Change Password", systemImage: "key.fill")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                vaultToDelete = vault
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete Vault", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            
            Divider()
            
            Button(action: { showingAddVault = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Create Vault")
                    Spacer()
                }
                .padding()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .toolbar {
            ToolbarItem {
                Button(action: { showingAddVault = true }) {
                    Label("Add Vault", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddVault) {
            createVaultSheet
        }
        .sheet(isPresented: $showingChangePassword) {
            changePasswordSheet
        }
        .alert("Delete Vault?", isPresented: $showingDeleteAlert, presenting: vaultToDelete) { vault in
            Button("Delete", role: .destructive) {
                deleteVault(vault)
            }
            Button("Cancel", role: .cancel) {}
        } message: { vault in
            Text("Are you sure you want to delete '\(vault.name)'? This will remove it from the app, but files on disk will remain in \(vault.rootPath).")
        }
    }
    
    private func isUnlocked(_ vault: Vault) -> Bool {
        vaultManager.activeVault?.id == vault.id && vaultManager.isUnlocked
    }
    
    var createVaultSheet: some View {
        VStack(spacing: 20) {
            Text("Create New Vault")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                TextField("Vault Name", text: $newVaultName)
                    .textFieldStyle(.roundedBorder)
                
                SecureField("Master Password", text: $newVaultPassword)
                    .textFieldStyle(.roundedBorder)
                
                HStack {
                    Text(selectedFolderURL?.lastPathComponent ?? "No folder selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Select Folder...") {
                        selectFolder()
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
            .padding(.horizontal)
            
            HStack {
                Button("Cancel") {
                    resetState()
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Button("Create") {
                    addVault()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newVaultName.isEmpty || newVaultPassword.isEmpty || selectedFolderURL == nil)
            }
        }
        .padding()
        .frame(width: 400)
    }
    
    var changePasswordSheet: some View {
        VStack(spacing: 20) {
            Text("Change Password")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                SecureField("Current Password", text: $oldPassword)
                    .textFieldStyle(.roundedBorder)
                
                SecureField("New Password", text: $newPassword)
                    .textFieldStyle(.roundedBorder)
                
                if let error = changePasswordError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                
                Text("This will re-encrypt all files in the vault. Do not close the app during this process.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            
            HStack {
                Button("Cancel") {
                    showingChangePassword = false
                    oldPassword = ""
                    newPassword = ""
                    changePasswordError = nil
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Button("Change Password") {
                    performChangePassword()
                }
                .buttonStyle(.borderedProminent)
                .disabled(oldPassword.isEmpty || newPassword.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
    
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            selectedFolderURL = panel.url
            if newVaultName.isEmpty {
                newVaultName = panel.url?.lastPathComponent ?? ""
            }
        }
    }
    
    private func addVault() {
        guard let folderURL = selectedFolderURL else { return }
        do {
            let salt = SecurityManager.shared.generateSalt()
            let bookmarkData = try folderURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            let verificationData = try SecurityManager.shared.encrypt(Data("vaultlyn-verified".utf8), password: newVaultPassword, salt: salt)
            let newVault = Vault(name: newVaultName, rootPath: folderURL.path, salt: salt, verificationData: verificationData, bookmarkData: bookmarkData)
            modelContext.insert(newVault)
            resetState()
        } catch {
            print("Error creating vault: \(error)")
        }
    }
    
    private func performChangePassword() {
        guard let vault = vaultToChangePassword else { return }
        changePasswordError = nil
        
        Task {
            do {
                try await VaultManager.shared.changePassword(vault: vault, oldPassword: oldPassword, newPassword: newPassword)
                showingChangePassword = false
                oldPassword = ""
                newPassword = ""
            } catch {
                changePasswordError = "Invalid current password or processing error."
            }
        }
    }
    
    private func resetState() {
        showingAddVault = false
        newVaultName = ""
        newVaultPassword = ""
        selectedFolderURL = nil
    }
    
    private func deleteVault(_ vault: Vault) {
        modelContext.delete(vault)
        if selectedVault?.id == vault.id {
            selectedVault = nil
        }
    }
}
