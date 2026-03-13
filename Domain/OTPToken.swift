import Foundation

struct OTPToken: Identifiable, Codable, Equatable {
    let id: UUID
    var issuer: String
    var account: String
    var digits: Int         // 6 или 8
    var period: Int         // обычно 30
    var algorithm: OTPAlgorithm
    var isPinned: Bool
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        issuer: String,
        account: String,
        digits: Int = 6,
        period: Int = 30,
        algorithm: OTPAlgorithm = .sha1,
        isPinned: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.issuer = issuer
        self.account = account
        self.digits = digits
        self.period = period
        self.algorithm = algorithm
        self.isPinned = isPinned
        self.sortOrder = sortOrder
    }

    var displayTitle: String {
        if issuer.isEmpty { return account }
        if account.isEmpty { return issuer }
        return "\(issuer) · \(account)"
    }
}
