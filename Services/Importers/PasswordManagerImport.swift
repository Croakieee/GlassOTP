import Foundation
import Compression

enum PasswordManagerImport {
    static let onePasswordExtension = "1pux"
    static let maxOnePasswordSize = 256 * 1024 * 1024
    private static let onePasswordEntry = "export.data"
    private static let maxEntrySize = 64 * 1024 * 1024

    private static let otpColumns = ["otpauth", "otp auth", "totp", "otp", "one-time password", "onetimepassword", "2fa"]
    private static let titleColumns = ["title", "name"]
    private static let userColumns = ["username", "user name", "login", "login name", "email"]
    private static let urlColumns = ["url", "website", "web site", "login_uri"]

    static func matchesCSV(_ text: String) -> Bool {
        guard let header = BitwardenImport.rows(String(text.prefix(4096))).first else { return false }
        return column(otpColumns, in: header) != nil
    }

    static func readCSV(_ text: String) throws -> ParsedLink {
        let table = BitwardenImport.rows(text)
        guard let header = table.first, let otpIndex = column(otpColumns, in: header) else { throw ExternalImportError.damaged }
        let titleIndex = column(titleColumns, in: header)
        let userIndex = column(userColumns, in: header)
        let urlIndex = column(urlColumns, in: header)
        func cell(_ row: [String], _ index: Int?) -> String? {
            guard let index, row.indices.contains(index) else { return nil }
            let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        let entries = table.dropFirst().flatMap { row -> [ImportedToken?] in
            guard let otp = cell(row, otpIndex) else { return [] }
            return convert(otp, title: cell(row, titleIndex) ?? host(cell(row, urlIndex)), username: cell(row, userIndex))
        }
        return try ExternalImport.result(entries)
    }

    static func isOnePassword(_ data: Data) -> Bool {
        data.starts(with: [0x50, 0x4b, 0x03, 0x04]) && (try? zipEntry(onePasswordEntry, in: data, extract: false)) != nil
    }

    static func readOnePassword(_ data: Data) throws -> ParsedLink {
        guard let exportData = try zipEntry(onePasswordEntry, in: data),
              let json = ExternalImport.jsonObject(exportData) else { throw ExternalImportError.damaged }
        let accounts = json["accounts"] as? [[String: Any]] ?? []
        let items = accounts
            .flatMap { $0["vaults"] as? [[String: Any]] ?? [] }
            .flatMap { $0["items"] as? [[String: Any]] ?? [] }
        let entries = items.flatMap { item -> [ImportedToken?] in
            let overview = item["overview"] as? [String: Any] ?? [:]
            let details = item["details"] as? [String: Any] ?? [:]
            let title = ExternalImport.string(overview, "title") ?? host(ExternalImport.string(overview, "url"))
            let loginFields = details["loginFields"] as? [[String: Any]] ?? []
            let username = loginFields.first { ExternalImport.string($0, "designation") == "username" }
                .flatMap { ExternalImport.string($0, "value") } ?? ExternalImport.string(overview, "subtitle")
            let fields = (details["sections"] as? [[String: Any]] ?? []).flatMap { $0["fields"] as? [[String: Any]] ?? [] }
            return fields.compactMap { field -> String? in
                guard let value = field["value"] as? [String: Any], let totp = ExternalImport.string(value, "totp") else { return nil }
                let trimmed = totp.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .flatMap { convert($0, title: title, username: username) }
        }
        return try ExternalImport.result(entries)
    }

    private static func convert(_ otp: String, title: String?, username: String?) -> [ImportedToken?] {
        if otp.lowercased().hasPrefix("otpauth") {
            guard let parsed = try? ImportExportService.parseOtpauthOrMigration(otp) else { return [nil] }
            return parsed.tokens.map { named($0, title: title, username: username) } + Array(repeating: nil, count: parsed.unsupported)
        }
        return [ExternalImport.entry(issuer: title, account: username, secret: otp, kind: .totp,
                                     digits: nil, period: nil, algorithm: nil, counter: nil)]
    }

    private static func named(_ imported: ImportedToken, title: String?, username: String?) -> ImportedToken {
        var token = imported.token
        if token.issuer.isEmpty { token.issuer = title ?? "" }
        if token.account.isEmpty { token.account = username ?? "" }
        return ImportedToken(token: token, secret: imported.secret, recoveryCodes: imported.recoveryCodes)
    }

    private static func column(_ names: [String], in header: [String]) -> Int? {
        let normalized = header.map {
            $0.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        for name in names {
            if let index = normalized.firstIndex(of: name) { return index }
        }
        return nil
    }

    private static func host(_ url: String?) -> String? {
        guard let url, !url.isEmpty else { return nil }
        let withScheme = url.contains("://") ? url : "https://\(url)"
        guard var host = URL(string: withScheme)?.host, !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    static func zipEntry(_ name: String, in data: Data, extract: Bool = true) throws -> Data? {
        let base = data.startIndex
        let length = data.count
        func u16(_ at: Int) -> Int { Int(data[base + at]) | Int(data[base + at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        guard length >= 22 else { return nil }
        var end = length - 22
        let lowest = max(0, length - 22 - 65_535)
        while end >= lowest && u32(end) != 0x0605_4b50 { end -= 1 }
        guard end >= lowest else { return nil }
        let count = u16(end + 10)
        var cursor = u32(end + 16)
        for _ in 0..<count {
            guard cursor + 46 <= length, u32(cursor) == 0x0201_4b50 else { throw ExternalImportError.damaged }
            let method = u16(cursor + 10)
            let compressedSize = u32(cursor + 20)
            let size = u32(cursor + 24)
            let nameLength = u16(cursor + 28)
            let extraLength = u16(cursor + 30)
            let commentLength = u16(cursor + 32)
            let localOffset = u32(cursor + 42)
            guard cursor + 46 + nameLength <= length else { throw ExternalImportError.damaged }
            let entryName = String(decoding: data[(base + cursor + 46)..<(base + cursor + 46 + nameLength)], as: UTF8.self)
            cursor += 46 + nameLength + extraLength + commentLength
            guard entryName == name else { continue }
            guard extract else { return Data() }
            guard size <= maxEntrySize, localOffset + 30 <= length, u32(localOffset) == 0x0403_4b50 else {
                throw ExternalImportError.damaged
            }
            let start = localOffset + 30 + u16(localOffset + 26) + u16(localOffset + 28)
            guard start + compressedSize <= length else { throw ExternalImportError.damaged }
            let payload = data.subdata(in: (base + start)..<(base + start + compressedSize))
            switch method {
            case 0:
                return payload
            case 8:
                return try inflate(payload, size: size)
            default:
                throw ExternalImportError.damaged
            }
        }
        return nil
    }

    private static func inflate(_ data: Data, size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                compression_decode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, size,
                                          input.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw ExternalImportError.damaged }
        return output
    }
}
