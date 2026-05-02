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
    
    // Decoy state during creation
    @State private var useDecoy = false
    @State private var decoyPassword = ""
    
    // Stealth state during creation
    @State private var useStealth = false
    
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
        // Decoy fields
        let hasDecoy: Bool
        let decoyPassword: String?
        let decoySalt: Data?
        let decoyVerif: Data?
        // Stealth
        let hasStealth: Bool
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
            
            createVaultButton
        }
        .toolbar {
            ToolbarItem {
                Button(action: { showingAddVault = true }) {
                    Label("Add Vault", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddVault) { createVaultSheet }
        .sheet(isPresented: $showingRecoveryWarning) { recoveryKeyWarningSheet }
        .sheet(isPresented: $showingChangePassword) { changePasswordSheet }
        .sheet(isPresented: $showingEditVault) { editVaultSheet }
        .sheet(isPresented: $showingAbout) { AboutView() }
        .alert("Delete Vault?", isPresented: $showingDeleteAlert, presenting: vaultToDelete) { vault in
            Button("Delete", role: .destructive) { deleteVault(vault) }
            Button("Cancel", role: .cancel) {}
        } message: { vault in
            Text("Are you sure you want to delete '\(vault.name)'? This will remove it from the app, but files on disk will remain in \(vault.rootPath).")
        }
    }
    
    var createVaultButton: some View {
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
    
    var createVaultSheet: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Create New Vault")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Basic Info")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Vault Name", text: $newVaultName)
                            .textFieldStyle(.roundedBorder)
                        
                        SecureField("Master Password", text: $newVaultPassword)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Privacy Features")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Toggle(isOn: $useStealth) {
                            VStack(alignment: .leading) {
                                Text("Stealth Filenames")
                                    .font(.subheadline)
                                Text("Obfuscates names on disk when locked.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Toggle(isOn: $useDecoy) {
                            VStack(alignment: .leading) {
                                Text("Decoy Mode")
                                    .font(.subheadline)
                                Text("Secondary password for hidden access.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        if useDecoy {
                            SecureField("Decoy Password", text: $decoyPassword)
                                .textFieldStyle(.roundedBorder)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    
                    Divider()
                    
                    HStack {
                        Text(selectedFolderURL?.lastPathComponent ?? "No folder selected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Select Folder...") { selectFolder() }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding(.horizontal)
                
                HStack {
                    Button("Cancel") { resetState() }
                    .keyboardShortcut(.escape, modifiers: [])
                    
                    Button("Prepare Vault") { prepareVault() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newVaultName.isEmpty || newVaultPassword.isEmpty || selectedFolderURL == nil || (useDecoy && decoyPassword.isEmpty))
                }
            }
            .padding()
        }
        .frame(width: 450, height: 550)
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
    
    var changePasswordSheet: some View {
        VStack(spacing: 20) {
            Text("Change Password")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                SecureField("Old Password", text: $oldPassword)
                    .textFieldStyle(.roundedBorder)
                SecureField("New Password", text: $newPassword)
                    .textFieldStyle(.roundedBorder)
                
                if let error = changePasswordError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal)
            
            HStack {
                Button("Cancel") {
                    showingChangePassword = false
                    oldPassword = ""
                    newPassword = ""
                }
                
                Button("Update Password") {
                    performPasswordChange()
                }
                .buttonStyle(.borderedProminent)
                .disabled(oldPassword.isEmpty || newPassword.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
    
    var editVaultSheet: some View {
        VStack(spacing: 20) {
            Text("Edit Vault")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Vault Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Name", text: $editedVaultName)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)
            
            HStack {
                Button("Cancel") {
                    showingEditVault = false
                }
                
                Button("Save") {
                    if let vault = vaultToEdit {
                        vault.name = editedVaultName
                        showingEditVault = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(editedVaultName.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
    
    private func performPasswordChange() {
        guard let vault = vaultToChangePassword else { return }
        changePasswordError = nil
        
        Task { @MainActor in
            do {
                try await vaultManager.changePassword(vault: vault, oldPassword: oldPassword, newPassword: newPassword)
                showingChangePassword = false
                oldPassword = ""
                newPassword = ""
            } catch {
                changePasswordError = "Password change failed. Please check your old password."
            }
        }
    }
    
    private func prepareVault() {
        guard let folderURL = selectedFolderURL else { return }
        do {
            let salt = SecurityManager.shared.generateSalt()
            let bookmarkData = try folderURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            let verificationData = try SecurityManager.shared.encrypt(Data("vaultlyn-verified".utf8), password: newVaultPassword, salt: salt)
            
            let recovery = SecurityManager.shared.generateRecoveryKey()
            let encryptedMaster = try SecurityManager.shared.encryptWithRecoveryKey(Data(newVaultPassword.utf8), recoveryKey: recovery.keyData)
            
            var dSalt: Data?
            var dVerif: Data?
            if useDecoy {
                dSalt = SecurityManager.shared.generateSalt()
                dVerif = try SecurityManager.shared.encrypt(Data("vaultlyn-decoy".utf8), password: decoyPassword, salt: dSalt!)
            }
            
            pendingVaultData = PendingVaultData(
                name: newVaultName,
                path: folderURL,
                password: newVaultPassword,
                salt: salt,
                verification: verificationData,
                bookmark: bookmarkData,
                keyData: recovery.keyData,
                keyHash: recovery.hash,
                encryptedMaster: encryptedMaster,
                hasDecoy: useDecoy,
                decoyPassword: useDecoy ? decoyPassword : nil,
                decoySalt: dSalt,
                decoyVerif: dVerif,
                hasStealth: useStealth
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
                    encryptedMasterPassword: data.encryptedMaster,
                    hasDecoy: data.hasDecoy,
                    decoySalt: data.decoySalt,
                    decoyVerificationData: data.decoyVerif,
                    hasStealth: data.hasStealth
                )
                
                modelContext.insert(newVault)
                try modelContext.save()
                
                // Select and auto-unlock the new vault
                let vaultPassword = data.password
                selectedVault = newVault
                
                Task { @MainActor in
                    do {
                        try await vaultManager.unlock(vault: newVault, password: vaultPassword)
                    } catch {
                        print("Auto-unlock failed: \(error)")
                    }
                }
                
                resetState()
                showingRecoveryWarning = false
                pendingVaultData = nil
            } catch {
                print("Error saving vault: \(error)")
            }
        }
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
    
    private func resetState() {
        showingAddVault = false
        showingRecoveryWarning = false
        newVaultName = ""
        newVaultPassword = ""
        decoyPassword = ""
        useDecoy = false
        useStealth = false
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
