import Foundation

enum Argon2Error: Error {
    case invalidParameters
}

struct Blake2b {
    private static let iv: [UInt64] = [
        0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
        0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
    ]

    private static let sigma: [[Int]] = [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
        [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
        [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
        [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
        [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
        [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
        [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
        [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
        [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
        [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
    ]

    private var h: [UInt64]
    private var buffer: [UInt8] = []
    private var counter: UInt64 = 0
    private let outputLength: Int

    init(outputLength: Int) {
        self.outputLength = outputLength
        h = Self.iv
        h[0] ^= 0x0101_0000 ^ UInt64(outputLength)
    }

    static func hash(_ data: [UInt8], length: Int) -> [UInt8] {
        var hasher = Blake2b(outputLength: length)
        hasher.update(data)
        return hasher.finish()
    }

    mutating func update(_ data: [UInt8]) {
        for byte in data {
            if buffer.count == 128 {
                counter &+= 128
                compress(buffer, last: false)
                buffer.removeAll(keepingCapacity: true)
            }
            buffer.append(byte)
        }
    }

    mutating func finish() -> [UInt8] {
        counter &+= UInt64(buffer.count)
        compress(buffer + [UInt8](repeating: 0, count: 128 - buffer.count), last: true)
        var out: [UInt8] = []
        for word in h {
            for shift in stride(from: 0, to: 64, by: 8) { out.append(UInt8(truncatingIfNeeded: word >> UInt64(shift))) }
        }
        return Array(out.prefix(outputLength))
    }

    private mutating func compress(_ block: [UInt8], last: Bool) {
        var m = [UInt64](repeating: 0, count: 16)
        for i in 0..<16 {
            var word: UInt64 = 0
            for j in 0..<8 { word |= UInt64(block[i * 8 + j]) << UInt64(8 * j) }
            m[i] = word
        }
        var v = h + Self.iv
        v[12] ^= counter
        if last { v[14] = ~v[14] }
        func rotr(_ x: UInt64, _ n: UInt64) -> UInt64 { (x >> n) | (x << (64 - n)) }
        func g(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ x: UInt64, _ y: UInt64) {
            v[a] = v[a] &+ v[b] &+ x; v[d] = rotr(v[d] ^ v[a], 32)
            v[c] = v[c] &+ v[d]; v[b] = rotr(v[b] ^ v[c], 24)
            v[a] = v[a] &+ v[b] &+ y; v[d] = rotr(v[d] ^ v[a], 16)
            v[c] = v[c] &+ v[d]; v[b] = rotr(v[b] ^ v[c], 63)
        }
        for round in 0..<12 {
            let s = Self.sigma[round % 10]
            g(0, 4, 8, 12, m[s[0]], m[s[1]]); g(1, 5, 9, 13, m[s[2]], m[s[3]])
            g(2, 6, 10, 14, m[s[4]], m[s[5]]); g(3, 7, 11, 15, m[s[6]], m[s[7]])
            g(0, 5, 10, 15, m[s[8]], m[s[9]]); g(1, 6, 11, 12, m[s[10]], m[s[11]])
            g(2, 7, 8, 13, m[s[12]], m[s[13]]); g(3, 4, 9, 14, m[s[14]], m[s[15]])
        }
        for i in 0..<8 { h[i] ^= v[i] ^ v[i + 8] }
    }
}

enum Argon2id {
    private static let version: UInt32 = 0x13
    private static let typeID: UInt32 = 2
    private static let blockWords = 128
    private static let syncPoints = 4
    private static let maxMemoryKiB = 512 * 1024

    static func derive(password: [UInt8], salt: [UInt8], secret: [UInt8] = [], associatedData: [UInt8] = [],
                       iterations: Int, memoryKiB: Int, parallelism: Int, length: Int) throws -> [UInt8] {
        guard iterations > 0, parallelism > 0, parallelism <= 16, length >= 4,
              memoryKiB >= 8 * parallelism, memoryKiB <= maxMemoryKiB else { throw Argon2Error.invalidParameters }

        var h0Input: [UInt8] = []
        for value in [UInt32(parallelism), UInt32(length), UInt32(memoryKiB), UInt32(iterations), version, typeID] {
            h0Input += le32(value)
        }
        h0Input += le32(UInt32(password.count)) + password
        h0Input += le32(UInt32(salt.count)) + salt
        h0Input += le32(UInt32(secret.count)) + secret
        h0Input += le32(UInt32(associatedData.count)) + associatedData
        let h0 = Blake2b.hash(h0Input, length: 64)

        let segmentLength = memoryKiB / (syncPoints * parallelism)
        let laneLength = segmentLength * syncPoints
        let blockCount = laneLength * parallelism
        let memory = UnsafeMutablePointer<UInt64>.allocate(capacity: blockCount * blockWords)
        memory.initialize(repeating: 0, count: blockCount * blockWords)
        defer { memory.deallocate() }

        for lane in 0..<parallelism {
            for column in 0..<2 {
                let bytes = hashPrime(h0 + le32(UInt32(column)) + le32(UInt32(lane)), length: 1024)
                load(bytes, into: memory + (lane * laneLength + column) * blockWords)
            }
        }

        let context = Context(memory: memory, lanes: parallelism, laneLength: laneLength, segmentLength: segmentLength,
                              passes: iterations, blockCount: blockCount)
        for pass in 0..<iterations {
            for slice in 0..<syncPoints {
                for lane in 0..<parallelism {
                    fillSegment(context, pass: pass, lane: lane, slice: slice)
                }
            }
        }

        var final = [UInt64](repeating: 0, count: blockWords)
        for lane in 0..<parallelism {
            let block = memory + (lane * laneLength + laneLength - 1) * blockWords
            for i in 0..<blockWords { final[i] ^= block[i] }
        }
        var finalBytes: [UInt8] = []
        finalBytes.reserveCapacity(1024)
        for word in final { finalBytes += le64(word) }
        return hashPrime(finalBytes, length: length)
    }

    private struct Context {
        let memory: UnsafeMutablePointer<UInt64>
        let lanes: Int
        let laneLength: Int
        let segmentLength: Int
        let passes: Int
        let blockCount: Int
    }

    private static func fillSegment(_ ctx: Context, pass: Int, lane: Int, slice: Int) {
        let independent = pass == 0 && slice < syncPoints / 2
        var address = [UInt64](repeating: 0, count: blockWords)
        var input = [UInt64](repeating: 0, count: blockWords)
        let zero = [UInt64](repeating: 0, count: blockWords)
        if independent {
            input[0] = UInt64(pass); input[1] = UInt64(lane); input[2] = UInt64(slice)
            input[3] = UInt64(ctx.blockCount); input[4] = UInt64(ctx.passes); input[5] = UInt64(typeID)
        }

        let start = pass == 0 && slice == 0 ? 2 : 0
        if independent && start == 2 { nextAddresses(&address, input: &input, zero: zero) }

        for index in start..<ctx.segmentLength {
            let column = slice * ctx.segmentLength + index
            let current = lane * ctx.laneLength + column
            let previous = column == 0 ? current + ctx.laneLength - 1 : current - 1

            let pseudoRandom: UInt64
            if independent {
                if index % blockWords == 0 { nextAddresses(&address, input: &input, zero: zero) }
                pseudoRandom = address[index % blockWords]
            } else {
                pseudoRandom = ctx.memory[previous * blockWords]
            }

            let refLane = pass == 0 && slice == 0 ? lane : Int((pseudoRandom >> 32) % UInt64(ctx.lanes))
            let refIndex = referenceIndex(ctx, pass: pass, slice: slice, index: index,
                                          j1: pseudoRandom & 0xFFFF_FFFF, sameLane: refLane == lane)
            let reference = refLane * ctx.laneLength + refIndex
            compress(ctx.memory + previous * blockWords, ctx.memory + reference * blockWords,
                     into: ctx.memory + current * blockWords, xorExisting: pass > 0)
        }
    }

    private static func referenceIndex(_ ctx: Context, pass: Int, slice: Int, index: Int, j1: UInt64, sameLane: Bool) -> Int {
        let areaSize: Int
        if pass == 0 {
            if slice == 0 {
                areaSize = index - 1
            } else if sameLane {
                areaSize = slice * ctx.segmentLength + index - 1
            } else {
                areaSize = slice * ctx.segmentLength - (index == 0 ? 1 : 0)
            }
        } else if sameLane {
            areaSize = ctx.laneLength - ctx.segmentLength + index - 1
        } else {
            areaSize = ctx.laneLength - ctx.segmentLength - (index == 0 ? 1 : 0)
        }
        let x = (j1 &* j1) >> 32
        let y = (UInt64(areaSize) &* x) >> 32
        let relative = UInt64(areaSize) - 1 - y
        let startPosition = pass == 0 || slice == syncPoints - 1 ? 0 : (slice + 1) * ctx.segmentLength
        return Int((UInt64(startPosition) + relative) % UInt64(ctx.laneLength))
    }

    private static func nextAddresses(_ address: inout [UInt64], input: inout [UInt64], zero: [UInt64]) {
        input[6] &+= 1
        var temp = [UInt64](repeating: 0, count: blockWords)
        zero.withUnsafeBufferPointer { z in
            input.withUnsafeBufferPointer { i in
                temp.withUnsafeMutableBufferPointer { t in
                    compress(UnsafeMutablePointer(mutating: z.baseAddress!), UnsafeMutablePointer(mutating: i.baseAddress!),
                             into: t.baseAddress!, xorExisting: false)
                }
            }
        }
        let first = temp
        zero.withUnsafeBufferPointer { z in
            first.withUnsafeBufferPointer { f in
                address.withUnsafeMutableBufferPointer { a in
                    compress(UnsafeMutablePointer(mutating: z.baseAddress!), UnsafeMutablePointer(mutating: f.baseAddress!),
                             into: a.baseAddress!, xorExisting: false)
                }
            }
        }
    }

    private static func compress(_ x: UnsafeMutablePointer<UInt64>, _ y: UnsafeMutablePointer<UInt64>,
                                 into out: UnsafeMutablePointer<UInt64>, xorExisting: Bool) {
        var r = [UInt64](repeating: 0, count: blockWords)
        for i in 0..<blockWords { r[i] = x[i] ^ y[i] }
        var q = r
        q.withUnsafeMutableBufferPointer { buffer in
            let p = buffer.baseAddress!
            for row in 0..<8 {
                let base = row * 16
                permute(p, [base, base + 1, base + 2, base + 3, base + 4, base + 5, base + 6, base + 7,
                            base + 8, base + 9, base + 10, base + 11, base + 12, base + 13, base + 14, base + 15])
            }
            for column in 0..<8 {
                let base = column * 2
                permute(p, [base, base + 1, base + 16, base + 17, base + 32, base + 33, base + 48, base + 49,
                            base + 64, base + 65, base + 80, base + 81, base + 96, base + 97, base + 112, base + 113])
            }
        }
        for i in 0..<blockWords {
            let value = q[i] ^ r[i]
            out[i] = xorExisting ? out[i] ^ value : value
        }
    }

    private static func permute(_ v: UnsafeMutablePointer<UInt64>, _ idx: [Int]) {
        func rotr(_ x: UInt64, _ n: UInt64) -> UInt64 { (x >> n) | (x << (64 - n)) }
        func mul(_ a: UInt64, _ b: UInt64) -> UInt64 { 2 &* (a & 0xFFFF_FFFF) &* (b & 0xFFFF_FFFF) }
        func g(_ a: Int, _ b: Int, _ c: Int, _ d: Int) {
            v[a] = v[a] &+ v[b] &+ mul(v[a], v[b]); v[d] = rotr(v[d] ^ v[a], 32)
            v[c] = v[c] &+ v[d] &+ mul(v[c], v[d]); v[b] = rotr(v[b] ^ v[c], 24)
            v[a] = v[a] &+ v[b] &+ mul(v[a], v[b]); v[d] = rotr(v[d] ^ v[a], 16)
            v[c] = v[c] &+ v[d] &+ mul(v[c], v[d]); v[b] = rotr(v[b] ^ v[c], 63)
        }
        g(idx[0], idx[4], idx[8], idx[12]); g(idx[1], idx[5], idx[9], idx[13])
        g(idx[2], idx[6], idx[10], idx[14]); g(idx[3], idx[7], idx[11], idx[15])
        g(idx[0], idx[5], idx[10], idx[15]); g(idx[1], idx[6], idx[11], idx[12])
        g(idx[2], idx[7], idx[8], idx[13]); g(idx[3], idx[4], idx[9], idx[14])
    }

    private static func hashPrime(_ input: [UInt8], length: Int) -> [UInt8] {
        let prefixed = le32(UInt32(length)) + input
        guard length > 64 else { return Blake2b.hash(prefixed, length: length) }
        var output: [UInt8] = []
        var v = Blake2b.hash(prefixed, length: 64)
        output += v.prefix(32)
        let fullBlocks = (length + 31) / 32 - 2
        for _ in 1..<fullBlocks {
            v = Blake2b.hash(v, length: 64)
            output += v.prefix(32)
        }
        output += Blake2b.hash(v, length: length - 32 * fullBlocks)
        return output
    }

    private static func load(_ bytes: [UInt8], into block: UnsafeMutablePointer<UInt64>) {
        for i in 0..<blockWords {
            var word: UInt64 = 0
            for j in 0..<8 { word |= UInt64(bytes[i * 8 + j]) << UInt64(8 * j) }
            block[i] = word
        }
    }

    private static func le32(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: value >> UInt32(8 * $0)) }
    }

    private static func le64(_ value: UInt64) -> [UInt8] {
        (0..<8).map { UInt8(truncatingIfNeeded: value >> UInt64(8 * $0)) }
    }
}
