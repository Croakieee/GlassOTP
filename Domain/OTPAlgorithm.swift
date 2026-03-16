import Foundation

enum OTPAlgorithm: String, Codable, CaseIterable {
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"

    var blockSize: Int {
        switch self {
        case .sha1:   return 64
        case .sha256: return 64
        case .sha512: return 128
        }
    }
}
