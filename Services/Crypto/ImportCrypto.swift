import Foundation
import CommonCrypto
import CryptoKit

enum ImportCryptoError: Error {
    case keyDerivation
    case decryption
}

enum ImportCrypto {
    enum PRF {
        case sha1
        case sha256

        var commonCrypto: CCPseudoRandomAlgorithm {
            switch self {
            case .sha1: return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1)
            case .sha256: return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256)
            }
        }
    }

    static func pbkdf2(password: String, salt: Data, rounds: UInt32, length: Int, prf: PRF) throws -> Data {
        let passwordBytes = Array(password.utf8) + [0]
        var key = Data(count: length)
        let status = key.withUnsafeMutableBytes { keyBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordBytes.withUnsafeBufferPointer { passwordBuffer in
                    passwordBuffer.baseAddress!.withMemoryRebound(to: Int8.self, capacity: passwordBytes.count) { passwordPointer in
                        CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordPointer, passwordBytes.count - 1,
                                             saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                                             prf.commonCrypto, rounds,
                                             keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), length)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw ImportCryptoError.keyDerivation }
        return key
    }

    static func aesCBCDecrypt(_ cipher: Data, key: Data, iv: Data) throws -> Data {
        guard iv.count == kCCBlockSizeAES128, !cipher.isEmpty else { throw ImportCryptoError.decryption }
        var output = Data(count: cipher.count + kCCBlockSizeAES128)
        let capacity = output.count
        var moved = 0
        let status = output.withUnsafeMutableBytes { out in
            cipher.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                                input.baseAddress, cipher.count, out.baseAddress, capacity, &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw ImportCryptoError.decryption }
        return output.prefix(moved)
    }

    static func aesGCMDecrypt(_ cipher: Data, key: Data, nonce: Data, tag: Data) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: cipher, tag: tag)
            return try AES.GCM.open(box, using: SymmetricKey(data: key))
        } catch {
            throw ImportCryptoError.decryption
        }
    }

    static func aesGCMDecrypt(combinedWithTag data: Data, key: Data, nonce: Data) throws -> Data {
        let tagLength = 16
        guard data.count >= tagLength else { throw ImportCryptoError.decryption }
        return try aesGCMDecrypt(data.dropLast(tagLength), key: key, nonce: nonce, tag: data.suffix(tagLength))
    }

    static func hmacSHA256(key: Data, message: Data) -> Data {
        var mac = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        mac.withUnsafeMutableBytes { macBytes in
            key.withUnsafeBytes { keyBytes in
                message.withUnsafeBytes { messageBytes in
                    CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), keyBytes.baseAddress, key.count,
                           messageBytes.baseAddress, message.count, macBytes.baseAddress)
                }
            }
        }
        return mac
    }
}

extension Data {
    init?(hex: String) {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(chars.count / 2)
        var index = 0
        while index < chars.count {
            guard let byte = UInt8(String(decoding: chars[index..<index + 2], as: UTF8.self), radix: 16) else { return nil }
            bytes.append(byte)
            index += 2
        }
        self.init(bytes)
    }
}
