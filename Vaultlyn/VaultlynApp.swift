import SwiftUI
import SwiftData

@main
struct VaultlynApp: App {
    @State private var showingAbout = false
    @State private var vaultManager = VaultManager.shared
    @State private var importManager = ImportManager.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .sheet(isPresented: $showingAbout) {
                    AboutView()
                }
                .onOpenURL { url in
                    importManager.handleExternalFiles([url])
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
                
                Button("Lock Selected Vault") {
                    if let vault = vaultManager.selectedVault {
                        Task { @MainActor in
                            await vaultManager.lock(vault: vault)
                        }
                    }
                }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(vaultManager.selectedVault == nil || vaultManager.sessions[vaultManager.selectedVault?.id ?? UUID()]?.isUnlocked != true)
            }
            
            // Vault Menu
            CommandMenu("Vault") {
                Button("Refresh Files") {
                    if let vault = vaultManager.selectedVault,
                       let session = vaultManager.sessions[vault.id] {
                        try? vaultManager.refreshItems(session: session)
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(vaultManager.selectedVault == nil || vaultManager.sessions[vaultManager.selectedVault?.id ?? UUID()]?.isUnlocked != true)
                
                Divider()
                
                Button("Change Password...") {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowChangePasswordSheet"), object: nil)
                }
                .disabled(vaultManager.selectedVault == nil || vaultManager.sessions[vaultManager.selectedVault?.id ?? UUID()]?.isUnlocked != true)
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

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        Task { @MainActor in
            ImportManager.shared.handleExternalFiles(urls)
        }
    }
}
