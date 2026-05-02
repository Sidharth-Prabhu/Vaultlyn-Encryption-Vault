import SwiftUI
import SwiftData

struct ImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Vault.createdAt, order: .reverse) private var vaults: [Vault]
    
    let files: [URL]
    
    @State private var selectedVault: Vault?
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isProcessing = false
    @State private var progress: Double = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor)
                
                Text("Secure Import")
                    .font(.title2.bold())
                
                Text("Adding \(files.count) \(files.count == 1 ? "file" : "files") to Vaultlyn")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 30)
            
            Divider()
            
            HStack(spacing: 0) {
                // Vault List
                VStack(alignment: .leading) {
                    Text("Select Vault")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)
                        .padding(.top, 16)
                    
                    List(vaults, selection: $selectedVault) { vault in
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(selectedVault?.id == vault.id ? .white : .accentColor)
                            Text(vault.name)
                        }
                        .tag(vault)
                    }
                    .listStyle(.inset)
                }
                .frame(width: 200)
                
                Divider()
                
                // Password & Action
                VStack(spacing: 20) {
                    if let selected = selectedVault {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Unlock \(selected.name)")
                                .font(.headline)
                            
                            SecureField("Enter Vault Password", text: $password)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.large)
                            
                            if let error = errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            
                            if isProcessing {
                                VStack(spacing: 8) {
                                    ProgressView(value: progress)
                                        .progressViewStyle(.linear)
                                    Text("Encrypting and importing...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 10)
                            }
                        }
                        .padding(24)
                        
                        Spacer()
                        
                        HStack {
                            Button("Cancel") {
                                dismiss()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Button(action: performImport) {
                                Text("Unlock & Secure")
                                    .frame(width: 120)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(password.isEmpty || isProcessing)
                        }
                        .padding(24)
                    } else {
                        VStack {
                            Image(systemName: "arrow.left.circle")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                            Text("Please select a target vault from the list.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(width: 600, height: 450)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func performImport() {
        guard let vault = selectedVault else { return }
        
        isProcessing = true
        errorMessage = nil
        
        Task { @MainActor in
            do {
                // 1. Unlock the vault
                try await VaultManager.shared.unlock(vault: vault, password: password)
                
                // 2. Import files
                let session = VaultManager.shared.session(for: vault)
                try await VaultManager.shared.importFiles(urls: files, session: session)
                
                // 3. Lock the vault (per user request: "I should be able to lock the vault like usual" 
                //    but usually imports should be clean. I'll stay unlocked so they can see them, 
                //    as per previous instructions where we said they'll be encrypted on lock.)
                
                // Actually, the user said "Then I should be able to lock the vault like usual"
                // which implies they stay in the app.
                
                ImportManager.shared.clear()
                dismiss()
            } catch {
                isProcessing = false
                errorMessage = "Authentication failed. Please check your password."
            }
        }
    }
}
