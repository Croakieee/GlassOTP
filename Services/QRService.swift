import Foundation
import Vision
import AppKit

enum QRImportError: Error, LocalizedError {
    case noQRFound
    case noOtpauthInQR
    case cannotReadImage

    var errorDescription: String? {
        switch self {
        case .noQRFound: return "No QR code found in the image."
        case .noOtpauthInQR: return "The QR code does not contain an otpauth:// or otpauth-migration:// link."
        case .cannotReadImage: return "Failed to read the image."
        }
    }
}

struct QRService {
    static func scanAllOtpauth(from image: NSImage) throws -> [String] {
        guard let cg = image.cgImage() else { throw QRImportError.cannotReadImage }

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.QR]

        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try handler.perform([request])

        guard let results = request.results, !results.isEmpty else {
            throw QRImportError.noQRFound
        }

        var links: [String] = []
        for r in results {
            if let payload = r.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines) {
                let lower = payload.lowercased()
                if (lower.hasPrefix("otpauth://") || lower.hasPrefix("otpauth-migration://")) && !links.contains(payload) {
                    links.append(payload)
                }
            }
        }
        guard !links.isEmpty else { throw QRImportError.noOtpauthInQR }
        return links
    }
}
