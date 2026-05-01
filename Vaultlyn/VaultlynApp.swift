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
            CommandGroup(replacing: .appInfo) {
                Button("About Vaultlyn") {
                    showingAbout = true
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
