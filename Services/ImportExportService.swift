import Foundation

struct ImportedToken {
    let token: OTPToken
    let secret: Data
}

enum ImportError: Error, LocalizedError {
    case invalidURL
    case unsupportedType
    case missingSecret
    case badBase32
    case badDigits
    case badPeriod
    case badAlgorithm

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid link."
        case .unsupportedType: return "Supported: otpauth://totp/… and otpauth-migration://…"
        case .missingSecret: return "Missing secret parameter."
        case .badBase32: return "Failed to decode the secret (Base32)."
        case .badDigits: return "Invalid digits value."
        case .badPeriod: return "Invalid period value."
        case .badAlgorithm: return "Invalid algorithm value."
        }
    }
}

struct ImportExportService {

    // Универсальный вход: обычная otpauth или migration-ссылка
    static func parseOtpauthOrMigration(_ urlString: String) throws -> [ImportedToken] {
        guard let url = URL(string: urlString) else { throw ImportError.invalidURL }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "otpauth" {
            return [try parseOtpauth(urlString)]
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
        guard url.host?.lowercased() == "totp" else { throw ImportError.unsupportedType }

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
        guard let secret = Base32.decode(secretStr) else { throw ImportError.badBase32 }

        let issuerParam = q["issuer"]?.removingPercentEncoding ?? ""
        let accountParam = q["account"]?.removingPercentEncoding ?? ""
        let issuer = issuerParam.isEmpty ? issuerFromLabel : issuerParam
        let account = accountParam.isEmpty ? accountFromLabel : accountParam

        let digits: Int = {
            if let dStr = q["digits"], let d = Int(dStr), (d == 6 || d == 8) { return d }
            return 6
        }()
        guard digits == 6 || digits == 8 else { throw ImportError.badDigits }

        let period: Int = {
            if let pStr = q["period"], let p = Int(pStr), p > 0 { return p }
            return 30
        }()
        guard period > 0 else { throw ImportError.badPeriod }

        let algorithm: OTPAlgorithm = {
            if let aStr = q["algorithm"]?.uppercased() {
                switch aStr {
                case "SHA1": return .sha1
                case "SHA256": return .sha256
                case "SHA512": return .sha512
                default: break
                }
            }
            return .sha1
        }()

        let token = OTPToken(
            issuer: issuer,
            account: account,
            digits: digits,
            period: period,
            algorithm: algorithm,
            isPinned: false,
            sortOrder: Int(Date().timeIntervalSince1970)
        )
        return ImportedToken(token: token, secret: secret)
    }

    // Google Authenticator export: otpauth-migration://offline?data=...
    private static func parseMigration(_ url: URL) throws -> [ImportedToken] {
        guard url.host?.lowercased() == "offline" else { throw ImportError.unsupportedType }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let dataParam = comps.queryItems?.first(where: { $0.name.lowercased() == "data" })?.value,
              !dataParam.isEmpty else {
            throw ImportError.invalidURL
        }

        let payload = try OtpauthMigrationDecoder.decode(base64URLData: dataParam)
        var result: [ImportedToken] = []

        for p in payload.params {
            // берем только TOTP (type==2)
            guard p.type == 2 else { continue }

            let algo: OTPAlgorithm = {
                switch p.algorithm {
                case 2: return .sha256
                case 3: return .sha512
                default: return .sha1
                }
            }()

            let digits: Int = (p.digits == 2) ? 8 : 6

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
                sortOrder: Int(Date().timeIntervalSince1970)
            )
            result.append(ImportedToken(token: token, secret: p.secret))
        }
        if result.isEmpty { throw ImportError.unsupportedType }
        return result
    }
    
    // MARK: - Dedup

    static func filterDuplicates(_ list: [ImportedToken], store: OTPStore) -> (added: [ImportedToken], skipped: Int) {

        var added: [ImportedToken] = []
        var skipped = 0

        for item in list {
            if store.isDuplicate(item.token, secret: item.secret) {
                skipped += 1
            } else {
                added.append(item)
            }
        }

        return (added, skipped)
    }
    
}
