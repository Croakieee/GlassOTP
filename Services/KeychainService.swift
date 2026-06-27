import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case add(OSStatus)
    case update(OSStatus)
    case copy(OSStatus)
    case delete(OSStatus)
    case notFound

    var errorDescription: String? {
        switch self {
        case .add(let s): return "Keychain add failed: \(s)"
        case .update(let s): return "Keychain update failed: \(s)"
        case .copy(let s): return "Keychain read failed: \(s)"
        case .delete(let s): return "Keychain delete failed: \(s)"
        case .notFound: return "Secret not found in Keychain."
        }
    }
}

/// All token secrets live in a SINGLE keychain item (a "vault" blob) instead of one
/// item per token.
///
/// Why: macOS guards each keychain item with an ACL tied to the app's *code identity*
/// (its code-signing designated requirement). With ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`,
/// no Team) that identity is just the binary's cdhash, which changes on every build/version.
/// So every update is a "different app" to the keychain, and macOS prompts for the login
/// password to authorise access — once *per item*. N tokens ⇒ N prompts on every update.
///
/// Consolidating into one item makes that at most ONE prompt per update instead of N.
/// (Eliminating the prompt entirely would require a stable signing identity — out of scope
/// here, which is why the prompt still fires once.)
///
/// The public API (`setSecret`/`getSecret`/`deleteSecret` by `UUID`) is unchanged; callers
/// don't need to know about the consolidation. The vault is read from the keychain once and
/// kept in memory, so repeated `getSecret` calls don't re-hit the keychain.
struct KeychainService {
    static let service = "com.glassotp.secret"

    /// Account of the consolidated vault item.
    private static let vaultAccount = "GlassOTP.vault.v1"
    /// Legacy per-token account prefix (pre-consolidation). Used only for one-time migration.
    private static let legacyPrefix = "token."

    /// In-memory vault: `uuidString` -> secret. `nil` means "not loaded from keychain yet".
    private static var vault: [String: Data]?
    private static let lock = NSLock()

    /// Legacy per-token account name. Retained for reference / migration; the format of the
    /// items the migration reads.
    static func key(for id: UUID) -> String {
        return "\(legacyPrefix)\(id.uuidString)"
    }

    // MARK: - Public API (signatures unchanged)

    static func setSecret(_ secret: Data, for id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        try loadVaultLocked()
        vault?[id.uuidString] = secret
        try persistVaultLocked()
    }

    static func getSecret(for id: UUID) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        try loadVaultLocked()
        guard let data = vault?[id.uuidString] else {
            throw KeychainError.notFound
        }
        return data
    }

    static func deleteSecret(for id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        try loadVaultLocked()
        if vault?.removeValue(forKey: id.uuidString) != nil {
            try persistVaultLocked()
        }
    }

    // MARK: - Vault load / persist (caller must hold `lock`)

    private static func loadVaultLocked() throws {
        if vault != nil { return }

        // 1) Try the consolidated blob.
        if let data = try readItemData(account: vaultAccount) {
            vault = (try? JSONDecoder().decode([String: Data].self, from: data)) ?? [:]
            return
        }

        // 2) No blob yet → migrate legacy per-token items (one-time), then persist as one blob.
        vault = migrateLegacyItems()
        try? persistVaultLocked()
    }

    private static func persistVaultLocked() throws {
        let data = try JSONEncoder().encode(vault ?? [:])

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vaultAccount
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecSuccess { return }
        if status != errSecItemNotFound { throw KeychainError.update(status) }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess { throw KeychainError.add(addStatus) }
    }

    // MARK: - Raw item helpers

    /// Reads a single item's data. Returns `nil` only when the item doesn't exist.
    /// Reading the data may trigger the ACL prompt (this is where the password dialog appears).
    private static func readItemData(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            if let data = item as? Data { return data }
            throw KeychainError.copy(status)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.copy(status)
        }
    }

    // MARK: - One-time migration from per-token items

    /// Folds every legacy `token.<uuid>` item into a single dictionary.
    ///
    /// Enumerating accounts (attributes only, no data) does NOT prompt. Reading each item's
    /// *data* does — that's the unavoidable one-time cost of moving secrets created under the
    /// old per-item ACLs. Successfully migrated items are deleted so they never prompt again,
    /// and so they don't leave duplicate secrets behind.
    private static func migrateLegacyItems() -> [String: Data] {
        let listQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(listQuery as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return [:]
        }

        var migrated: [String: Data] = [:]
        var accountsToDelete: [String] = []

        for attrs in items {
            guard let account = attrs[kSecAttrAccount as String] as? String,
                  account.hasPrefix(legacyPrefix) else { continue }

            let uuidString = String(account.dropFirst(legacyPrefix.count))

            // Reading the data here is what surfaces the per-item prompt (one-time).
            if let data = (try? readItemData(account: account)) ?? nil {
                migrated[uuidString] = data
                accountsToDelete.append(account)
            }
        }

        for account in accountsToDelete {
            let delQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(delQuery as CFDictionary)
        }

        return migrated
    }
}
