//
//  VaultlynApp.swift
//  Vaultlyn
//
//  Created by Sidharth Prabhu on 2026-05-02.
//

import SwiftUI
import SwiftData

@main
struct VaultlynApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(for: Vault.self)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
