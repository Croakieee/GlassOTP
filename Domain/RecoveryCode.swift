import Foundation

struct RecoveryCode: Codable, Equatable, Identifiable {
    let id: UUID
    let code: String
    var usedAt: Date?
    var note: String?

    init(id: UUID = UUID(), code: String, usedAt: Date? = nil, note: String? = nil) {
        self.id = id
        self.code = code
        self.usedAt = usedAt
        self.note = note
    }

    var isUsed: Bool { usedAt != nil }

    func toggledUsed(at date: Date = Date()) -> RecoveryCode {
        RecoveryCode(id: id, code: code, usedAt: isUsed ? nil : date, note: note)
    }
}

struct RecoveryCodeMerge: Equatable {
    let codes: [RecoveryCode]
    let added: Int
    let skipped: Int
}

extension RecoveryCode {
    static let maxCount = 100
    static let maxLength = 128

    private static let separators = try! NSRegularExpression(pattern: "[\\n\\r,;\\t]+| {2,}")
    private static let listMarker = try! NSRegularExpression(pattern: "^(?:\\d{1,3}[.)]|[-•*])\\s+")
    private static let innerSpaces = try! NSRegularExpression(pattern: "\\s+")

    static func candidates(in text: String) -> [String] {
        let marked = replacing(separators, in: text, with: "\n")
        return marked
            .components(separatedBy: "\n")
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let unmarked = replacing(listMarker, in: trimmed, with: "")
                return replacing(innerSpaces, in: unmarked, with: " ")
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
    }

    static func merging(_ text: String, into existing: [RecoveryCode]) -> RecoveryCodeMerge {
        var known = Set(existing.map(\.code))
        var accepted: [RecoveryCode] = []
        var skipped = 0
        for candidate in candidates(in: text) {
            let fits = candidate.count <= maxLength && existing.count + accepted.count < maxCount
            guard fits, !known.contains(candidate) else {
                skipped += 1
                continue
            }
            known.insert(candidate)
            accepted.append(RecoveryCode(code: candidate))
        }
        return RecoveryCodeMerge(codes: existing + accepted, added: accepted.count, skipped: skipped)
    }

    static func encode(_ codes: [RecoveryCode]) throws -> Data? {
        codes.isEmpty ? nil : try JSONEncoder().encode(codes)
    }

    static func decode(_ data: Data?) throws -> [RecoveryCode] {
        guard let data else { return [] }
        return try JSONDecoder().decode([RecoveryCode].self, from: data)
    }

    private static func replacing(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
