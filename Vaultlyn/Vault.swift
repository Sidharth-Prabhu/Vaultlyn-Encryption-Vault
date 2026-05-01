import Foundation
import SwiftData

@Model
final class Vault {
    @Attribute(.unique) var id: UUID
    var name: String
    var rootPath: String
    var salt: Data
    var verificationData: Data? // Encrypted string to verify password
    var bookmarkData: Data? // For security-scoped bookmarks (persistent folder access)
    var createdAt: Date
    
    init(name: String, rootPath: String, salt: Data, verificationData: Data? = nil, bookmarkData: Data? = nil) {
        self.id = UUID()
        self.name = name
        self.rootPath = rootPath
        self.salt = salt
        self.verificationData = verificationData
        self.bookmarkData = bookmarkData
        self.createdAt = Date()
    }
}

struct VaultItem: Identifiable, Hashable {
    let id: UUID = UUID()
    let name: String
    let url: URL
    let size: Int64
    let modificationDate: Date
    
    var isEncrypted: Bool {
        url.pathExtension == "vaultlyn"
    }
}
