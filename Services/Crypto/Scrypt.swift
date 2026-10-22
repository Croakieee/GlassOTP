import Foundation

enum ScryptError: Error {
    case invalidParameters
}

enum Scrypt {
    private static let maxMemory = 512 * 1024 * 1024

    static func derive(password: Data, salt: Data, n: Int, r: Int, p: Int, length: Int) throws -> Data {
        guard n > 1, n & (n - 1) == 0, r > 0, p > 0, length > 0,
              128 * r * n <= maxMemory, p <= 16 else { throw ScryptError.invalidParameters }

        let blockWords = 32 * r
        var b = words(pbkdf2SHA256(password: password, salt: salt, length: p * 128 * r))
        let v = UnsafeMutablePointer<UInt32>.allocate(capacity: blockWords * n)
        let scratch = UnsafeMutablePointer<UInt32>.allocate(capacity: blockWords * 2 + 16)
        defer {
            v.deallocate()
            scratch.deallocate()
        }

        b.withUnsafeMutableBufferPointer { buffer in
            for chunk in 0..<p {
                roMix(buffer.baseAddress! + chunk * blockWords, r: r, n: n, v: v, scratch: scratch)
            }
        }
        return pbkdf2SHA256(password: password, salt: bytes(b), length: length)
    }

    private static func roMix(_ block: UnsafeMutablePointer<UInt32>, r: Int, n: Int,
                              v: UnsafeMutablePointer<UInt32>, scratch: UnsafeMutablePointer<UInt32>) {
        let blockWords = 32 * r
        let x = scratch
        let y = scratch + blockWords
        let salsa = scratch + 2 * blockWords
        x.update(from: block, count: blockWords)
        for i in 0..<n {
            (v + i * blockWords).update(from: x, count: blockWords)
            blockMix(x, into: y, r: r, salsa: salsa)
            x.update(from: y, count: blockWords)
        }
        for _ in 0..<n {
            let j = Int(x[(2 * r - 1) * 16]) & (n - 1)
            let row = v + j * blockWords
            for k in 0..<blockWords { x[k] ^= row[k] }
            blockMix(x, into: y, r: r, salsa: salsa)
            x.update(from: y, count: blockWords)
        }
        block.update(from: x, count: blockWords)
    }

    private static func blockMix(_ input: UnsafeMutablePointer<UInt32>, into output: UnsafeMutablePointer<UInt32>,
                                 r: Int, salsa: UnsafeMutablePointer<UInt32>) {
        salsa.update(from: input + (2 * r - 1) * 16, count: 16)
        for i in 0..<(2 * r) {
            for k in 0..<16 { salsa[k] ^= input[i * 16 + k] }
            salsa208(salsa)
            let target = (i % 2 == 0 ? i / 2 : r + i / 2) * 16
            (output + target).update(from: salsa, count: 16)
        }
    }

    private static func salsa208(_ b: UnsafeMutablePointer<UInt32>) {
        var x0 = b[0], x1 = b[1], x2 = b[2], x3 = b[3], x4 = b[4], x5 = b[5], x6 = b[6], x7 = b[7]
        var x8 = b[8], x9 = b[9], x10 = b[10], x11 = b[11], x12 = b[12], x13 = b[13], x14 = b[14], x15 = b[15]
        func rotl(_ v: UInt32, _ n: UInt32) -> UInt32 { (v << n) | (v >> (32 - n)) }
        for _ in 0..<4 {
            x4 ^= rotl(x0 &+ x12, 7); x8 ^= rotl(x4 &+ x0, 9); x12 ^= rotl(x8 &+ x4, 13); x0 ^= rotl(x12 &+ x8, 18)
            x9 ^= rotl(x5 &+ x1, 7); x13 ^= rotl(x9 &+ x5, 9); x1 ^= rotl(x13 &+ x9, 13); x5 ^= rotl(x1 &+ x13, 18)
            x14 ^= rotl(x10 &+ x6, 7); x2 ^= rotl(x14 &+ x10, 9); x6 ^= rotl(x2 &+ x14, 13); x10 ^= rotl(x6 &+ x2, 18)
            x3 ^= rotl(x15 &+ x11, 7); x7 ^= rotl(x3 &+ x15, 9); x11 ^= rotl(x7 &+ x3, 13); x15 ^= rotl(x11 &+ x7, 18)
            x1 ^= rotl(x0 &+ x3, 7); x2 ^= rotl(x1 &+ x0, 9); x3 ^= rotl(x2 &+ x1, 13); x0 ^= rotl(x3 &+ x2, 18)
            x6 ^= rotl(x5 &+ x4, 7); x7 ^= rotl(x6 &+ x5, 9); x4 ^= rotl(x7 &+ x6, 13); x5 ^= rotl(x4 &+ x7, 18)
            x11 ^= rotl(x10 &+ x9, 7); x8 ^= rotl(x11 &+ x10, 9); x9 ^= rotl(x8 &+ x11, 13); x10 ^= rotl(x9 &+ x8, 18)
            x12 ^= rotl(x15 &+ x14, 7); x13 ^= rotl(x12 &+ x15, 9); x14 ^= rotl(x13 &+ x12, 13); x15 ^= rotl(x14 &+ x13, 18)
        }
        b[0] &+= x0; b[1] &+= x1; b[2] &+= x2; b[3] &+= x3; b[4] &+= x4; b[5] &+= x5; b[6] &+= x6; b[7] &+= x7
        b[8] &+= x8; b[9] &+= x9; b[10] &+= x10; b[11] &+= x11; b[12] &+= x12; b[13] &+= x13; b[14] &+= x14; b[15] &+= x15
    }

    private static func pbkdf2SHA256(password: Data, salt: Data, length: Int) -> Data {
        var output = Data()
        var index: UInt32 = 1
        while output.count < length {
            var counter = index.bigEndian
            let block = salt + Data(bytes: &counter, count: 4)
            output.append(ImportCrypto.hmacSHA256(key: password, message: block))
            index += 1
        }
        return output.prefix(length)
    }

    private static func words(_ data: Data) -> [UInt32] {
        data.withUnsafeBytes { raw in
            (0..<data.count / 4).map { UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self)) }
        }
    }

    private static func bytes(_ words: [UInt32]) -> Data {
        var data = Data(capacity: words.count * 4)
        for word in words {
            var little = word.littleEndian
            data.append(Data(bytes: &little, count: 4))
        }
        return data
    }
}
