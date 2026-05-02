import Foundation
import SwiftUI

struct VaultItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL
    let size: Int64
    let modificationDate: Date
    let isDirectory: Bool
}

@Observable
class VaultSession {
    let vault: Vault
    var unlockedItems: [VaultItem] = []
    var isUnlocked: Bool = false
    var isProcessing: Bool = false
    var progress: Double = 0.0
    var logs: [String] = []
    
    var sessionKey: String?
    var scopedURL: URL?
    
    init(vault: Vault) {
        self.vault = vault
    }
    
    @MainActor
    func addLog(_ message: String) {
        logs.append("[\(Date().formatted(date: .omitted, time: .standard))] \(message)")
        if logs.count > 100 {
            logs.removeFirst()
        }
    }
}

@Observable
class VaultManager {
    static let shared = VaultManager()
    
    var sessions: [UUID: VaultSession] = [:]
    var selectedVault: Vault?
    
    private init() {}
    
    func session(for vault: Vault) -> VaultSession {
        if let existing = sessions[vault.id] {
            return existing
        }
        let newSession = VaultSession(vault: vault)
        sessions[vault.id] = newSession
        return newSession
    }
    
    func unlock(vault: Vault, password: String, persist: Bool = true) async throws {
        let s = session(for: vault)
        
        await MainActor.run { 
            s.isProcessing = true
            s.progress = 0.0
            s.logs = ["Initializing unlock sequence..."]
        }
        
        defer { 
            Task { @MainActor in s.isProcessing = false }
        }
        
        // Resolve security-scoped bookmark
        if let bookmarkData = vault.bookmarkData {
            await MainActor.run { s.addLog("Resolving security-scoped bookmark...") }
            var isStale = false
            let folderURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if folderURL.startAccessingSecurityScopedResource() {
                s.scopedURL = folderURL
            } else {
                await MainActor.run { s.addLog("ERROR: Failed to access security scoped resource.") }
                throw SecurityError.invalidData
            }
        }
        
        // Verify password
        await MainActor.run { s.addLog("Verifying master password...") }
        if let verificationData = vault.verificationData {
            let decryptedData = try SecurityManager.shared.decrypt(verificationData, password: password, salt: vault.salt)
            let verificationString = String(data: decryptedData, encoding: .utf8)
            guard verificationString == "vaultlyn-verified" else {
                await MainActor.run { s.addLog("ERROR: Invalid password.") }
                throw SecurityError.decryptionFailed
            }
        }
        
        s.sessionKey = password
        
        if persist {
            KeychainHelper.shared.save(password, for: vault.id.uuidString)
            saveUnlockedVaultID(vault.id.uuidString)
        }
        
        // Automatically decrypt all files recursively
        await MainActor.run { s.addLog("Starting recursive decryption...") }
        try await decryptAllFiles(session: s)
        
        await MainActor.run { 
            s.addLog("Unlock complete.")
            s.progress = 1.0
            s.isUnlocked = true
            try? refreshItems(session: s)
        }
    }
    
    func lock(vault: Vault) async {
        guard let s = sessions[vault.id] else { return }
        
        await MainActor.run { 
            s.isProcessing = true 
            s.progress = 0.0
            s.logs = ["Initializing lock sequence..."]
        }
        
        KeychainHelper.shared.delete(for: vault.id.uuidString)
        removeUnlockedVaultID(vault.id.uuidString)
        
        // Automatically encrypt all files recursively
        do {
            await MainActor.run { s.addLog("Starting recursive encryption...") }
            try await encryptAllFiles(session: s)
            await MainActor.run { s.addLog("Encryption complete.") }
        } catch {
            await MainActor.run { s.addLog("ERROR: Encryption failed: \(error.localizedDescription)") }
        }
        
        // Clean up
        s.scopedURL?.stopAccessingSecurityScopedResource()
        s.scopedURL = nil
        s.sessionKey = nil
        
        await MainActor.run {
            s.isUnlocked = false
            s.unlockedItems = []
            s.progress = 1.0
            s.isProcessing = false
        }
    }
    
    private func saveUnlockedVaultID(_ id: String) {
        var ids = UserDefaults.standard.stringArray(forKey: "unlockedVaultIDs") ?? []
        if !ids.contains(id) {
            ids.append(id)
            UserDefaults.standard.set(ids, forKey: "unlockedVaultIDs")
        }
    }
    
    private func removeUnlockedVaultID(_ id: String) {
        var ids = UserDefaults.standard.stringArray(forKey: "unlockedVaultIDs") ?? []
        ids.removeAll { $0 == id }
        UserDefaults.standard.set(ids, forKey: "unlockedVaultIDs")
    }
    
    func changePassword(vault: Vault, oldPassword: String, newPassword: String) async throws {
        let s = session(for: vault)
        
        await MainActor.run { 
            s.isProcessing = true
            s.progress = 0.0
            s.logs = ["Initializing password change..."]
        }
        
        defer { 
            Task { @MainActor in s.isProcessing = false }
        }
        
        if let bookmarkData = vault.bookmarkData {
            var isStale = false
            let folderURL = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            if folderURL.startAccessingSecurityScopedResource() {
                s.scopedURL = folderURL
            }
        }
        
        if let verificationData = vault.verificationData {
            let decryptedData = try SecurityManager.shared.decrypt(verificationData, password: oldPassword, salt: vault.salt)
            let verificationString = String(data: decryptedData, encoding: .utf8)
            guard verificationString == "vaultlyn-verified" else { throw SecurityError.decryptionFailed }
        }
        
        s.sessionKey = oldPassword
        
        await MainActor.run { s.addLog("Decrypting files with old password...") }
        try await decryptAllFiles(session: s)
        
        await MainActor.run { s.addLog("Generating new verification data...") }
        let newVerificationData = try SecurityManager.shared.encrypt(
            Data("vaultlyn-verified".utf8),
            password: newPassword,
            salt: vault.salt
        )
        vault.verificationData = newVerificationData
        s.sessionKey = newPassword
        
        // Update Keychain
        KeychainHelper.shared.save(newPassword, for: vault.id.uuidString)
        
        await MainActor.run { s.addLog("Re-encrypting files with new password...") }
        try await encryptAllFiles(session: s)
        
        await MainActor.run { s.addLog("Password changed successfully.") }
        
        s.scopedURL?.stopAccessingSecurityScopedResource()
        s.scopedURL = nil
        s.sessionKey = nil
    }
    
    func refreshItems(session: VaultSession, at folderURL: URL? = nil) throws {
        let url = folderURL ?? session.scopedURL ?? URL(fileURLWithPath: session.vault.rootPath)
        
        let fileURLs = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
        
        session.unlockedItems = fileURLs
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .map { url in
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
                return VaultItem(
                    name: url.lastPathComponent,
                    url: url,
                    size: attributes?[.size] as? Int64 ?? 0,
                    modificationDate: attributes?[.modificationDate] as? Date ?? Date(),
                    isDirectory: resourceValues?.isDirectory ?? false
                )
            }
            .sorted { (a, b) in
                if a.isDirectory != b.isDirectory {
                    return a.isDirectory // Folders first
                }
                return a.name.localizedCompare(b.name) == .orderedAscending
            }
    }
    
    private func encryptAllFiles(session: VaultSession) async throws {
        guard let password = session.sessionKey else { return }
        let rootURL = session.scopedURL ?? URL(fileURLWithPath: session.vault.rootPath)
        
        let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        
        var filesToProcess: [URL] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues.isDirectory == false && fileURL.pathExtension != "vaultlyn" {
                filesToProcess.append(fileURL)
            }
        }
        
        let totalFiles = Double(filesToProcess.count)
        if totalFiles == 0 { return }
        
        var completed = 0.0
        
        for fileURL in filesToProcess {
            await MainActor.run { session.addLog("Encrypting: \(fileURL.lastPathComponent)") }
            let data = try Data(contentsOf: fileURL)
            let encryptedData = try SecurityManager.shared.encrypt(data, password: password, salt: session.vault.salt)
            
            let destinationURL = fileURL.appendingPathExtension("vaultlyn")
            try encryptedData.write(to: destinationURL)
            try FileManager.default.removeItem(at: fileURL)
            
            completed += 1.0
            await MainActor.run { session.progress = completed / totalFiles }
        }
    }
    
    private func decryptAllFiles(session: VaultSession) async throws {
        guard let password = session.sessionKey else { return }
        let rootURL = session.scopedURL ?? URL(fileURLWithPath: session.vault.rootPath)
        
        let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        
        var filesToProcess: [URL] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues.isDirectory == false && fileURL.pathExtension == "vaultlyn" {
                filesToProcess.append(fileURL)
            }
        }
        
        let totalFiles = Double(filesToProcess.count)
        if totalFiles == 0 { return }
        
        var completed = 0.0
        
        for fileURL in filesToProcess {
            await MainActor.run { session.addLog("Decrypting: \(fileURL.lastPathComponent)") }
            let encryptedData = try Data(contentsOf: fileURL)
            let decryptedData = try SecurityManager.shared.decrypt(encryptedData, password: password, salt: session.vault.salt)
            
            let destinationURL = fileURL.deletingPathExtension()
            try decryptedData.write(to: destinationURL)
            try FileManager.default.removeItem(at: fileURL)
            
            completed += 1.0
            await MainActor.run { session.progress = completed / totalFiles }
        }
    }
    
    func encryptFiles(urls: [URL], session: VaultSession, targetFolder: URL? = nil) async throws {
        guard let password = session.sessionKey else { return }
        let folderURL = targetFolder ?? session.scopedURL ?? URL(fileURLWithPath: session.vault.rootPath)
        
        await MainActor.run {
            session.isProcessing = true
            session.progress = 0.0
            session.logs = ["Importing \(urls.count) files..."]
        }
        
        defer {
            Task { @MainActor in session.isProcessing = false }
        }
        
        let total = Double(urls.count)
        var completed = 0.0
        
        for sourceURL in urls {
            await MainActor.run { session.addLog("Securing: \(sourceURL.lastPathComponent)") }
            
            let data = try Data(contentsOf: sourceURL)
            let encryptedData = try SecurityManager.shared.encrypt(data, password: password, salt: session.vault.salt)
            
            let destinationURL = folderURL.appendingPathComponent(sourceURL.lastPathComponent).appendingPathExtension("vaultlyn")
            try encryptedData.write(to: destinationURL)
            
            completed += 1.0
            await MainActor.run { session.progress = completed / total }
        }
        
        try refreshItems(session: session, at: folderURL)
    }
}
