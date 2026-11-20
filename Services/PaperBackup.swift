import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct PaperBackupEntry {
    let token: OTPToken
    let secret: String
    let recoveryCodes: [RecoveryCode]
}

enum PaperBackup {
    private static let margin: CGFloat = 40
    private static let padding: CGFloat = 12
    private static let qrSize: CGFloat = 116
    private static let gap: CGFloat = 10
    private static let footerHeight: CGFloat = 24

    private struct Card {
        let entry: PaperBackupEntry
        let text: NSAttributedString
        let height: CGFloat
    }

    private struct Placement {
        let card: Card
        let page: Int
        let y: CGFloat
    }

    static func pdf(_ entries: [PaperBackupEntry], paper: NSSize, date: Date = Date()) -> Data {
        let width = paper.width - margin * 2
        let textWidth = width - qrSize - padding * 3
        let header = headerText(count: entries.count, date: date)
        let headerHeight = ceil(header.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                                    options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 18
        let cards = entries.map { entry -> Card in
            let text = cardText(entry)
            let textHeight = ceil(text.boundingRect(with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
                                                    options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
            return Card(entry: entry, text: text, height: max(qrSize, textHeight) + padding * 2)
        }

        let bottom = paper.height - margin - footerHeight
        var placements: [Placement] = []
        var page = 0
        var y = margin + headerHeight
        for card in cards {
            if y + card.height > bottom && y > margin {
                page += 1
                y = margin
            }
            placements.append(Placement(card: card, page: page, y: y))
            y += card.height + gap
        }
        let pageCount = page + 1

        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: paper)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, [
                  kCGPDFContextTitle as String: "GlassOTP backup",
                  kCGPDFContextCreator as String: "GlassOTP"
              ] as CFDictionary) else { return Data() }

        let previous = NSGraphicsContext.current
        for index in 0..<pageCount {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: paper.height)
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

            if index == 0 {
                header.draw(with: NSRect(x: margin, y: margin, width: width, height: headerHeight),
                            options: [.usesLineFragmentOrigin, .usesFontLeading])
            }
            for placement in placements where placement.page == index {
                draw(placement.card, at: NSPoint(x: margin, y: placement.y), width: width, textWidth: textWidth)
            }
            footer(page: index + 1, of: pageCount).draw(
                with: NSRect(x: margin, y: paper.height - margin - 12, width: width, height: 14),
                options: [.usesLineFragmentOrigin])

            NSGraphicsContext.current = previous
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    private static func draw(_ card: Card, at origin: NSPoint, width: CGFloat, textWidth: CGFloat) {
        let frame = NSRect(x: origin.x, y: origin.y, width: width, height: card.height)
        let border = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        NSColor(white: 0.78, alpha: 1).setStroke()
        border.lineWidth = 1
        border.stroke()

        let link = ImportExportService.link(for: card.entry.token, secret: card.entry.secret)
        if let qr = qrImage(link) {
            qr.draw(in: NSRect(x: frame.minX + padding, y: frame.minY + padding, width: qrSize, height: qrSize),
                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.none])
        }
        card.text.draw(with: NSRect(x: frame.minX + qrSize + padding * 2, y: frame.minY + padding,
                                    width: textWidth, height: card.height - padding * 2),
                       options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    private static func qrImage(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let image = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: qrSize, height: qrSize))
    }

    private static func headerText(count: Int, date: Date) -> NSAttributedString {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        let text = NSMutableAttributedString()
        text.append(line("GlassOTP backup", font: .systemFont(ofSize: 20, weight: .bold)))
        text.append(line("\(formatter.string(from: date)) · \(count) \(count == 1 ? "account" : "accounts")",
                         font: .systemFont(ofSize: 11), color: .darkGray))
        text.append(line("Anyone with this page can generate your codes. Keep it somewhere safe, away from your Mac. To restore, scan a QR code in GlassOTP or any authenticator app, or type the secret in manually.",
                         font: .systemFont(ofSize: 10), color: .darkGray, last: true))
        return text
    }

    private static func cardText(_ entry: PaperBackupEntry) -> NSAttributedString {
        let token = entry.token
        let text = NSMutableAttributedString()
        text.append(line(token.issuer.isEmpty ? token.account : token.issuer, font: .systemFont(ofSize: 13, weight: .semibold)))
        if !token.issuer.isEmpty && !token.account.isEmpty {
            text.append(line(token.account, font: .systemFont(ofSize: 11)))
        }
        text.append(line(details(token), font: .systemFont(ofSize: 9), color: .darkGray))
        text.append(line("Secret", font: .systemFont(ofSize: 9, weight: .semibold), color: .darkGray, spacingBefore: 4))
        text.append(line(grouped(entry.secret), font: .monospacedSystemFont(ofSize: 10, weight: .regular)))
        let codes = entry.recoveryCodes.filter { !$0.isUsed }
        if !codes.isEmpty {
            text.append(line("Recovery codes", font: .systemFont(ofSize: 9, weight: .semibold), color: .darkGray, spacingBefore: 4))
            let list = codes.map { code -> String in
                guard let note = code.note, !note.isEmpty else { return code.code }
                return "\(note): \(code.code)".replacingOccurrences(of: " ", with: "\u{00A0}")
            }
            text.append(line(list.joined(separator: "   "), font: .monospacedSystemFont(ofSize: 9, weight: .regular)))
        }
        return text
    }

    private static func details(_ token: OTPToken) -> String {
        switch token.kind {
        case .steam:
            return "Steam Guard · scan the QR code with GlassOTP"
        case .hotp:
            return "HOTP · \(token.algorithm.rawValue) · \(token.digits) digits · counter \(token.counter) when printed"
        case .totp:
            return "TOTP · \(token.algorithm.rawValue) · \(token.digits) digits · every \(token.period) s"
        }
    }

    private static func grouped(_ secret: String) -> String {
        var groups: [String] = []
        var current = ""
        for char in secret where char != "=" {
            current.append(char)
            if current.count == 4 {
                groups.append(current)
                current = ""
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups.joined(separator: " ")
    }

    private static func footer(page: Int, of count: Int) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return NSAttributedString(string: "GlassOTP backup · page \(page) of \(count)", attributes: [
            .font: NSFont.systemFont(ofSize: 8), .foregroundColor: NSColor.gray, .paragraphStyle: style
        ])
    }

    private static func line(_ string: String, font: NSFont, color: NSColor = .black,
                             spacingBefore: CGFloat = 0, last: Bool = false) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = spacingBefore
        style.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: last ? string : string + "\n", attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: style
        ])
    }
}
