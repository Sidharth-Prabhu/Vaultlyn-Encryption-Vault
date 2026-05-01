import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var vaults: [Vault]
    @State private var selectedVault: Vault?
    @State private var isInitializing = true
    
    var body: some View {
        NavigationSplitView {
            SidebarView(selectedVault: $selectedVault)
        } detail: {
            if isInitializing {
                VStack {
                    ProgressView()
                    Text("Restoring session...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let vault = selectedVault {
                VaultDetailView(vault: vault)
            } else {
                ContentUnavailableView(
                    "Select a Vault",
                    systemImage: "lock.shield",
                    description: Text("Choose a vault from the sidebar or create a new one.")
                )
            }
        }
        .frame(minWidth: 700, minHeight: 450)
        .onAppear {
            attemptAutoUnlock()
        }
    }
    
    private func attemptAutoUnlock() {
        guard let lastVaultID = UserDefaults.standard.string(forKey: "lastActiveVaultID"),
              let vault = vaults.first(where: { $0.id.uuidString == lastVaultID }),
              let password = KeychainHelper.shared.read(for: lastVaultID) else {
            isInitializing = false
            return
        }
        
        selectedVault = vault
        Task {
            // Attempt auto-unlock without re-persisting (already in keychain)
            try? await VaultManager.shared.unlock(vault: vault, password: password, persist: false)
            await MainActor.run {
                isInitializing = false
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Vault.self, inMemory: true)
}
