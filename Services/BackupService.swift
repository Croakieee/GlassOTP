import Foundation
import CryptoKit
import CommonCrypto

struct BackupContainer: Codable {
    let version: Int
    let salt: Data
    let sealedData: Data
}

enum BackupError: Error, LocalizedError {
    case sealFailed
    case corruptedPayload
    case badPassword
    case keyDerivationFailed

    var errorDescription: String? {
        switch self {
        case .sealFailed:          return "Failed to encrypt backup."
        case .corruptedPayload:    return "Backup file is corrupted."
        case .badPassword:         return "Invalid password encoding."
        case .keyDerivationFailed: return "Key derivation failed."
        }
    }
}

struct BackupService {

    private static let currentVersion = 2

    // MARK: - Export

    static func export(tokens: [OTPToken], store: OTPStore, password: String) throws -> Data {
        let payload = try buildPayload(tokens: tokens, store: store)
        let json    = try JSONEncoder().encode(payload)

        let salt = randomData(16)
        let key  = try deriveKey(password: password, salt: salt, version: currentVersion)

        let sealed = try AES.GCM.seal(json, using: key)
        guard let combined = sealed.combined else { throw BackupError.sealFailed }

        let container = BackupContainer(version: currentVersion, salt: salt, sealedData: combined)
        return try JSONEncoder().encode(container)
    }

    // MARK: - Import

    static func `import`(data: Data, password: String) throws -> [ImportedToken] {
        let container = try JSONDecoder().decode(BackupContainer.self, from: data)
        let key       = try deriveKey(password: password, salt: container.salt, version: container.version)

        let sealedBox = try AES.GCM.SealedBox(combined: container.sealedData)
        let decrypted = try AES.GCM.open(sealedBox, using: key)

        let payload = try JSONDecoder().decode([BackupToken].self, from: decrypted)

        return try payload.map { item in
            guard let secret = Data(base64Encoded: item.secret) else {
                throw BackupError.corruptedPayload
            }
            return ImportedToken(token: item.token, secret: secret)
        }
    }

    // MARK: - Key derivation

    private static func deriveKey(password: String, salt: Data, version: Int) throws -> SymmetricKey {
        switch version {
        case 1:
            // Legacy SHA256(password||salt) — retained for reading old backups only.
            let data     = password.data(using: .utf8)!
            let hash     = SHA256.hash(data: data + salt)
            return SymmetricKey(data: Data(hash))
        default:
            // v2+: PBKDF2-HMAC-SHA256, 100 000 iterations.
            return try pbkdf2(password: password, salt: salt)
        }
    }

    private static func pbkdf2(password: String, salt: Data) throws -> SymmetricKey {
        guard let passwordData = password.data(using: .utf8) else {
            throw BackupError.badPassword
        }
        var derivedKey = Data(count: 32)
        var status: Int32 = 0

        derivedKey.withUnsafeMutableBytes { derivedPtr in
            passwordData.withUnsafeBytes { passPtr in
                salt.withUnsafeBytes { saltPtr in
                    status = CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        100_000,
                        derivedPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }

        guard status == kCCSuccess else { throw BackupError.keyDerivationFailed }
        return SymmetricKey(data: derivedKey)
    }

    // MARK: - Helpers

    private static func randomData(_ length: Int) -> Data {
        var data = Data(count: length)
        _ = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, length, $0.baseAddress!)
        }
        return data
    }

    private static func buildPayload(tokens: [OTPToken], store: OTPStore) throws -> [BackupToken] {
        try tokens.map {
            let secret = try KeychainService.getSecret(for: $0.id)
            return BackupToken(token: $0, secret: secret.base64EncodedString())
        }
    }
}

// MARK: - Model

struct BackupToken: Codable {
    let token: OTPToken
    let secret: String
}
