import Foundation
import CryptoKit
import CommonCrypto

enum SecurityError: Error {
    case encryptionFailed
    case decryptionFailed
    case keyDerivationFailed
    case invalidData
}

/// Manages encryption and decryption of data using AES-GCM and PBKDF2 for key derivation.
class SecurityManager {
    static let shared = SecurityManager()
    
    private let saltLength = 32
    private let iterations: UInt32 = 100_000
    
    private init() {}
    
    /// Derives a symmetric key from a password and salt using PBKDF2.
    func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        let passwordData = Data(password.utf8)
        var derivedBytes = [UInt8](repeating: 0, count: 32) // 256-bit key
        
        let result = passwordData.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.bindMemory(to: Int8.self).baseAddress,
                    passwordData.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iterations,
                    &derivedBytes,
                    derivedBytes.count
                )
            }
        }
        
        guard result == kCCSuccess else {
            throw SecurityError.keyDerivationFailed
        }
        
        return SymmetricKey(data: derivedBytes)
    }
    
    /// Encrypts data using AES-GCM.
    /// - Returns: A combined data object containing the nonce, tag, and ciphertext.
    func encrypt(_ data: Data, password: String, salt: Data) throws -> Data {
        let key = try deriveKey(password: password, salt: salt)
        let sealedBox = try AES.GCM.seal(data, using: key)
        return sealedBox.combined!
    }
    
    /// Decrypts data using AES-GCM.
    func decrypt(_ combinedData: Data, password: String, salt: Data) throws -> Data {
        let key = try deriveKey(password: password, salt: salt)
        let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
        return try AES.GCM.open(sealedBox, using: key)
    }
    
    /// Generates a random salt.
    func generateSalt() -> Data {
        var salt = Data(count: saltLength)
        _ = salt.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, saltLength, $0.baseAddress!)
        }
        return salt
    }
}
