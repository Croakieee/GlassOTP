import Foundation

struct PersistenceService {
    private static let key = "GlassOTP.tokens.v1"

    static func save(tokens: [OTPToken]) {
        do {
            let data = try JSONEncoder().encode(tokens)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            // ignore: в худшем случае токены не сохранятся
        }
    }

    static func load() -> [OTPToken] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([OTPToken].self, from: data)
        } catch {
            return []
        }
    }

    /// Один раз засеиваем демо, если сохранённых нет
    static func firstRunSeedIfNeeded() -> [OTPToken] {
        let existing = load()
        if !existing.isEmpty { return existing }

        // seed демо-токены (без секретов — секреты кладём в кейчейн)
        var seeded: [OTPToken] = []

        func make(issuer: String, account: String, base32: String, order: Int, pinned: Bool = false) {
            let id = UUID()
            let token = OTPToken(
                id: id,
                issuer: issuer,
                account: account,
                digits: 6,
                period: 30,
                algorithm: .sha1,
                isPinned: pinned,
                sortOrder: order
            )
            seeded.append(token)
            // секрет в кейчейн
            if let secret = Base32.decode(base32) {
                try? KeychainService.setSecret(secret, for: id)
            }
        }

        make(issuer: "GitHub",  account: "you@example.com", base32: "JBSWY3DPEHPK3PXP", order: 0, pinned: true)
        make(issuer: "Binance", account: "trader@desk",    base32: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", order: 1)
        make(issuer: "Google",  account: "alt@account",    base32: "MFRGGZDFMZTWQ2LK", order: 2)

        save(tokens: seeded)
        return seeded
    }
}
