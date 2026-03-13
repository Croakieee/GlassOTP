import Foundation
import Vision
import AppKit

enum QRImportError: Error, LocalizedError {
    case noQRFound
    case noOtpauthInQR
    case cannotReadImage

    var errorDescription: String? {
        switch self {
        case .noQRFound: return "QR-код не найден на изображении."
        case .noOtpauthInQR: return "В QR нет otpauth:// или otpauth-migration:// ссылки."
        case .cannotReadImage: return "Не удалось прочитать изображение."
        }
    }
}

struct QRService {
    static func scanOtpauth(from image: NSImage) throws -> String {
        guard let cg = image.cgImage() else { throw QRImportError.cannotReadImage }

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.QR]

        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try handler.perform([request])

        guard let results = request.results, !results.isEmpty else {
            throw QRImportError.noQRFound
        }

        for r in results {
            if let payload = r.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines) {
                let lower = payload.lowercased()
                if lower.hasPrefix("otpauth://") || lower.hasPrefix("otpauth-migration://") {
                    return payload
                }
            }
        }
        throw QRImportError.noOtpauthInQR
    }

    static func scanOtpauth(from url: URL) throws -> String {
        guard let img = NSImage(contentsOf: url) else { throw QRImportError.cannotReadImage }
        return try scanOtpauth(from: img)
    }
}
