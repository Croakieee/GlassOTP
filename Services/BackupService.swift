import Foundation
import CryptoKit

struct BackupContainer: Codable {
    let version: Int
    let salt: Data
    let sealedData: Data
}

struct BackupService {

    // MARK: - EXPORT

    static func export(tokens: [OTPToken], store: OTPStore, password: String) throws -> Data {

        let payload = try buildPayload(tokens: tokens, store: store)
        let json = try JSONEncoder().encode(payload)

        let salt = randomData(16)
        let key = deriveKey(password: password, salt: salt)

        let sealed = try AES.GCM.seal(json, using: key)

        let container = BackupContainer(
            version: 1,
            salt: salt,
            sealedData: sealed.combined!
        )

        return try JSONEncoder().encode(container)
    }

    // MARK: - IMPORT

    static func `import`(data: Data, password: String) throws -> [ImportedToken] {

        let container = try JSONDecoder().decode(BackupContainer.self, from: data)

        let key = deriveKey(password: password, salt: container.salt)

        let sealedBox = try AES.GCM.SealedBox(combined: container.sealedData)
        let decrypted = try AES.GCM.open(sealedBox, using: key)

        let payload = try JSONDecoder().decode([BackupToken].self, from: decrypted)

        return payload.map {
            ImportedToken(
                token: $0.token,
                secret: Data(base64Encoded: $0.secret)!
            )
        }
    }

    // MARK: - Helpers

    private static func deriveKey(password: String, salt: Data) -> SymmetricKey {
        let data = password.data(using: .utf8)!
        let combined = data + salt
        let hash = SHA256.hash(data: combined)
        return SymmetricKey(data: Data(hash))
    }

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
