import Foundation
import SwiftData

@Model
final class Vault {
    @Attribute(.unique) var id: UUID
    var name: String
    var rootPath: String
    var createdAt: Date
    var salt: Data
    var verificationData: Data?
    var bookmarkData: Data?
    
    // Recovery & Brute Force Protection
    var failedAttempts: Int = 0
    var isLockedOut: Bool = false
    var recoveryKeyHash: Data?
    var encryptedMasterPassword: Data? // Master password encrypted with recovery key
    
    // Decoy System
    var hasDecoy: Bool = false
    var decoySalt: Data?
    var decoyVerificationData: Data?
    
    init(name: String, rootPath: String, salt: Data, verificationData: Data? = nil, bookmarkData: Data? = nil, recoveryKeyHash: Data? = nil, encryptedMasterPassword: Data? = nil, hasDecoy: Bool = false, decoySalt: Data? = nil, decoyVerificationData: Data? = nil) {
        self.id = UUID()
        self.name = name
        self.rootPath = rootPath
        self.createdAt = Date()
        self.salt = salt
        self.verificationData = verificationData
        self.bookmarkData = bookmarkData
        self.recoveryKeyHash = recoveryKeyHash
        self.encryptedMasterPassword = encryptedMasterPassword
        self.hasDecoy = hasDecoy
        self.decoySalt = decoySalt
        self.decoyVerificationData = decoyVerificationData
        self.failedAttempts = 0
        self.isLockedOut = false
    }
}
