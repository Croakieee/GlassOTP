import Foundation

enum ExternalImportError: Error, LocalizedError, Equatable {
    case wrongPassword
    case damaged
    case noAccounts
    case nothingSupported(Int)
    case bitwardenEncrypted

    var errorDescription: String? {
        switch self {
        case .wrongPassword:
            return "Wrong password."
        case .damaged:
            return "This file is damaged or was made by an unsupported app version."
        case .noAccounts:
            return "No accounts were found in this file."
        case .nothingSupported(let count):
            return "None of the \(count) account(s) can be added: GlassOTP supports TOTP, HOTP and Steam codes with SHA1/SHA256/SHA512 and 6 or 8 digits."
        case .bitwardenEncrypted:
            return "This Bitwarden export is password-protected. In Bitwarden, export the vault again as .json or .csv without a password, import it, then delete the file."
        }
    }
}

enum ExternalImport {
    static func entry(issuer: String?, account: String?, secret: String?, kind: OTPKind,
                      digits: Int?, period: Int?, algorithm: String?, counter: UInt64?) -> ImportedToken? {
        guard let secretText = secret, let secretData = Base32.decode(secretText), !secretData.isEmpty else { return nil }
        let cleanIssuer = issuer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanAccount = account?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard kind != .steam else {
            let token = OTPToken(
                issuer: cleanIssuer.isEmpty ? ImportExportService.steamIssuer : cleanIssuer,
                account: cleanAccount,
                digits: OTPKind.steamDigits,
                sortOrder: Int(Date().timeIntervalSince1970),
                kind: .steam
            )
            return ImportedToken(token: token, secret: secretData)
        }

        let finalDigits = digits ?? 6
        let finalPeriod = period ?? 30
        guard kind.allowsDigits(finalDigits), finalPeriod > 0,
              let finalAlgorithm = parseAlgorithm(algorithm) else { return nil }
        let token = OTPToken(
            issuer: cleanIssuer,
            account: cleanAccount,
            digits: finalDigits,
            period: finalPeriod,
            algorithm: finalAlgorithm,
            sortOrder: Int(Date().timeIntervalSince1970),
            kind: kind,
            counter: kind == .hotp ? counter ?? 0 : 0
        )
        return ImportedToken(token: token, secret: secretData)
    }

    static func result(_ entries: [ImportedToken?]) throws -> ParsedLink {
        let tokens = entries.compactMap { $0 }
        let skipped = entries.count - tokens.count
        guard !tokens.isEmpty else {
            throw skipped > 0 ? ExternalImportError.nothingSupported(skipped) : ExternalImportError.noAccounts
        }
        return ParsedLink(tokens: tokens, unsupported: skipped)
    }

    static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func string(_ object: [String: Any], _ key: String) -> String? {
        object[key] as? String
    }

    static func int(_ object: [String: Any], _ key: String) -> Int? {
        (object[key] as? NSNumber)?.intValue
    }

    static func uint64(_ object: [String: Any], _ key: String) -> UInt64? {
        guard let number = object[key] as? NSNumber, number.int64Value >= 0 else { return nil }
        return number.uint64Value
    }

    private static func parseAlgorithm(_ raw: String?) -> OTPAlgorithm? {
        guard let raw, !raw.isEmpty else { return .sha1 }
        return OTPAlgorithm(rawValue: raw.uppercased().replacingOccurrences(of: "-", with: ""))
    }
}
