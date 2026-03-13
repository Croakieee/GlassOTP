import Foundation

struct TOTPGenerator {
    static func code(for date: Date, token: OTPToken, secret: Data) -> String {
        // Шаг счётчика
        let counter = UInt64(floor(date.timeIntervalSince1970 / Double(token.period)))
        // 8 байт big-endian
        var be = counter.bigEndian
        let msg = withUnsafeBytes(of: &be) { Data($0) }

        // HMAC
        let digest = HMAC.sign(algorithm: token.algorithm, key: secret, message: msg)
        guard let last = digest.last else { return String(repeating: "0", count: token.digits) }

        // Dynamic Truncation (RFC 4226 5.3)
        let rawOffset = Int(last & 0x0f)
        let offset = max(0, min(rawOffset, digest.count - 4))

        let p0 = UInt32(digest[offset + 0] & 0x7f)
        let p1 = UInt32(digest[offset + 1])
        let p2 = UInt32(digest[offset + 2])
        let p3 = UInt32(digest[offset + 3])

        let bin = (p0 << 24) | (p1 << 16) | (p2 << 8) | p3
        let mod = pow10(token.digits)
        let val = bin % mod

        // Надёжное формирование строки с ведущими нулями
        let s = String(val)
        if s.count >= token.digits { return s }
        return String(repeating: "0", count: token.digits - s.count) + s
    }

    static func timeRemaining(for date: Date, period: Int) -> Int {
        let s = Int(date.timeIntervalSince1970)
        let rem = period - (s % period)
        return rem == period ? 0 : rem
    }

    private static func pow10(_ n: Int) -> UInt32 {
        var v: UInt32 = 1
        for _ in 0..<n { v &*= 10 }
        return v
    }
}
