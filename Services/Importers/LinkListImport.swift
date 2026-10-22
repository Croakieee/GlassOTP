import Foundation

enum LinkListImport {
    private static let pattern = try! NSRegularExpression(pattern: "otpauth(?:-migration)?://[^\\s\"'<>]+", options: [.caseInsensitive])

    static func links(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    static func read(_ text: String) throws -> ParsedLink {
        let found = links(in: text)
        guard found.count != 1 else { return try ImportExportService.parseOtpauthOrMigration(found[0]) }
        guard !found.isEmpty else {
            return try ImportExportService.parseOtpauthOrMigration(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        var tokens: [ImportedToken] = []
        var skipped = 0
        for link in found {
            guard let parsed = try? ImportExportService.parseOtpauthOrMigration(link) else {
                skipped += 1
                continue
            }
            tokens += parsed.tokens
            skipped += parsed.unsupported
        }
        guard !tokens.isEmpty else { throw ExternalImportError.nothingSupported(skipped) }
        return ParsedLink(tokens: tokens, unsupported: skipped)
    }
}
