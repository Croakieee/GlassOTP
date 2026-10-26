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
    static let maxPDFPages = 10
    private static let pdfRenderSide: CGFloat = 2400

    static func scanAllOtpauth(from image: NSImage) throws -> [String] {
        guard let cg = image.cgImage() else { throw QRImportError.cannotReadImage }
        return try scanAllOtpauth(from: cg)
    }

    static func scanAllOtpauth(fromPDF url: URL) throws -> [String] {
        var links: [String] = []
        var sawQR = false
        try renderPages(ofPDF: url) { image in
            do {
                for link in try scanAllOtpauth(from: image) where !links.contains(link) {
                    links.append(link)
                }
                sawQR = true
            } catch QRImportError.noOtpauthInQR {
                sawQR = true
            } catch {
                return
            }
        }
        guard !links.isEmpty else { throw sawQR ? QRImportError.noOtpauthInQR : QRImportError.noQRFound }
        return links
    }

    static func renderPages(ofPDF url: URL, _ body: (CGImage) -> Void) throws {
        guard let document = CGPDFDocument(url as CFURL), document.numberOfPages > 0 else { throw QRImportError.cannotReadImage }
        for index in 1...min(document.numberOfPages, maxPDFPages) {
            guard let page = document.page(at: index), let image = render(page) else { continue }
            body(image)
        }
    }

    private static func render(_ page: CGPDFPage) -> CGImage? {
        let box = page.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = pdfRenderSide / max(box.width, box.height)
        let width = Int(box.width * scale), height = Int(box.height * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.drawPDFPage(page)
        return context.makeImage()
    }

    static func scanAllOtpauth(from cg: CGImage) throws -> [String] {
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
