import AppKit
import PDFKit
import Vision

enum TextRecognizer {
    static func lines(in image: CGImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    static func lines(in image: NSImage) throws -> [String] {
        guard let cg = image.cgImage() else { throw QRImportError.cannotReadImage }
        return lines(in: cg)
    }

    static func lines(inFile url: URL) throws -> [String] {
        guard url.pathExtension.lowercased() != QuickAdd.pdfExtension else {
            if let text = PDFDocument(url: url)?.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text.components(separatedBy: .newlines)
            }
            var found: [String] = []
            try QRService.renderPages(ofPDF: url) { found += lines(in: $0) }
            return found
        }
        guard let image = NSImage(contentsOf: url) else { throw QRImportError.cannotReadImage }
        return try lines(in: image)
    }
}
