import Foundation

enum AegisImport {
    private static let passwordSlot = 1
    private static let keyLength = 32

    static func matches(_ json: [String: Any]) -> Bool {
        json["header"] is [String: Any] && json["db"] != nil
    }

    static func isEncrypted(_ json: [String: Any]) -> Bool {
        json["db"] is String
    }

    static func read(_ json: [String: Any], password: String?) throws -> ParsedLink {
        let database: [String: Any]
        if let encrypted = json["db"] as? String {
            guard let password else { throw ExternalImportError.wrongPassword }
            database = try decrypt(encrypted, header: json["header"] as? [String: Any] ?? [:], password: password)
        } else {
            guard let plain = json["db"] as? [String: Any] else { throw ExternalImportError.damaged }
            database = plain
        }
        let entries = database["entries"] as? [[String: Any]] ?? []
        return try ExternalImport.result(entries.map(entry))
    }

    private static func decrypt(_ encrypted: String, header: [String: Any], password: String) throws -> [String: Any] {
        guard let slots = header["slots"] as? [[String: Any]],
              let params = header["params"] as? [String: Any],
              let nonce = hex(params, "nonce"), let tag = hex(params, "tag"),
              let cipher = Data(base64Encoded: encrypted) else { throw ExternalImportError.damaged }

        let passwordBytes = Data(password.utf8)
        for slot in slots where ExternalImport.int(slot, "type") == passwordSlot {
            guard let masterKey = try? unlock(slot, password: passwordBytes) else { continue }
            guard let plain = try? ImportCrypto.aesGCMDecrypt(cipher, key: masterKey, nonce: nonce, tag: tag),
                  let database = ExternalImport.jsonObject(plain) else { throw ExternalImportError.damaged }
            return database
        }
        throw ExternalImportError.wrongPassword
    }

    private static func unlock(_ slot: [String: Any], password: Data) throws -> Data {
        guard let n = ExternalImport.int(slot, "n"), let r = ExternalImport.int(slot, "r"), let p = ExternalImport.int(slot, "p"),
              let salt = hex(slot, "salt"), let wrapped = hex(slot, "key"),
              let keyParams = slot["key_params"] as? [String: Any],
              let nonce = hex(keyParams, "nonce"), let tag = hex(keyParams, "tag") else { throw ExternalImportError.damaged }
        let derived = try Scrypt.derive(password: password, salt: salt, n: n, r: r, p: p, length: keyLength)
        return try ImportCrypto.aesGCMDecrypt(wrapped, key: derived, nonce: nonce, tag: tag)
    }

    private static func entry(_ item: [String: Any]) -> ImportedToken? {
        let info = item["info"] as? [String: Any] ?? [:]
        let kind: OTPKind
        switch ExternalImport.string(item, "type")?.lowercased() {
        case "totp": kind = .totp
        case "hotp": kind = .hotp
        case "steam": kind = .steam
        default: return nil
        }
        return ExternalImport.entry(
            issuer: ExternalImport.string(item, "issuer"),
            account: ExternalImport.string(item, "name"),
            secret: ExternalImport.string(info, "secret"),
            kind: kind,
            digits: ExternalImport.int(info, "digits"),
            period: ExternalImport.int(info, "period"),
            algorithm: ExternalImport.string(info, "algo"),
            counter: ExternalImport.uint64(info, "counter")
        )
    }

    private static func hex(_ object: [String: Any], _ key: String) -> Data? {
        ExternalImport.string(object, key).flatMap { Data(hex: $0) }
    }
}
