import Foundation
import Combine

final class OTPStore: ObservableObject {
    @Published private(set) var tokens: [OTPToken] = []
    @Published var query: String = ""

    let timer = TimeStepTimer()

    // КЕШ СЕКРЕТОВ (добавлено)
    private var secretCache: [UUID: Data] = [:]

    // MARK: - Init

    init(tokens: [OTPToken] = []) {
        if tokens.isEmpty {
            self.tokens = OTPStore.sorted(PersistenceService.load())
        } else {
            self.tokens = OTPStore.sorted(tokens)
        }
    }

    // MARK: - Derived

    func filteredTokens() -> [OTPToken] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return tokens }
        return tokens.filter {
            $0.issuer.lowercased().contains(q) ||
            $0.account.lowercased().contains(q)
        }
    }

    // ИСПРАВЛЕНО (использует кеш)
    func code(for token: OTPToken) -> String {

        if let cached = secretCache[token.id] {
            return TOTPGenerator.code(for: timer.now, token: token, secret: cached)
        }

        do {
            let secret = try KeychainService.getSecret(for: token.id)
            secretCache[token.id] = secret
            return TOTPGenerator.code(for: timer.now, token: token, secret: secret)
        } catch {
            return "------"
        }
    }

    func remaining(for token: OTPToken) -> Int {
        TOTPGenerator.timeRemaining(for: timer.now, period: token.period)
    }

    // MARK: - Mutations (+ persist)

    func addImported(_ imported: ImportedToken) {
        try? KeychainService.setSecret(imported.secret, for: imported.token.id)
        secretCache[imported.token.id] = imported.secret
        tokens.append(imported.token)
        commit()
    }

    @discardableResult
    func addImportedMany(_ list: [ImportedToken]) -> Int {

        var addedCount = 0

        // создаём набор существующих ключей
        let existingKeys: Set<String> = Set(tokens.compactMap { token in

            guard let secret = try? KeychainService.getSecret(for: token.id) else {
                return nil
            }

            let issuer = token.issuer
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            let account = token.account
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            let secretBase32 = Base32.encode(secret)

            return "\(issuer)|\(account)|\(secretBase32)"
        })

        var mutableKeys = existingKeys

        for item in list {

            let issuer = item.token.issuer
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            let account = item.token.account
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            let secretBase32 = Base32.encode(item.secret)

            let key = "\(issuer)|\(account)|\(secretBase32)"

            // duplicate
            if mutableKeys.contains(key) {
                continue
            }

            try? KeychainService.setSecret(
                item.secret,
                for: item.token.id
            )

            secretCache[item.token.id] = item.secret
            tokens.append(item.token)

            mutableKeys.insert(key)

            addedCount += 1
        }

        if addedCount > 0 {
            commit()
        }

        return addedCount
    }

    func add(_ token: OTPToken) {
        tokens.append(token)
        commit()
    }

    func remove(_ tokenID: UUID) {
        if let idx = tokens.firstIndex(where: { $0.id == tokenID }) {
            let token = tokens[idx]
            tokens.remove(at: idx)
            try? KeychainService.deleteSecret(for: token.id)

            // очистка кеша
            secretCache[tokenID] = nil

            commit()
        }
    }

    func rename(_ tokenID: UUID, issuer: String, account: String) {
        guard let idx = tokens.firstIndex(where: { $0.id == tokenID }) else { return }
        var t = tokens[idx]
        t.issuer = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        t.account = account.trimmingCharacters(in: .whitespacesAndNewlines)
        tokens[idx] = t
        commit()
    }

    func togglePin(_ tokenID: UUID) {
        guard let idx = tokens.firstIndex(where: { $0.id == tokenID }) else { return }
        var t = tokens[idx]
        t.isPinned.toggle()
        if t.isPinned {
            let minOrder = tokens.map(\.sortOrder).min() ?? 0
            t.sortOrder = minOrder - 1
        }
        tokens[idx] = t
        commit()
    }

    private func commit() {
        tokens = OTPStore.sorted(tokens)
        PersistenceService.save(tokens: tokens)
    }

    // MARK: - Sorting

    private static func sorted(_ arr: [OTPToken]) -> [OTPToken] {
        arr.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.displayTitle.localizedCompare(rhs.displayTitle) == .orderedAscending
        }
    }

    static func sampleStore() -> OTPStore { OTPStore(tokens: []) }
    
    // MARK: - Secret editing

    func secret(for token: OTPToken) -> String? {
        guard let data = try? KeychainService.getSecret(for: token.id) else { return nil }
        return Base32.encode(data)
    }

    func updateSecret(for token: OTPToken, base32: String) throws {

        guard let decoded = Base32.decode(base32) else {
            throw ImportError.badBase32
        }

        try KeychainService.setSecret(decoded, for: token.id)

        // обновление кеша
        secretCache[token.id] = decoded

        objectWillChange.send()
    }
    
    // MARK: - Bulk

    func removeAllTokens() {
        for t in tokens {
            try? KeychainService.deleteSecret(for: t.id)
        }
        tokens.removeAll()
        secretCache.removeAll()
        commit()
    }

    func isDuplicate(_ token: OTPToken, secret: Data) -> Bool {
        for existing in tokens {
            if existing.issuer == token.issuer &&
               existing.account == token.account,
               let existingSecret = try? KeychainService.getSecret(for: existing.id),
               existingSecret == secret {
                return true
            }
        }
        return false
    }
    
}
