import Foundation

enum ProtonImport {
    private static let supportedVersion = 1
    private static let nonceLength = 12
    private static let keyLength = 32
    private static let argonIterations = 2
    private static let argonMemoryKiB = 19 * 1024
    private static let argonParallelism = 1
    private static let associatedData = Data("proton.authenticator.export.v1".utf8)
    private static let steamScheme = "steam://"

    static func matches(_ json: [String: Any]) -> Bool {
        if isEncrypted(json) { return true }
        guard let entries = json["entries"] as? [[String: Any]], json["version"] != nil else { return false }
        return entries.isEmpty || entries.contains { ($0["content"] as? [String: Any])?["uri"] is String }
    }

    static func isEncrypted(_ json: [String: Any]) -> Bool {
        json["salt"] is String && json["content"] is String && json["version"] != nil
    }

    static func read(_ json: [String: Any], password: String?) throws -> ParsedLink {
        guard version(json) == supportedVersion else { throw ExternalImportError.damaged }
        let plain = isEncrypted(json) ? try decrypt(json, password: password) : json
        let entries = plain["entries"] as? [[String: Any]] ?? []
        return try ExternalImport.result(entries.flatMap(convert))
    }

    private static func version(_ json: [String: Any]) -> Int? {
        if let number = json["version"] as? NSNumber { return number.intValue }
        return (json["version"] as? String).flatMap { Int($0) }
    }

    private static func decrypt(_ json: [String: Any], password: String?) throws -> [String: Any] {
        guard let password else { throw ExternalImportError.wrongPassword }
        guard let salt = (json["salt"] as? String).flatMap({ Data(base64Encoded: $0) }),
              let content = (json["content"] as? String).flatMap({ Data(base64Encoded: $0) }),
              content.count > nonceLength else { throw ExternalImportError.damaged }
        let key = try Argon2id.derive(password: Array(password.utf8), salt: Array(salt), iterations: argonIterations,
                                      memoryKiB: argonMemoryKiB, parallelism: argonParallelism, length: keyLength)
        guard let plain = try? ImportCrypto.aesGCMDecrypt(combinedWithTag: Data(content.dropFirst(nonceLength)), key: Data(key),
                                                          nonce: Data(content.prefix(nonceLength)), authenticating: associatedData) else {
            throw ExternalImportError.wrongPassword
        }
        guard let decoded = ExternalImport.jsonObject(plain) else { throw ExternalImportError.damaged }
        return decoded
    }

    private static func convert(_ entry: [String: Any]) -> [ImportedToken?] {
        guard let content = entry["content"] as? [String: Any], let uri = content["uri"] as? String else { return [nil] }
        let name = (content["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if uri.lowercased().hasPrefix(steamScheme) {
            return [ExternalImport.entry(issuer: ImportExportService.steamIssuer, account: name,
                                         secret: String(uri.dropFirst(steamScheme.count)), kind: .steam,
                                         digits: nil, period: nil, algorithm: nil, counter: nil)]
        }
        guard let parsed = try? ImportExportService.parseOtpauthOrMigration(uri) else { return [nil] }
        return parsed.tokens.map { imported in
            guard !name.isEmpty else { return imported }
            var token = imported.token
            token.account = name
            return ImportedToken(token: token, secret: imported.secret, recoveryCodes: imported.recoveryCodes)
        } + Array(repeating: nil, count: parsed.unsupported)
    }
}
