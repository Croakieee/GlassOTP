import Foundation

enum OTPKind: String, Codable, CaseIterable {
    case totp
    case hotp
    case steam

    static let steamDigits = 5

    var isTimeBased: Bool { self != .hotp }

    func allowsDigits(_ digits: Int) -> Bool {
        self == .steam ? digits == Self.steamDigits : digits == 6 || digits == 8
    }
}

struct OTPToken: Identifiable, Codable, Equatable {
    let id: UUID
    var issuer: String
    var account: String
    var digits: Int         // 6 или 8
    var period: Int         // обычно 30
    var algorithm: OTPAlgorithm
    var isPinned: Bool
    var sortOrder: Int
    var sortOrderBeforePin: Int?
    var recentUses: [Date]
    var isProtected: Bool
    var kind: OTPKind
    var counter: UInt64

    init(
        id: UUID = UUID(),
        issuer: String,
        account: String,
        digits: Int = 6,
        period: Int = 30,
        algorithm: OTPAlgorithm = .sha1,
        isPinned: Bool = false,
        sortOrder: Int = 0,
        sortOrderBeforePin: Int? = nil,
        recentUses: [Date] = [],
        isProtected: Bool = false,
        kind: OTPKind = .totp,
        counter: UInt64 = 0
    ) {
        self.id = id
        self.issuer = issuer
        self.account = account
        self.digits = digits
        self.period = period
        self.algorithm = algorithm
        self.isPinned = isPinned
        self.sortOrder = sortOrder
        self.sortOrderBeforePin = sortOrderBeforePin
        self.recentUses = recentUses
        self.isProtected = isProtected
        self.kind = kind
        self.counter = counter
    }

    var displayTitle: String {
        if issuer.isEmpty { return account }
        if account.isEmpty { return issuer }
        return "\(issuer) · \(account)"
    }

    func withNewID() -> OTPToken {
        OTPToken(
            issuer: issuer,
            account: account,
            digits: digits,
            period: period,
            algorithm: algorithm,
            isPinned: isPinned,
            sortOrder: sortOrder,
            sortOrderBeforePin: sortOrderBeforePin,
            recentUses: recentUses,
            isProtected: isProtected,
            kind: kind,
            counter: counter
        )
    }
}

extension OTPToken {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let kind = try c.decodeIfPresent(OTPKind.self, forKey: .kind) ?? .totp
        let digits = try c.decodeIfPresent(Int.self, forKey: .digits) ?? (kind == .steam ? OTPKind.steamDigits : 6)
        guard kind.allowsDigits(digits) else {
            throw DecodingError.dataCorruptedError(forKey: .digits, in: c, debugDescription: "digits must be 6 or 8, or 5 for Steam")
        }
        let period = try c.decodeIfPresent(Int.self, forKey: .period) ?? 30
        guard period > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .period, in: c, debugDescription: "period must be positive")
        }

        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            issuer: try c.decodeIfPresent(String.self, forKey: .issuer) ?? "",
            account: try c.decodeIfPresent(String.self, forKey: .account) ?? "",
            digits: digits,
            period: period,
            algorithm: try c.decodeIfPresent(OTPAlgorithm.self, forKey: .algorithm) ?? .sha1,
            isPinned: try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false,
            sortOrder: try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0,
            sortOrderBeforePin: try c.decodeIfPresent(Int.self, forKey: .sortOrderBeforePin),
            recentUses: try c.decodeIfPresent([Date].self, forKey: .recentUses) ?? [],
            isProtected: try c.decodeIfPresent(Bool.self, forKey: .isProtected) ?? false,
            kind: kind,
            counter: try c.decodeIfPresent(UInt64.self, forKey: .counter) ?? 0
        )
    }
}

struct TrashedToken: Codable, Equatable, Identifiable {
    let token: OTPToken
    let deletedAt: Date

    var id: UUID { token.id }
}
