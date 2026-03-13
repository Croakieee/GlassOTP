import Foundation

/// RFC 4648 Base32 декодер (как в Google Authenticator)
/// устойчив к нижнему регистру, пробелам, дефисам и типичным опечаткам
enum Base32 {
    private static let table: [Character: UInt8] = {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var map = [Character: UInt8]()
        for (i, c) in chars.enumerated() {
            map[c] = UInt8(i)
            map[Character(c.lowercased())] = UInt8(i)
        }
        // частые замены
        map["0"] = map["O"]
        map["1"] = map["I"]
        map["l"] = map["L"]
        return map
    }()

    static func decode(_ input: String) -> Data? {
        let cleaned = input
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        var buffer: UInt64 = 0
        var bits = 0
        var output = [UInt8]()
        output.reserveCapacity(cleaned.count * 5 / 8 + 1)

        for ch in cleaned {
            guard let val = table[ch] else { return nil }
            buffer = (buffer << 5) | UInt64(val)
            bits += 5
            if bits >= 8 {
                bits -= 8
                let byte = UInt8((buffer >> UInt64(bits)) & 0xff)
                output.append(byte)
            }
        }
        return Data(output)
    }
}
