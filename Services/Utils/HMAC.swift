import Foundation
import CryptoKit

enum HMAC {
    static func sign(algorithm: OTPAlgorithm, key: Data, message: Data) -> Data {
        let k = SymmetricKey(data: key)
        switch algorithm {
        case .sha1:
            // Google Authenticator по умолчанию использует SHA1
            let mac = CryptoKit.HMAC<Insecure.SHA1>.authenticationCode(for: message, using: k)
            return Data(mac)
        case .sha256:
            let mac = CryptoKit.HMAC<SHA256>.authenticationCode(for: message, using: k)
            return Data(mac)
        case .sha512:
            let mac = CryptoKit.HMAC<SHA512>.authenticationCode(for: message, using: k)
            return Data(mac)
        }
    }
}
