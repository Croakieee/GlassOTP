import Foundation

struct PersistenceService {
    private static let key = "GlassOTP.tokens.v1"
    private static let unreadableBackupKey = "GlassOTP.tokens.v1.unreadable"
    private static let trashKey = "GlassOTP.trash.v1"

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

    static func save(trash: [TrashedToken]) {
        guard let data = try? JSONEncoder().encode(trash) else { return }
        UserDefaults.standard.set(data, forKey: trashKey)
    }

    static func loadTrash() -> [TrashedToken] {
        guard let data = UserDefaults.standard.data(forKey: trashKey) else { return [] }
        return (try? JSONDecoder().decode([SalvagedTrashItem].self, from: data))?.compactMap(\.item) ?? []
    }
}

private struct SalvagedTrashItem: Decodable {
    let item: TrashedToken?

    init(from decoder: Decoder) throws {
        item = try? TrashedToken(from: decoder)
    }
}

private struct SalvagedToken: Decodable {
    let token: OTPToken?

    init(from decoder: Decoder) throws {
        token = try? OTPToken(from: decoder)
    }
}
