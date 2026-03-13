import Foundation

/// Мини-декодер protobuf для otpauth-migration://offline?data=...
/// Поддерживает только нужные нам поля.
struct OtpauthMigrationDecoder {

    struct Payload {
        var params: [OtpParameters] = []
        // batch/version поля игнорируем
    }

    struct OtpParameters {
        var secret: Data = Data()
        var name: String = ""
        var issuer: String = ""
        var algorithm: Int = 1 // 1=SHA1, 2=SHA256, 3=SHA512
        var digits: Int = 1    // 1=6, 2=8
        var type: Int = 2      // 2=TOTP, 1=HOTP
        var counter: UInt64 = 0
    }

    enum WireType: UInt64 {
        case varint = 0
        case fixed64 = 1
        case lengthDelimited = 2
        case startGroup = 3
        case endGroup = 4
        case fixed32 = 5
    }

    static func decode(base64URLData: String) throws -> Payload {
        guard let raw = base64URLDecode(base64URLData) else {
            throw ImportError.invalidURL
        }
        var cursor = 0
        return try decodePayload(from: raw, cursor: &cursor, limit: raw.count)
    }

    // MARK: - Decode helpers

    private static func decodePayload(from data: Data, cursor: inout Int, limit: Int) throws -> Payload {
        var payload = Payload()
        while cursor < limit {
            let (fieldNumber, wtype) = try readKey(data: data, cursor: &cursor)
            switch (fieldNumber, wtype) {
            case (1, .lengthDelimited): // repeated OtpParameters
                let len = try readVarint(data: data, cursor: &cursor)
                let subLimit = cursor + Int(len)
                var subCursor = cursor
                let param = try decodeOtpParameters(from: data, cursor: &subCursor, limit: subLimit)
                payload.params.append(param)
                cursor = subLimit
            case (2, .varint), (3, .varint), (4, .varint):
                _ = try readVarint(data: data, cursor: &cursor) // version/batch_size/batch_index (ignore)
            case (5, .lengthDelimited):
                let l = try readVarint(data: data, cursor: &cursor)
                cursor += Int(l) // batch_id (ignore)
            default:
                try skipUnknown(wire: wtype, data: data, cursor: &cursor)
            }
        }
        return payload
    }

    private static func decodeOtpParameters(from data: Data, cursor: inout Int, limit: Int) throws -> OtpParameters {
        var p = OtpParameters()
        while cursor < limit {
            let (fieldNumber, wtype) = try readKey(data: data, cursor: &cursor)
            switch fieldNumber {
            case 1: // secret bytes
                guard wtype == .lengthDelimited else { throw ImportError.invalidURL }
                let l = try readVarint(data: data, cursor: &cursor)
                p.secret = data.subdata(in: cursor ..< cursor + Int(l))
                cursor += Int(l)
            case 2: // name
                guard wtype == .lengthDelimited else { throw ImportError.invalidURL }
                let l = try readVarint(data: data, cursor: &cursor)
                if let s = String(data: data.subdata(in: cursor ..< cursor + Int(l)), encoding: .utf8) {
                    p.name = s
                }
                cursor += Int(l)
            case 3: // issuer
                guard wtype == .lengthDelimited else { throw ImportError.invalidURL }
                let l = try readVarint(data: data, cursor: &cursor)
                if let s = String(data: data.subdata(in: cursor ..< cursor + Int(l)), encoding: .utf8) {
                    p.issuer = s
                }
                cursor += Int(l)
            case 4: // algorithm enum
                guard wtype == .varint else { throw ImportError.invalidURL }
                p.algorithm = Int(try readVarint(data: data, cursor: &cursor))
            case 5: // digits enum
                guard wtype == .varint else { throw ImportError.invalidURL }
                p.digits = Int(try readVarint(data: data, cursor: &cursor))
            case 6: // type enum
                guard wtype == .varint else { throw ImportError.invalidURL }
                p.type = Int(try readVarint(data: data, cursor: &cursor))
            case 7: // counter (for HOTP)
                guard wtype == .varint else { throw ImportError.invalidURL }
                p.counter = try readVarint(data: data, cursor: &cursor)
            default:
                try skipUnknown(wire: wtype, data: data, cursor: &cursor)
            }
        }
        return p
    }

    private static func readKey(data: Data, cursor: inout Int) throws -> (Int, WireType) {
        let key = try readVarint(data: data, cursor: &cursor)
        let fieldNumber = Int(key >> 3)
        guard let wire = WireType(rawValue: key & 0x7) else { throw ImportError.invalidURL }
        return (fieldNumber, wire)
    }

    private static func readVarint(data: Data, cursor: inout Int) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while cursor < data.count {
            let b = data[cursor]
            cursor += 1
            result |= UInt64(b & 0x7F) << shift
            if (b & 0x80) == 0 { return result }
            shift += 7
            if shift > 63 { throw ImportError.invalidURL }
        }
        throw ImportError.invalidURL
    }

    private static func skipUnknown(wire: WireType, data: Data, cursor: inout Int) throws {
        switch wire {
        case .varint:
            _ = try readVarint(data: data, cursor: &cursor)
        case .fixed64:
            cursor += 8
        case .lengthDelimited:
            let l = try readVarint(data: data, cursor: &cursor)
            cursor += Int(l)
        case .fixed32:
            cursor += 4
        case .startGroup, .endGroup:
            throw ImportError.invalidURL // не ожидаем групп
        }
    }

    private static func base64URLDecode(_ s: String) -> Data? {
        var str = s
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - (str.count % 4)) % 4
        if padding > 0 { str.append(String(repeating: "=", count: padding)) }
        return Data(base64Encoded: str)
    }
}
