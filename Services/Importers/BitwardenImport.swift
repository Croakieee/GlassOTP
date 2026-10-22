import Foundation

enum BitwardenImport {
    private static let totpColumn = "login_totp"
    private static let steamScheme = "steam://"

    static func matches(_ json: [String: Any]) -> Bool {
        json["encrypted"] is Bool && (json["items"] != nil || json["data"] != nil || json["passwordProtected"] != nil)
    }

    static func matchesCSV(_ text: String) -> Bool {
        guard let header = rows(String(text.prefix(4096))).first else { return false }
        return header.contains(totpColumn)
    }

    static func read(_ json: [String: Any]) throws -> ParsedLink {
        guard json["encrypted"] as? Bool != true else { throw ExternalImportError.bitwardenEncrypted }
        let items = json["items"] as? [[String: Any]] ?? []
        let entries = items.flatMap { item -> [ImportedToken?] in
            let login = item["login"] as? [String: Any] ?? [:]
            guard let totp = ExternalImport.string(login, "totp"), !totp.isEmpty else { return [] }
            return convert(totp, name: ExternalImport.string(item, "name"), username: ExternalImport.string(login, "username"))
        }
        return try ExternalImport.result(entries)
    }

    static func readCSV(_ text: String) throws -> ParsedLink {
        let table = rows(text)
        guard let header = table.first, let totpIndex = header.firstIndex(of: totpColumn) else { throw ExternalImportError.damaged }
        let nameIndex = header.firstIndex(of: "name")
        let userIndex = header.firstIndex(of: "login_username")
        func cell(_ row: [String], _ index: Int?) -> String? {
            guard let index, row.indices.contains(index) else { return nil }
            return row[index]
        }
        let entries = table.dropFirst().flatMap { row -> [ImportedToken?] in
            guard let totp = cell(row, totpIndex), !totp.isEmpty else { return [] }
            return convert(totp, name: cell(row, nameIndex), username: cell(row, userIndex))
        }
        return try ExternalImport.result(entries)
    }

    private static func convert(_ totp: String, name: String?, username: String?) -> [ImportedToken?] {
        let value = totp.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("otpauth") {
            guard let parsed = try? ImportExportService.parseOtpauthOrMigration(value) else { return [nil] }
            return parsed.tokens.map { named($0, name: name, username: username) } + Array(repeating: nil, count: parsed.unsupported)
        }
        if value.lowercased().hasPrefix(steamScheme) {
            return [ExternalImport.entry(issuer: ImportExportService.steamIssuer, account: username ?? name,
                                         secret: String(value.dropFirst(steamScheme.count)), kind: .steam,
                                         digits: nil, period: nil, algorithm: nil, counter: nil)]
        }
        return [ExternalImport.entry(issuer: name, account: username, secret: value, kind: .totp,
                                     digits: nil, period: nil, algorithm: nil, counter: nil)]
    }

    private static func named(_ imported: ImportedToken, name: String?, username: String?) -> ImportedToken {
        guard imported.token.issuer.isEmpty && imported.token.account.isEmpty else { return imported }
        var token = imported.token
        token.issuer = name ?? ""
        token.account = username ?? ""
        return ImportedToken(token: token, secret: imported.secret, recoveryCodes: imported.recoveryCodes)
    }

    static func rows(_ text: String) -> [[String]] {
        let chars = Array(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = 0
        while index < chars.count {
            let char = chars[index]
            index += 1
            if quoted {
                if char != "\"" {
                    field.append(char)
                } else if index < chars.count && chars[index] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    quoted = false
                }
                continue
            }
            switch char {
            case "\"":
                quoted = true
            case ",":
                row.append(field)
                field = ""
            case "\n", "\r\n", "\r":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            default:
                field.append(char)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
