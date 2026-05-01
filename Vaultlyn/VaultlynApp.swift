import SwiftUI
import SwiftData

@main
struct VaultlynApp: App {
    @State private var showingAbout = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .sheet(isPresented: $showingAbout) {
                    AboutView()
                }
        }
        .modelContainer(for: Vault.self)
        .commands {
            // About Menu
            CommandGroup(replacing: .appInfo) {
                Button("About Vaultlyn") {
                    showingAbout = true
                }
            }
            
            // File Menu
            CommandGroup(after: .newItem) {
                Button("New Vault...") {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowNewVaultSheet"), object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Divider()
                
                Button("Lock Active Vault") {
                    Task { @MainActor in
                        await VaultManager.shared.lock()
                    }
                }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(!VaultManager.shared.isUnlocked)
            }
            
            // Vault Menu
            CommandMenu("Vault") {
                Button("Refresh Files") {
                    try? VaultManager.shared.refreshItems()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!VaultManager.shared.isUnlocked)
                
                Divider()
                
                Button("Change Password...") {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowChangePasswordSheet"), object: nil)
                }
                .disabled(!VaultManager.shared.isUnlocked)
            }
            
            // Help Menu
            CommandGroup(replacing: .help) {
                Link("Vaultlyn Documentation", destination: URL(string: "https://vaultlyn.com/docs")!)
                Link("Contact Support", destination: URL(string: "mailto:support@sidharthpl.com")!)
            }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
