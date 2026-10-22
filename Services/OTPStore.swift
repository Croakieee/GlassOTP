import Foundation
import Combine

final class OTPStore: ObservableObject {
    @Published private(set) var tokens: [OTPToken] = []
    @Published var query: String = ""

    @Published private(set) var vaultCorrupted: Bool = false

    @Published private(set) var keychainUnavailable: Bool = false

    @Published private(set) var tokenListUnreadable: Bool = false

    let timer = TimeStepTimer()

    // КЕШ СЕКРЕТОВ (добавлено)
    private var secretCache: [UUID: Data] = [:]

    // MARK: - Init

    init(tokens: [OTPToken] = []) {
        guard tokens.isEmpty else {
            self.tokens = OTPStore.sorted(tokens)
            return
        }

        let saved = PersistenceService.load()
        let loaded = saved.tokens
        self.tokenListUnreadable = saved.hadUnreadableData
        do {
            let ids = try KeychainService.storedSecretIDs()
            self.tokens = OTPStore.sorted(loaded.filter { ids.contains($0.id.uuidString) })
        } catch {
            self.tokens = OTPStore.sorted(loaded)
            applyVaultError(error)
        }
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
        if let cached = secretCache[token.id] {
            return TOTPGenerator.code(for: timer.now, token: token, secret: cached)
        }

        guard let secret = try? KeychainService.getSecret(for: token.id) else { return nil }
        secretCache[token.id] = secret
        return TOTPGenerator.code(for: timer.now, token: token, secret: secret)
    }

    func remaining(for token: OTPToken) -> Int {
        TOTPGenerator.timeRemaining(for: timer.now, period: token.period)
    }

    // MARK: - Mutations (+ persist)

    @discardableResult
    func addImportedMany(_ list: [ImportedToken]) -> ImportResult {
        var contentKeys = Set<String>()
        var secretsByID: [UUID: Data] = [:]
        for token in tokens {
            guard let secret = try? KeychainService.getSecret(for: token.id) else { continue }
            secretsByID[token.id] = secret
            contentKeys.insert(OTPStore.contentKey(token, secret: secret))
        }
        var usedIDs = Set(tokens.map(\.id))

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
                try KeychainService.setSecret(item.secret, for: token.id)
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
        secretCache.removeAll()
        vaultCorrupted = false
        keychainUnavailable = false
        tokenListUnreadable = false
        commit()
    }

}
