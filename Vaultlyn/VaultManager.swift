import Foundation
import SwiftUI

@Observable
class VaultManager {
    static let shared = VaultManager()
    
    var activeVault: Vault?
    var unlockedItems: [VaultItem] = []
    var isUnlocked: Bool = false
    var isProcessing: Bool = false
    var logs: [String] = []
    
    private var sessionKey: String? // Store password temporarily in memory
    private var scopedURL: URL? // Keep the security-scoped URL active
    
    private init() {}
    
    @MainActor
    private func addLog(_ message: String) {
        logs.append("[\(Date().formatted(date: .omitted, time: .standard))] \(message)")
        if logs.count > 100 {
            logs.removeFirst()
        }
    }
    
    func unlock(vault: Vault, password: String, persist: Bool = true) async throws {
        await MainActor.run { 
            self.isProcessing = true
            self.logs = ["Initializing unlock sequence..."]
        }
        
        defer { 
            Task { @MainActor in self.isProcessing = false }
        }
        
        // Resolve security-scoped bookmark
        if let bookmarkData = vault.bookmarkData {
            await MainActor.run { self.addLog("Resolving security-scoped bookmark...") }
            var isStale = false
            let folderURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if folderURL.startAccessingSecurityScopedResource() {
                self.scopedURL = folderURL
            } else {
                await MainActor.run { self.addLog("ERROR: Failed to access security scoped resource.") }
                throw SecurityError.invalidData
            }
        }
        
        // Verify password
        await MainActor.run { self.addLog("Verifying master password...") }
        if let verificationData = vault.verificationData {
            let decryptedData = try SecurityManager.shared.decrypt(verificationData, password: password, salt: vault.salt)
            let verificationString = String(data: decryptedData, encoding: .utf8)
            guard verificationString == "vaultlyn-verified" else {
                await MainActor.run { self.addLog("ERROR: Invalid password.") }
                throw SecurityError.decryptionFailed
            }
        }
        
        self.activeVault = vault
        self.sessionKey = password
        
        if persist {
            KeychainHelper.shared.save(password, for: vault.id.uuidString)
            UserDefaults.standard.set(vault.id.uuidString, forKey: "lastActiveVaultID")
        }
        
        // Automatically decrypt all files recursively
        await MainActor.run { self.addLog("Starting recursive decryption...") }
        try await decryptAllFiles()
        
        await MainActor.run { 
            self.addLog("Unlock complete.")
            self.isUnlocked = true
            try? refreshItems()
        }
    }
    
    func lock() async {
        await MainActor.run { 
            self.isProcessing = true 
            self.logs = ["Initializing lock sequence..."]
        }
        
        if let vault = activeVault {
            KeychainHelper.shared.delete(for: vault.id.uuidString)
            UserDefaults.standard.removeObject(forKey: "lastActiveVaultID")
        }
        
        // Automatically encrypt all files recursively
        do {
            await MainActor.run { self.addLog("Starting recursive encryption...") }
            try await encryptAllFiles()
            await MainActor.run { self.addLog("Encryption complete.") }
        } catch {
            await MainActor.run { self.addLog("ERROR: Encryption failed: \(error.localizedDescription)") }
        }
        
        // Clean up
        self.scopedURL?.stopAccessingSecurityScopedResource()
        self.scopedURL = nil
        self.activeVault = nil
        self.sessionKey = nil
        
        await MainActor.run {
            self.isUnlocked = false
            self.unlockedItems = []
            self.isProcessing = false
        }
    }
    
    func changePassword(vault: Vault, oldPassword: String, newPassword: String) async throws {
        await MainActor.run { 
            self.isProcessing = true
            self.logs = ["Initializing password change..."]
        }
        
        defer { 
            Task { @MainActor in self.isProcessing = false }
        }
        
        if let bookmarkData = vault.bookmarkData {
            var isStale = false
            let folderURL = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            if folderURL.startAccessingSecurityScopedResource() {
                self.scopedURL = folderURL
            }
        }
        
        if let verificationData = vault.verificationData {
            let decryptedData = try SecurityManager.shared.decrypt(verificationData, password: oldPassword, salt: vault.salt)
            let verificationString = String(data: decryptedData, encoding: .utf8)
            guard verificationString == "vaultlyn-verified" else { throw SecurityError.decryptionFailed }
        }
        
        self.activeVault = vault
        self.sessionKey = oldPassword
        
        await MainActor.run { self.addLog("Decrypting files with old password...") }
        try await decryptAllFiles()
        
        await MainActor.run { self.addLog("Generating new verification data...") }
        let newVerificationData = try SecurityManager.shared.encrypt(
            Data("vaultlyn-verified".utf8),
            password: newPassword,
            salt: vault.salt
        )
        vault.verificationData = newVerificationData
        self.sessionKey = newPassword
        
        // Update Keychain
        KeychainHelper.shared.save(newPassword, for: vault.id.uuidString)
        
        await MainActor.run { self.addLog("Re-encrypting files with new password...") }
        try await encryptAllFiles()
        
        await MainActor.run { self.addLog("Password changed successfully.") }
        
        self.scopedURL?.stopAccessingSecurityScopedResource()
        self.scopedURL = nil
        self.activeVault = nil
        self.sessionKey = nil
    }
    
    func refreshItems() throws {
        guard let vault = activeVault else { return }
        let url = scopedURL ?? URL(fileURLWithPath: vault.rootPath)
        
        let fileURLs = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
        
        self.unlockedItems = fileURLs
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .map { url in
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                return VaultItem(
                    name: url.lastPathComponent,
                    url: url,
                    size: attributes?[.size] as? Int64 ?? 0,
                    modificationDate: attributes?[.modificationDate] as? Date ?? Date()
                )
            }
    }
    
    private func encryptAllFiles() async throws {
        guard let vault = activeVault, let password = sessionKey else { return }
        let rootURL = scopedURL ?? URL(fileURLWithPath: vault.rootPath)
        
        let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        
        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues.isDirectory == true { continue }
            if fileURL.pathExtension == "vaultlyn" { continue }
            
            await MainActor.run { self.addLog("Encrypting: \(fileURL.lastPathComponent)") }
            let data = try Data(contentsOf: fileURL)
            let encryptedData = try SecurityManager.shared.encrypt(data, password: password, salt: vault.salt)
            
            let destinationURL = fileURL.appendingPathExtension("vaultlyn")
            try encryptedData.write(to: destinationURL)
            try FileManager.default.removeItem(at: fileURL)
        }
    }
    
    private func decryptAllFiles() async throws {
        guard let vault = activeVault, let password = sessionKey else { return }
        let rootURL = scopedURL ?? URL(fileURLWithPath: vault.rootPath)
        
        let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        
        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues.isDirectory == true { continue }
            
            if fileURL.pathExtension == "vaultlyn" {
                await MainActor.run { self.addLog("Decrypting: \(fileURL.lastPathComponent)") }
                let encryptedData = try Data(contentsOf: fileURL)
                let decryptedData = try SecurityManager.shared.decrypt(encryptedData, password: password, salt: vault.salt)
                
                let destinationURL = fileURL.deletingPathExtension()
                try decryptedData.write(to: destinationURL)
                try FileManager.default.removeItem(at: fileURL)
            }
        }
    }
    
    func encryptFile(at sourceURL: URL) async throws {
        guard let vault = activeVault else { return }
        let url = scopedURL ?? URL(fileURLWithPath: vault.rootPath)
        let destinationURL = url.appendingPathComponent(sourceURL.lastPathComponent)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        try refreshItems()
    }
}
