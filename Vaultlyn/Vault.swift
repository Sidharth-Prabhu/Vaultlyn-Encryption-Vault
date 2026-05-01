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
    
    init(name: String, rootPath: String, salt: Data, verificationData: Data? = nil, bookmarkData: Data? = nil) {
        self.id = UUID()
        self.name = name
        self.rootPath = rootPath
        self.createdAt = Date()
        self.salt = salt
        self.verificationData = verificationData
        self.bookmarkData = bookmarkData
    }
}
