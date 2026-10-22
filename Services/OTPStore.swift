import Foundation
import Combine

final class OTPStore: ObservableObject {
    @Published private(set) var tokens: [OTPToken] = []
    @Published private(set) var trash: [TrashedToken] = []
    @Published var query: String = ""

    @Published private(set) var vaultCorrupted: Bool = false

    @Published private(set) var keychainUnavailable: Bool = false

    @Published private(set) var tokenListUnreadable: Bool = false

    let timer = TimeStepTimer()

    var sortByUsage: Bool = false {
        didSet {
            if sortByUsage != oldValue { refreshOrder() }
        }
    }

    var hotpAdvancesOnCopy: Bool = true

    static let trashRetention: TimeInterval = 30 * 24 * 60 * 60
    private static let usageHistoryLimit = 20
    private static let usageHalfLife: TimeInterval = 14 * 24 * 60 * 60

    // КЕШ СЕКРЕТОВ (добавлено)
    private var secretCache: [UUID: Data] = [:]

    // MARK: - Init

    init(tokens: [OTPToken] = []) {
        guard tokens.isEmpty else {
            self.tokens = OTPStore.sorted(tokens, byUsage: false, now: Date())
            return
        }

        let saved = PersistenceService.load()
        let loaded = saved.tokens
        let savedTrash = PersistenceService.loadTrash()
        self.tokenListUnreadable = saved.hadUnreadableData
        do {
            let ids = try KeychainService.storedSecretIDs()
            self.tokens = OTPStore.sorted(loaded.filter { ids.contains($0.id.uuidString) }, byUsage: false, now: Date())
            self.trash = savedTrash.filter { ids.contains($0.id.uuidString) }
        } catch {
            self.tokens = OTPStore.sorted(loaded, byUsage: false, now: Date())
            self.trash = savedTrash
            applyVaultError(error)
        }
        purgeExpiredTrash()
    }

    func retryKeychainAccess() {
        KeychainService.retryAccess()
        do {
            _ = try KeychainService.storedSecretIDs()
            keychainUnavailable = false
            vaultCorrupted = false
        } catch {
            applyVaultError(error)
        }
        objectWillChange.send()
    }

    private func applyVaultError(_ error: Error) {
        if case KeychainError.decode = error {
            vaultCorrupted = true
            keychainUnavailable = false
        } else {
            keychainUnavailable = true
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

    func code(for token: OTPToken) -> String? {
        code(for: token, at: timer.now)
    }

    func nextCode(for token: OTPToken) -> String? {
        guard token.kind.isTimeBased else { return nil }
        return code(for: token, at: timer.now.addingTimeInterval(TimeInterval(token.period)))
    }

    private func code(for token: OTPToken, at date: Date) -> String? {
        guard let secret = cachedSecret(of: token) else { return nil }
        switch token.kind {
        case .totp, .steam:
            return TOTPGenerator.code(for: date, token: token, secret: secret)
        case .hotp:
            let current = tokens.first { $0.id == token.id } ?? token
            return TOTPGenerator.code(counter: current.counter, token: current, secret: secret)
        }
    }

    private func cachedSecret(of token: OTPToken) -> Data? {
        if let cached = secretCache[token.id] {
            return cached
        }
        guard let secret = try? KeychainService.getSecret(for: token.id) else { return nil }
        secretCache[token.id] = secret
        return secret
    }

    func remaining(for token: OTPToken) -> Int {
        TOTPGenerator.timeRemaining(for: timer.now, period: token.period)
    }

    // MARK: - Mutations (+ persist)

    @discardableResult
    func addImportedMany(_ list: [ImportedToken]) -> ImportResult {
        var (contentKeys, secretsByID) = existingContent()
        var usedIDs = Set(tokens.map(\.id)).union(trash.map(\.id))

        var added = 0
        var duplicates = 0
        var failed = 0

        for item in list {
            let named = OTPStore.namedIfBlank(item.token)
            let key = OTPStore.contentKey(named, secret: item.secret)
            let sameTokenRenamed = secretsByID[named.id] == item.secret
            if contentKeys.contains(key) || sameTokenRenamed {
                duplicates += 1
                continue
            }

            let token = usedIDs.contains(named.id) ? named.withNewID() : named

            do {
                let codes = try RecoveryCode.encode(item.recoveryCodes)
                try KeychainService.setSecret(item.secret, for: token.id, recoveryCodes: codes)
            } catch {
                failed += 1
                continue
            }

            secretCache[token.id] = item.secret
            tokens.append(token)
            contentKeys.insert(key)
            usedIDs.insert(token.id)
            secretsByID[token.id] = item.secret
            added += 1
        }

        if added > 0 {
            commit()
        }

        return ImportResult(added: added, duplicates: duplicates, failed: failed)
    }

    func newAccounts(in list: [ImportedToken]) -> [ImportedToken] {
        var knownSecrets = Set(existingContent().secrets.values)
        return list.filter { knownSecrets.insert($0.secret).inserted }
    }

    private func existingContent() -> (keys: Set<String>, secrets: [UUID: Data]) {
        var contentKeys = Set<String>()
        var secretsByID: [UUID: Data] = [:]
        for token in tokens {
            guard let secret = try? KeychainService.getSecret(for: token.id) else { continue }
            secretsByID[token.id] = secret
            contentKeys.insert(OTPStore.contentKey(token, secret: secret))
        }
        return (contentKeys, secretsByID)
    }

    static let unnamedIssuer = "Unnamed"

    private static func namedIfBlank(_ token: OTPToken) -> OTPToken {
        let isBlank = token.issuer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && token.account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard isBlank else { return token }
        var named = token
        named.issuer = unnamedIssuer
        return named
    }

    private static func contentKey(_ token: OTPToken, secret: Data) -> String {
        let issuer = token.issuer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let account = token.account.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(issuer)|\(account)|\(Base32.encode(secret))"
    }

    func remove(_ tokenID: UUID, at date: Date = Date()) {
        if let idx = tokens.firstIndex(where: { $0.id == tokenID }) {
            let token = tokens.remove(at: idx)

            // очистка кеша
            secretCache[tokenID] = nil

            trash.insert(TrashedToken(token: token, deletedAt: date), at: 0)
            PersistenceService.save(trash: trash)
            commit()
        }
    }

    func restore(_ tokenID: UUID) {
        guard let idx = trash.firstIndex(where: { $0.id == tokenID }) else { return }
        let item = trash.remove(at: idx)
        tokens.append(item.token)
        PersistenceService.save(trash: trash)
        commit()
    }

    func deletePermanently(_ tokenID: UUID) {
        guard let idx = trash.firstIndex(where: { $0.id == tokenID }) else { return }
        trash.remove(at: idx)
        try? KeychainService.deleteSecret(for: tokenID)
        PersistenceService.save(trash: trash)
    }

    func emptyTrash() {
        for item in trash {
            try? KeychainService.deleteSecret(for: item.id)
        }
        trash.removeAll()
        PersistenceService.save(trash: trash)
    }

    func purgeExpiredTrash(now: Date = Date()) {
        guard !vaultCorrupted, !keychainUnavailable else { return }
        let expired = trash.filter { now.timeIntervalSince($0.deletedAt) >= Self.trashRetention }
        guard !expired.isEmpty else { return }
        for item in expired {
            try? KeychainService.deleteSecret(for: item.id)
        }
        let expiredIDs = Set(expired.map(\.id))
        trash.removeAll { expiredIDs.contains($0.id) }
        PersistenceService.save(trash: trash)
    }

    func recoveryCodes(for tokenID: UUID) throws -> [RecoveryCode] {
        try RecoveryCode.decode(KeychainService.recoveryCodes(for: tokenID))
    }

    func saveRecoveryCodes(_ codes: [RecoveryCode], for tokenID: UUID) throws {
        try KeychainService.setRecoveryCodes(RecoveryCode.encode(codes), for: tokenID)
    }

    static func daysLeft(in item: TrashedToken, now: Date) -> Int {
        let remaining = trashRetention - now.timeIntervalSince(item.deletedAt)
        return max(0, Int(ceil(remaining / 86_400)))
    }

    func rename(_ tokenID: UUID, issuer: String, account: String) {
        let newIssuer = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        let newAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(newIssuer.isEmpty && newAccount.isEmpty),
              let idx = tokens.firstIndex(where: { $0.id == tokenID }) else { return }
        var t = tokens[idx]
        t.issuer = newIssuer
        t.account = newAccount
        tokens[idx] = t
        commit()
    }

    func togglePin(_ tokenID: UUID) {
        guard let idx = tokens.firstIndex(where: { $0.id == tokenID }) else { return }
        var t = tokens[idx]
        if t.isPinned {
            let lastUnpinned = tokens.filter { !$0.isPinned }.map(\.sortOrder).max() ?? 0
            t.sortOrder = t.sortOrderBeforePin ?? lastUnpinned + 1
            t.sortOrderBeforePin = nil
        } else {
            t.sortOrderBeforePin = t.sortOrder
            t.sortOrder = (tokens.map(\.sortOrder).min() ?? 0) - 1
        }
        t.isPinned.toggle()
        tokens[idx] = t
        commit()
    }

    func recordUse(_ tokenID: UUID, at date: Date = Date()) {
        guard let idx = tokens.firstIndex(where: { $0.id == tokenID }) else { return }
        var t = tokens[idx]
        t.recentUses = Array((t.recentUses + [date]).suffix(Self.usageHistoryLimit))
        if t.kind == .hotp && hotpAdvancesOnCopy {
            t.counter = Self.advanced(t.counter)
        }
        tokens[idx] = t
        PersistenceService.save(tokens: tokens)
    }

    func advanceCounter(_ tokenID: UUID) {
        guard let idx = tokens.firstIndex(where: { $0.id == tokenID }), tokens[idx].kind == .hotp else { return }
        var t = tokens[idx]
        t.counter = Self.advanced(t.counter)
        tokens[idx] = t
        PersistenceService.save(tokens: tokens)
    }

    private static func advanced(_ counter: UInt64) -> UInt64 {
        counter == .max ? counter : counter + 1
    }

    func setProtected(_ tokenID: UUID, _ isProtected: Bool) {
        guard let idx = tokens.firstIndex(where: { $0.id == tokenID }) else { return }
        var t = tokens[idx]
        t.isProtected = isProtected
        tokens[idx] = t
        PersistenceService.save(tokens: tokens)
    }

    func refreshOrder(now: Date = Date()) {
        tokens = OTPStore.sorted(tokens, byUsage: sortByUsage, now: now)
    }

    private func commit() {
        refreshOrder()
        PersistenceService.save(tokens: tokens)
    }

    // MARK: - Sorting

    static func usageScore(_ token: OTPToken, now: Date) -> Double {
        token.recentUses.reduce(0) { score, use in
            score + pow(0.5, max(0, now.timeIntervalSince(use)) / usageHalfLife)
        }
    }

    static func sorted(_ arr: [OTPToken], byUsage: Bool, now: Date) -> [OTPToken] {
        let scores = byUsage
            ? Dictionary(arr.map { ($0.id, usageScore($0, now: now)) }, uniquingKeysWith: { first, _ in first })
            : [:]
        return arr.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            if byUsage, !lhs.isPinned {
                let lhsScore = scores[lhs.id] ?? 0
                let rhsScore = scores[rhs.id] ?? 0
                if abs(lhsScore - rhsScore) > 0.000_001 {
                    return lhsScore > rhsScore
                }
            }
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.displayTitle.localizedCompare(rhs.displayTitle) == .orderedAscending
        }
    }

    // MARK: - Secret editing

    func secret(for token: OTPToken) -> String? {
        guard let data = try? KeychainService.getSecret(for: token.id) else { return nil }
        return Base32.encode(data)
    }

    func updateSecret(for token: OTPToken, base32: String) throws {

        guard let decoded = Base32.decode(base32), !decoded.isEmpty else {
            throw ImportError.badBase32
        }

        try KeychainService.setSecret(decoded, for: token.id)

        // обновление кеша
        secretCache[token.id] = decoded

        objectWillChange.send()
    }
    
    // MARK: - Bulk

    func removeAllTokens() throws {
        try KeychainService.removeAll()
        tokens.removeAll()
        trash.removeAll()
        PersistenceService.save(trash: trash)
        secretCache.removeAll()
        vaultCorrupted = false
        keychainUnavailable = false
        tokenListUnreadable = false
        commit()
    }

}
