import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Vault.createdAt, order: .reverse) private var vaults: [Vault]
    @Binding var selectedVault: Vault?
    
    @State private var vaultManager = VaultManager.shared
    @State private var showingAddVault = false
    @State private var newVaultName = ""
    @State private var newVaultPassword = ""
    @State private var selectedFolderURL: URL?
    
    @State private var showingRecoveryWarning = false
    @State private var pendingVaultData: PendingVaultData?
    
    @State private var showingChangePassword = false
    @State private var vaultToChangePassword: Vault?
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var changePasswordError: String?
    
    @State private var showingEditVault = false
    @State private var vaultToEdit: Vault?
    @State private var editedVaultName = ""
    
    @State private var showingDeleteAlert = false
    @State private var vaultToDelete: Vault?
    
    @State private var showingAbout = false
    
    struct PendingVaultData {
        let name: String
        let path: URL
        let password: String
        let salt: Data
        let verification: Data
        let bookmark: Data
        let keyData: Data
        let keyHash: Data
        let encryptedMaster: Data
    }
    
    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedVault) {
                Section("Your Vaults") {
                    ForEach(vaults) { vault in
                        VaultRow(vault: vault, vaultManager: vaultManager, onEdit: {
                            vaultToEdit = vault
                            editedVaultName = vault.name
                            showingEditVault = true
                        }, onChangePassword: {
                            vaultToChangePassword = vault
                            showingChangePassword = true
                        }, onDelete: {
                            vaultToDelete = vault
                            showingDeleteAlert = true
                        }, onAbout: {
                            showingAbout = true
                        })
                        .tag(vault)
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectedVault) { _, newValue in
                vaultManager.selectedVault = newValue
            }
            
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
        .sheet(isPresented: $showingRecoveryWarning) {
            recoveryKeyWarningSheet
        }
        .sheet(isPresented: $showingChangePassword) {
            changePasswordSheet
        }
        .sheet(isPresented: $showingEditVault) {
            editVaultSheet
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .alert("Delete Vault?", isPresented: $showingDeleteAlert, presenting: vaultToDelete) { vault in
            Button("Delete", role: .destructive) {
                deleteVault(vault)
            }
            Button("Cancel", role: .cancel) {}
        } message: { vault in
            Text("Are you sure you want to delete '\(vault.name)'? This will remove it from the app, but files on disk will remain in \(vault.rootPath).")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowNewVaultSheet"))) { _ in
            showingAddVault = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowChangePasswordSheet"))) { _ in
            if let vault = selectedVault, vaultManager.sessions[vault.id]?.isUnlocked == true {
                vaultToChangePassword = vault
                showingChangePassword = true
            }
        }
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
                
                Button("Prepare Vault") {
                    prepareVault()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newVaultName.isEmpty || newVaultPassword.isEmpty || selectedFolderURL == nil)
            }
        }
        .padding()
        .frame(width: 400)
    }
    
    var recoveryKeyWarningSheet: some View {
        VStack(spacing: 24) {
            Image(systemName: "key.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            
            VStack(spacing: 8) {
                Text("Recovery Key Generated")
                    .font(.headline)
                Text("A unique recovery key has been created for your vault. If you forget your password or the vault gets locked due to multiple failed attempts, this key is the ONLY way to regain access.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Store this file in a safe, offline location.")
                }
                HStack {
                    Image(systemName: "lock.shield.fill")
                    Text("Anyone with this file can access your vault.")
                }
            }
            .font(.caption)
            .foregroundStyle(.orange)
            
            HStack {
                Button("Cancel") {
                    showingRecoveryWarning = false
                    pendingVaultData = nil
                }
                
                Button("Save Recovery Key & Finish") {
                    saveRecoveryKey()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(width: 450)
    }
    
    private func prepareVault() {
        guard let folderURL = selectedFolderURL else { return }
        do {
            let salt = SecurityManager.shared.generateSalt()
            let bookmarkData = try folderURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            let verificationData = try SecurityManager.shared.encrypt(Data("vaultlyn-verified".utf8), password: newVaultPassword, salt: salt)
            
            let recovery = SecurityManager.shared.generateRecoveryKey()
            let encryptedMaster = try SecurityManager.shared.encryptWithRecoveryKey(Data(newVaultPassword.utf8), recoveryKey: recovery.keyData)
            
            pendingVaultData = PendingVaultData(
                name: newVaultName,
                path: folderURL,
                password: newVaultPassword,
                salt: salt,
                verification: verificationData,
                bookmark: bookmarkData,
                keyData: recovery.keyData,
                keyHash: recovery.hash,
                encryptedMaster: encryptedMaster
            )
            
            showingAddVault = false
            showingRecoveryWarning = true
        } catch {
            print("Error preparing vault: \(error)")
        }
    }
    
    private func saveRecoveryKey() {
        guard let data = pendingVaultData else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType(filenameExtension: "vaultkey")!]
        savePanel.nameFieldStringValue = "\(data.name).vaultkey"
        savePanel.message = "Choose a safe place to store your recovery key."
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try data.keyData.write(to: url)
                
                let newVault = Vault(
                    name: data.name,
                    rootPath: data.path.path,
                    salt: data.salt,
                    verificationData: data.verification,
                    bookmarkData: data.bookmark,
                    recoveryKeyHash: data.keyHash,
                    encryptedMasterPassword: data.encryptedMaster
                )
                
                modelContext.insert(newVault)
                try modelContext.save()
                
                resetState()
                showingRecoveryWarning = false
                pendingVaultData = nil
            } catch {
                print("Error saving recovery key: \(error)")
            }
        }
    }
    
    var editVaultSheet: some View {
        VStack(spacing: 20) {
            Text("Edit Vault")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Vault Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Vault Name", text: $editedVaultName)
                    .textFieldStyle(.roundedBorder)
                
                Text("Root Path")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(vaultToEdit?.rootPath ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding(.horizontal)
            
            HStack {
                Button("Cancel") {
                    showingEditVault = false
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Button("Save Changes") {
                    updateVault()
                }
                .buttonStyle(.borderedProminent)
                .disabled(editedVaultName.isEmpty)
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
    
    private func updateVault() {
        if let vault = vaultToEdit {
            vault.name = editedVaultName
            try? modelContext.save()
            showingEditVault = false
        }
    }
    
    private func performChangePassword() {
        guard let vault = vaultToChangePassword else { return }
        changePasswordError = nil
        
        Task { @MainActor in
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
        showingRecoveryWarning = false
        newVaultName = ""
        newVaultPassword = ""
        selectedFolderURL = nil
        pendingVaultData = nil
    }
    
    private func deleteVault(_ vault: Vault) {
        modelContext.delete(vault)
        if selectedVault?.id == vault.id {
            selectedVault = nil
        }
    }
}

struct VaultRow: View {
    let vault: Vault
    let vaultManager: VaultManager
    let onEdit: () -> Void
    let onChangePassword: () -> Void
    let onDelete: () -> Void
    let onAbout: () -> Void
    
    private var isUnlocked: Bool {
        vaultManager.sessions[vault.id]?.isUnlocked == true
    }
    
    var body: some View {
        NavigationLink(value: vault) {
            HStack {
                Label(vault.name, systemImage: isUnlocked ? "lock.open.fill" : "lock.fill")
                Spacer()
                if isUnlocked {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .shadow(color: .green.opacity(0.5), radius: 2)
                }
                if vault.isLockedOut {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundStyle(Color.red)
                        .font(.caption)
                }
            }
            .foregroundStyle(isUnlocked ? Color.primary : (vault.isLockedOut ? Color.red : Color.secondary))
        }
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit Vault", systemImage: "pencil")
            }
            
            Button(action: onChangePassword) {
                Label("Change Password", systemImage: "key.fill")
            }
            
            Divider()
            
            Button(role: .destructive, action: onDelete) {
                Label("Delete Vault", systemImage: "trash")
            }
            
            Divider()
            
            Button(action: onAbout) {
                Label("About Vaultlyn", systemImage: "info.circle")
            }
        }
    }
}
