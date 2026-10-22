import Foundation

enum TwoFASImport {
    private static let rounds: UInt32 = 10_000
    private static let keyLength = 32

    static func matches(_ json: [String: Any]) -> Bool {
        json["schemaVersion"] != nil && (json["services"] != nil || json["servicesEncrypted"] != nil)
    }

    static func isEncrypted(_ json: [String: Any]) -> Bool {
        !(ExternalImport.string(json, "servicesEncrypted") ?? "").isEmpty
    }

    static func read(_ json: [String: Any], password: String?) throws -> ParsedLink {
        let services: [[String: Any]]
        if let encrypted = ExternalImport.string(json, "servicesEncrypted"), !encrypted.isEmpty {
            guard let password else { throw ExternalImportError.wrongPassword }
            services = try decrypt(encrypted, password: password)
        } else {
            services = json["services"] as? [[String: Any]] ?? []
        }
        return try ExternalImport.result(services.map(entry))
    }

    private static func decrypt(_ encrypted: String, password: String) throws -> [[String: Any]] {
        let parts = encrypted.split(separator: ":").map(String.init)
        guard parts.count >= 3,
              let data = Data(base64Encoded: parts[0]),
              let salt = Data(base64Encoded: parts[1]),
              let iv = Data(base64Encoded: parts[2]) else { throw ExternalImportError.damaged }
        let key = try ImportCrypto.pbkdf2(password: password, salt: salt, rounds: rounds, length: keyLength, prf: .sha256)
        guard let plain = try? ImportCrypto.aesGCMDecrypt(combinedWithTag: data, key: key, nonce: iv) else {
            throw ExternalImportError.wrongPassword
        }
        guard let services = (try? JSONSerialization.jsonObject(with: plain)) as? [[String: Any]] else {
            throw ExternalImportError.damaged
        }
        return services
    }

    private static func entry(_ service: [String: Any]) -> ImportedToken? {
        let otp = service["otp"] as? [String: Any] ?? [:]
        let kind: OTPKind
        switch ExternalImport.string(otp, "tokenType")?.uppercased() {
        case nil, "TOTP": kind = .totp
        case "HOTP": kind = .hotp
        case "STEAM": kind = .steam
        default: return nil
        }
        let name = ExternalImport.string(service, "name") ?? ""
        return ExternalImport.entry(
            issuer: name.isEmpty ? ExternalImport.string(otp, "issuer") : name,
            account: ExternalImport.string(otp, "account"),
            secret: ExternalImport.string(service, "secret"),
            kind: kind,
            digits: ExternalImport.int(otp, "digits"),
            period: ExternalImport.int(otp, "period"),
            algorithm: ExternalImport.string(otp, "algorithm"),
            counter: ExternalImport.uint64(otp, "counter")
        )
    }
}
