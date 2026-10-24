import Foundation

enum SteamImportError: Error, LocalizedError, Equatable {
    case notSteamData
    case encryptedNeedsFolder
    case wrongPasskey
    case noAccounts
    case badSecret

    var errorDescription: String? {
        switch self {
        case .notSteamData:
            return "This isn't a Steam Desktop Authenticator file."
        case .encryptedNeedsFolder:
            return "This maFile is encrypted. Choose Import in the menu-bar menu and select the whole maFiles folder."
        case .wrongPasskey:
            return "Wrong encryption passkey."
        case .noAccounts:
            return "No Steam accounts were found."
        case .badSecret:
            return "The Steam secret in this file is damaged."
        }
    }
}

enum SteamImport {
    static let revocationNote = "Steam revocation code"
    static let manifestName = "manifest.json"
    static let fileExtension = "mafile"

    private static let pbkdf2Rounds: UInt32 = 50_000
    private static let keyLength = 32

    private struct MaFile: Decodable {
        let sharedSecret: String
        let accountName: String?
        let revocationCode: String?

        enum CodingKeys: String, CodingKey {
            case sharedSecret = "shared_secret"
            case accountName = "account_name"
            case revocationCode = "revocation_code"
        }
    }

    struct Manifest: Decodable {
        let encrypted: Bool?
        let entries: [Entry]?

        struct Entry: Decodable {
            let filename: String
            let encryptionIV: String?
            let encryptionSalt: String?

            enum CodingKeys: String, CodingKey {
                case filename
                case encryptionIV = "encryption_iv"
                case encryptionSalt = "encryption_salt"
            }
        }

        var isEncrypted: Bool { encrypted ?? false }
    }

    static func isMaFile(_ data: Data) -> Bool {
        (try? JSONDecoder().decode(MaFile.self, from: data)) != nil
    }

    static func looksEncrypted(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.hasPrefix("{") else { return false }
        return Data(base64Encoded: text) != nil
    }

    static func token(fromMaFile data: Data) throws -> ImportedToken {
        guard let file = try? JSONDecoder().decode(MaFile.self, from: data) else { throw SteamImportError.notSteamData }
        guard let secret = Data(base64Encoded: file.sharedSecret), !secret.isEmpty else { throw SteamImportError.badSecret }
        let token = OTPToken(
            issuer: ImportExportService.steamIssuer,
            account: file.accountName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            digits: OTPKind.steamDigits,
            sortOrder: Int(Date().timeIntervalSince1970),
            kind: .steam
        )
        let revocation = file.revocationCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let codes = revocation.isEmpty ? [] : [RecoveryCode(code: revocation, note: revocationNote)]
        return ImportedToken(token: token, secret: secret, recoveryCodes: codes)
    }

    static func manifest(in folder: URL) -> Manifest? {
        guard let data = try? FileImportService.readLimited(folder.appendingPathComponent(manifestName)) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    static func hasAccounts(in folder: URL) -> Bool {
        manifest(in: folder) != nil || !maFiles(in: folder).isEmpty
    }

    static func readFolder(_ folder: URL, passkey: String?) throws -> ParsedLink {
        let manifest = manifest(in: folder)
        let entries = manifest?.entries ?? []
        if let manifest, manifest.isEncrypted {
            guard let passkey else { throw SteamImportError.wrongPasskey }
            let parsed = collect(entries.map { entry in {
                let text = String(decoding: try FileImportService.readLimited(file(entry, in: folder)), as: UTF8.self)
                let plain = try decrypt(text, passkey: passkey, salt: entry.encryptionSalt ?? "", iv: entry.encryptionIV ?? "")
                return try token(fromMaFile: plain)
            } })
            guard !parsed.tokens.isEmpty else { throw entries.isEmpty ? SteamImportError.noAccounts : SteamImportError.wrongPasskey }
            return parsed
        }
        let files = manifest == nil ? maFiles(in: folder) : entries.map { file($0, in: folder) }
        let parsed = collect(files.map { url in { try token(fromMaFile: FileImportService.readLimited(url)) } })
        guard !parsed.tokens.isEmpty else { throw SteamImportError.noAccounts }
        return parsed
    }

    private static func file(_ entry: Manifest.Entry, in folder: URL) -> URL {
        folder.appendingPathComponent((entry.filename as NSString).lastPathComponent)
    }

    static func decrypt(_ base64: String, passkey: String, salt: String, iv: String) throws -> Data {
        guard let cipher = Data(base64Encoded: base64.trimmingCharacters(in: .whitespacesAndNewlines)),
              let saltData = Data(base64Encoded: salt),
              let ivData = Data(base64Encoded: iv) else { throw SteamImportError.wrongPasskey }
        do {
            let key = try ImportCrypto.pbkdf2(password: passkey, salt: saltData, rounds: pbkdf2Rounds, length: keyLength, prf: .sha1)
            return try ImportCrypto.aesCBCDecrypt(cipher, key: key, iv: ivData)
        } catch {
            throw SteamImportError.wrongPasskey
        }
    }

    private static func maFiles(in folder: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { $0.pathExtension.lowercased() == fileExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func collect(_ readers: [() throws -> ImportedToken]) -> ParsedLink {
        var tokens: [ImportedToken] = []
        var failed = 0
        for read in readers {
            do {
                tokens.append(try read())
            } catch {
                failed += 1
            }
        }
        return ParsedLink(tokens: tokens, unsupported: failed)
    }
}
