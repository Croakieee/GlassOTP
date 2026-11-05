import Foundation

enum LinkListImport {
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?)]}")
    private static let pattern = try! NSRegularExpression(pattern: "otpauth(?:-migration)?://[^\\s\"'<>]+", options: [.caseInsensitive])

    static func links(in text: String) -> [String] {
        text.components(separatedBy: .newlines).flatMap { line -> [String] in
            let range = NSRange(line.startIndex..., in: line)
            let found = pattern.matches(in: line, range: range).compactMap { match in
                Range(match.range, in: line).map { String(line[$0]).trimmingCharacters(in: trailingPunctuation) }
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard found.count == 1, trimmed != found[0], trimmed.lowercased().hasPrefix("otpauth"),
                  (try? ImportExportService.parseOtpauthOrMigration(found[0])) == nil,
                  (try? ImportExportService.parseOtpauthOrMigration(trimmed)) != nil else { return found }
            return [trimmed]
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
