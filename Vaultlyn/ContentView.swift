//
//  ContentView.swift
//  Vaultlyn
//
//  Created by Sidharth Prabhu on 2026-05-02.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var vaults: [Vault]
    @State private var selectedVault: Vault?
    @State private var isInitializing = true
    
    @State private var importManager = ImportManager.shared
    
    var body: some View {
        NavigationSplitView {
            SidebarView(selectedVault: $selectedVault)
        } detail: {
            if isInitializing {
                VStack {
                    ProgressView()
                    Text("Restoring sessions...")
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
        .sheet(isPresented: $importManager.isShowingImportSheet) {
            ImportView(files: importManager.pendingURLs)
        }
        .onAppear {
            attemptAutoUnlock()
        }
    }
    
    private func attemptAutoUnlock() {
        let unlockedIDs = UserDefaults.standard.stringArray(forKey: "unlockedVaultIDs") ?? []
        
        if unlockedIDs.isEmpty {
            isInitializing = false
            return
        }
        
        Task {
            for vaultID in unlockedIDs {
                if let vault = vaults.first(where: { $0.id.uuidString == vaultID }),
                   let password = KeychainHelper.shared.read(for: vaultID) {
                    
                    // Attempt auto-unlock without re-persisting (already in keychain)
                    try? await VaultManager.shared.unlock(vault: vault, password: password, persist: false)
                }
            }
            
            await MainActor.run {
                // Set the selected vault to the first one we restored, if any
                if let firstID = unlockedIDs.first {
                    selectedVault = vaults.first(where: { $0.id.uuidString == firstID })
                }
                isInitializing = false
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Vault.self, inMemory: true)
}
