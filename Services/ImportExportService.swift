import Foundation

struct ImportedToken {
    let token: OTPToken
    let secret: Data
    var recoveryCodes: [RecoveryCode] = []
}

struct ImportResult {
    let added: Int
    let duplicates: Int
    let failed: Int
}

enum ImportError: Error, LocalizedError {
    case invalidURL
    case unsupportedType
    case missingSecret
    case badBase32
    case badDigits
    case badPeriod
    case badAlgorithm
    case badCounter
    case noSupportedTokens
    case missingName

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid link."
        case .unsupportedType: return "Supported: otpauth://totp/…, otpauth://hotp/…, otpauth://steam/… and otpauth-migration://…"
        case .missingSecret: return "Missing secret parameter."
        case .badBase32: return "Failed to decode the secret (Base32)."
        case .badDigits: return "Only 6- or 8-digit codes are supported."
        case .badPeriod: return "The period must be a whole number of seconds greater than 0."
        case .badAlgorithm: return "Unsupported algorithm. Use SHA1, SHA256 or SHA512."
        case .badCounter: return "The counter must be a whole number of 0 or more."
        case .noSupportedTokens:
            return "None of these accounts can be added: only TOTP and HOTP codes with SHA1/SHA256/SHA512 and 6 or 8 digits are supported."
        case .missingName: return "Enter an issuer or an account name."
        }
    }
}

struct ParsedLink {
    let tokens: [ImportedToken]
    let unsupported: Int
}

struct ImportExportService {

    // Универсальный вход: обычная otpauth или migration-ссылка
    static func parseOtpauthOrMigration(_ urlString: String) throws -> ParsedLink {
        guard let url = URL(string: urlString) else { throw ImportError.invalidURL }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "otpauth" {
            return ParsedLink(tokens: [try parseOtpauth(urlString)], unsupported: 0)
        } else if scheme == "otpauth-migration" {
            return try parseMigration(url)
        } else {
            throw ImportError.unsupportedType
        }
    }

    // Обычная otpauth://totp/...
    static func parseOtpauth(_ urlString: String) throws -> ImportedToken {
        guard let url = URL(string: urlString) else { throw ImportError.invalidURL }
        guard url.scheme?.lowercased() == "otpauth" else { throw ImportError.invalidURL }
        guard let declaredKind = OTPKind(rawValue: url.host?.lowercased() ?? "") else { throw ImportError.unsupportedType }

        let rawLabel = url.path.removingPercentEncoding?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        var issuerFromLabel = ""
        var accountFromLabel = ""
        if !rawLabel.isEmpty {
            if let range = rawLabel.range(of: ":") {
                issuerFromLabel = String(rawLabel[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                accountFromLabel = String(rawLabel[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else {
                accountFromLabel = rawLabel
            }
        }

        var q: [String: String] = [:]
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems?.forEach { item in
                q[item.name.lowercased()] = item.value ?? ""
            }
        }

        guard let secretStr = q["secret"], !secretStr.isEmpty else { throw ImportError.missingSecret }
        guard let secret = Base32.decode(secretStr), !secret.isEmpty else { throw ImportError.badBase32 }

        let issuerParam = q["issuer"]?.removingPercentEncoding ?? ""
        let accountParam = q["account"]?.removingPercentEncoding ?? ""
        let issuer = issuerParam.isEmpty ? issuerFromLabel : issuerParam
        let account = accountParam.isEmpty ? accountFromLabel : accountParam
        let kind = isSteam(declaredKind, issuer: issuer, query: q) ? OTPKind.steam : declaredKind

        guard kind != .steam else {
            let token = OTPToken(
                issuer: issuer.isEmpty ? steamIssuer : issuer,
                account: account,
                digits: OTPKind.steamDigits,
                sortOrder: Int(Date().timeIntervalSince1970),
                kind: .steam
            )
            return ImportedToken(token: token, secret: secret)
        }

        guard let digits = value(q["digits"], default: 6, { Int($0).flatMap { [6, 8].contains($0) ? $0 : nil } }) else {
            throw ImportError.badDigits
        }
        let periodParam = kind == .totp ? q["period"] : nil
        guard let period = value(periodParam, default: 30, { Int($0).flatMap { $0 > 0 ? $0 : nil } }) else {
            throw ImportError.badPeriod
        }
        let counterParam = kind == .hotp ? q["counter"] : nil
        guard let counter = value(counterParam, default: UInt64(0), { UInt64($0) }) else {
            throw ImportError.badCounter
        }
        guard let algorithm = value(q["algorithm"], default: OTPAlgorithm.sha1, { OTPAlgorithm(rawValue: $0.uppercased()) }) else {
            throw ImportError.badAlgorithm
        }

        let token = OTPToken(
            issuer: issuer,
            account: account,
            digits: digits,
            period: period,
            algorithm: algorithm,
            isPinned: false,
            sortOrder: Int(Date().timeIntervalSince1970),
            kind: kind,
            counter: counter
        )
        return ImportedToken(token: token, secret: secret)
    }

    // Google Authenticator export: otpauth-migration://offline?data=...
    private static func parseMigration(_ url: URL) throws -> ParsedLink {
        guard url.host?.lowercased() == "offline" else { throw ImportError.unsupportedType }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let dataParam = comps.queryItems?.first(where: { $0.name.lowercased() == "data" })?.value,
              !dataParam.isEmpty else {
            throw ImportError.invalidURL
        }

        let payload = try OtpauthMigrationDecoder.decode(base64URLData: dataParam)
        var result: [ImportedToken] = []
        var unsupported = 0

        for p in payload.params {
            let algo: OTPAlgorithm?
            switch p.algorithm {
            case 0, 1: algo = .sha1
            case 2: algo = .sha256
            case 3: algo = .sha512
            default: algo = nil
            }
            let digits: Int?
            switch p.digits {
            case 0, 1: digits = 6
            case 2: digits = 8
            default: digits = nil
            }
            let kind: OTPKind?
            switch p.type {
            case 1: kind = .hotp
            case 2: kind = .totp
            default: kind = nil
            }
            guard let kind, !p.secret.isEmpty, let algo, let digits else {
                unsupported += 1
                continue
            }

            // Иногда issuer пуст, а name в формате "Issuer:Account"
            var issuer = p.issuer
            var account = p.name
            if issuer.isEmpty, let r = p.name.range(of: ":"), !p.name.hasPrefix(":") {
                issuer = String(p.name[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                account = String(p.name[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            }

            let token = OTPToken(
                issuer: issuer,
                account: account,
                digits: digits,
                period: 30,   // migration не передаёт period; дефолт 30
                algorithm: algo,
                isPinned: false,
                sortOrder: Int(Date().timeIntervalSince1970),
                kind: kind,
                counter: kind == .hotp ? p.counter : 0
            )
            result.append(ImportedToken(token: token, secret: p.secret))
        }
        if result.isEmpty { throw ImportError.noSupportedTokens }
        return ParsedLink(tokens: result, unsupported: unsupported)
    }

    static let steamIssuer = "Steam"

    private static func isSteam(_ kind: OTPKind, issuer: String, query: [String: String]) -> Bool {
        guard kind == .totp else { return kind == .steam }
        if query["encoder"]?.lowercased() == steamIssuer.lowercased() { return true }
        let digits = query["digits"] ?? ""
        return issuer.caseInsensitiveCompare(steamIssuer) == .orderedSame
            && (digits.isEmpty || digits == String(OTPKind.steamDigits))
    }

    private static func value<T>(_ raw: String?, default fallback: T, _ parse: (String) -> T?) -> T? {
        guard let raw, !raw.isEmpty else { return fallback }
        return parse(raw)
    }

}
