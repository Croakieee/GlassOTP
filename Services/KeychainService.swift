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

struct KeychainService {
    static let service = "com.glassotp.secret"

    static func key(for id: UUID) -> String {
        return "token.\(id.uuidString)"
    }

    static func setSecret(_ secret: Data, for id: UUID) throws {
        let account = key(for: id)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attrs: [String: Any] = [
            kSecValueData as String: secret,
            //  лишние запросы пароля
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecSuccess {
            return
        }

        if status != errSecItemNotFound {
            throw KeychainError.update(status)
        }

        // Add
        var addQuery = query
        addQuery[kSecValueData as String] = secret

        // параметры для хранения кейчена
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            throw KeychainError.add(addStatus)
        }
    }

    static func getSecret(for id: UUID) throws -> Data {
        let account = key(for: id)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?

        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess {
            if let data = item as? Data { return data }
            throw KeychainError.copy(status)
        } else if status == errSecItemNotFound {
            throw KeychainError.notFound
        } else {
            throw KeychainError.copy(status)
        }
    }

    static func deleteSecret(for id: UUID) throws {
        let account = key(for: id)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }

        throw KeychainError.delete(status)
    }
}
