import Foundation

enum AuthenticatorProImport {
    private static let header = Data("AUTHENTICATORPRO".utf8)
    private static let legacyHeader = Data("AuthenticatorPro".utf8)

    private static let saltLength = 16
    private static let nonceLength = 12
    private static let argonIterations = 3
    private static let argonMemoryKiB = 64 * 1024
    private static let argonParallelism = 4

    private static let legacySaltLength = 20
    private static let legacyIVLength = 16
    private static let legacyRounds: UInt32 = 64_000

    private static let keyLength = 32
    private static let algorithms = ["SHA1", "SHA256", "SHA512"]

    static func matches(_ json: [String: Any]) -> Bool {
        json["Authenticators"] is [[String: Any]]
    }

    static func isEncryptedBackup(_ data: Data) -> Bool {
        data.starts(with: header) || data.starts(with: legacyHeader)
    }

    static func read(_ json: [String: Any]) throws -> ParsedLink {
        let items = json["Authenticators"] as? [[String: Any]] ?? []
        return try ExternalImport.result(items.map(entry))
    }

    static func readEncrypted(_ data: Data, password: String?) throws -> ParsedLink {
        guard let password else { throw ExternalImportError.wrongPassword }
        let isLegacy = !data.starts(with: header)
        let plain = isLegacy
            ? try decryptLegacy(data.dropFirst(legacyHeader.count), password: password)
            : try decrypt(data.dropFirst(header.count), password: password)
        guard let json = ExternalImport.jsonObject(plain), matches(json) else {
            throw isLegacy ? ExternalImportError.wrongPassword : ExternalImportError.damaged
        }
        return try read(json)
    }

    private static func decrypt(_ body: Data, password: String) throws -> Data {
        guard body.count > saltLength + nonceLength else { throw ExternalImportError.damaged }
        let salt = body.prefix(saltLength)
        let nonce = body.dropFirst(saltLength).prefix(nonceLength)
        let cipher = body.dropFirst(saltLength + nonceLength)
        let key = try Argon2id.derive(password: Array(password.utf8), salt: Array(salt), iterations: argonIterations,
                                      memoryKiB: argonMemoryKiB, parallelism: argonParallelism, length: keyLength)
        guard let plain = try? ImportCrypto.aesGCMDecrypt(combinedWithTag: Data(cipher), key: Data(key), nonce: Data(nonce)) else {
            throw ExternalImportError.wrongPassword
        }
        return plain
    }

    private static func decryptLegacy(_ body: Data, password: String) throws -> Data {
        guard body.count > legacySaltLength + legacyIVLength else { throw ExternalImportError.damaged }
        let salt = body.prefix(legacySaltLength)
        let iv = body.dropFirst(legacySaltLength).prefix(legacyIVLength)
        let cipher = body.dropFirst(legacySaltLength + legacyIVLength)
        let key = try ImportCrypto.pbkdf2(password: password, salt: Data(salt), rounds: legacyRounds, length: keyLength, prf: .sha1)
        guard let plain = try? ImportCrypto.aesCBCDecrypt(Data(cipher), key: key, iv: Data(iv)) else {
            throw ExternalImportError.wrongPassword
        }
        return plain
    }

    private static func entry(_ item: [String: Any]) -> ImportedToken? {
        let kind: OTPKind
        switch ExternalImport.int(item, "Type") {
        case 1: kind = .hotp
        case 2: kind = .totp
        case 4: kind = .steam
        default: return nil
        }
        let algorithmIndex = ExternalImport.int(item, "Algorithm") ?? 0
        guard algorithms.indices.contains(algorithmIndex) else { return nil }
        return ExternalImport.entry(
            issuer: ExternalImport.string(item, "Issuer"),
            account: ExternalImport.string(item, "Username"),
            secret: ExternalImport.string(item, "Secret"),
            kind: kind,
            digits: ExternalImport.int(item, "Digits"),
            period: ExternalImport.int(item, "Period"),
            algorithm: algorithms[algorithmIndex],
            counter: ExternalImport.uint64(item, "Counter")
        )
    }
}
