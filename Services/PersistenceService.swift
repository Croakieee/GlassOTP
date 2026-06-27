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
}
