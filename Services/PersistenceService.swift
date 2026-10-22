import Foundation

struct PersistenceService {
    private static let key = "GlassOTP.tokens.v1"
    private static let unreadableBackupKey = "GlassOTP.tokens.v1.unreadable"

    static func save(tokens: [OTPToken]) {
        do {
            let data = try JSONEncoder().encode(tokens)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            // ignore: в худшем случае токены не сохранятся
        }
    }

    static func load() -> (tokens: [OTPToken], hadUnreadableData: Bool) {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: key) else { return ([], false) }

        if let tokens = try? JSONDecoder().decode([OTPToken].self, from: data) {
            return (tokens, false)
        }

        if defaults.data(forKey: unreadableBackupKey) == nil {
            defaults.set(data, forKey: unreadableBackupKey)
        }

        let salvaged = (try? JSONDecoder().decode([SalvagedToken].self, from: data))?
            .compactMap(\.token) ?? []
        return (salvaged, true)
    }
}

private struct SalvagedToken: Decodable {
    let token: OTPToken?

    init(from decoder: Decoder) throws {
        token = try? OTPToken(from: decoder)
    }
}
