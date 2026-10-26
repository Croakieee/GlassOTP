import AppKit

struct QuickAddFeedback: Equatable {
    enum Kind: Equatable {
        case success
        case info
        case permission
    }

    let kind: Kind
    let message: String
    let lockedMessage: String
}

struct QuickAddPayload {
    var files: [URL] = []
    var text: String?
    var image: NSImage?

    var isEmpty: Bool { files.isEmpty && (text ?? "").isEmpty && image == nil }

    static func read(from pasteboard: NSPasteboard) -> QuickAddPayload {
        var payload = QuickAddPayload()
        payload.files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard payload.files.isEmpty else { return payload }
        let links = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []).map(\.absoluteString)
        payload.text = ([pasteboard.string(forType: .string)].compactMap { $0 } + links).joined(separator: "\n")
        if pasteboard.availableType(from: [.tiff, .png]) != nil {
            payload.image = NSImage(pasteboard: pasteboard)
        }
        return payload
    }
}

enum QuickAddInput {
    case accounts([ImportedToken], unreadable: Int)
    case file(FileImportPlan)
    case failure(String)
}

enum QuickAdd {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff", "bmp", "gif"]
    static let pdfExtension = "pdf"

    static let nothingFound = QuickAddFeedback(
        kind: .info,
        message: "No QR code or otpauth:// link with an account was found.",
        lockedMessage: "No QR code or otpauth:// link with an account was found."
    )

    static let permissionNeeded = QuickAddFeedback(
        kind: .permission,
        message: "Allow Screen Recording for GlassOTP, then reopen it.",
        lockedMessage: "Allow Screen Recording for GlassOTP, then reopen it."
    )

    static func inputs(from payload: QuickAddPayload) -> [QuickAddInput] {
        if !payload.files.isEmpty {
            return payload.files.map(input(forFile:))
        }
        let links = LinkListImport.links(in: payload.text ?? "")
        if !links.isEmpty {
            return [accounts(fromLinks: links)]
        }
        if let image = payload.image {
            return [accounts(fromLinks: (try? QRService.scanAllOtpauth(from: image)) ?? [])]
        }
        return [.accounts([], unreadable: 0)]
    }

    static func input(forFile url: URL) -> QuickAddInput {
        let ext = url.pathExtension.lowercased()
        if ext == pdfExtension {
            return accounts(fromLinks: (try? QRService.scanAllOtpauth(fromPDF: url)) ?? [])
        }
        if imageExtensions.contains(ext) {
            guard let image = NSImage(contentsOf: url) else { return .failure(QRImportError.cannotReadImage.errorDescription ?? "") }
            return accounts(fromLinks: (try? QRService.scanAllOtpauth(from: image)) ?? [])
        }
        do {
            return .file(try FileImportService.plan(for: url))
        } catch {
            return .failure((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    static func accounts(fromLinks links: [String]) -> QuickAddInput {
        var tokens: [ImportedToken] = []
        var unreadable = 0
        for link in links {
            guard let parsed = try? ImportExportService.parseOtpauthOrMigration(link) else {
                unreadable += 1
                continue
            }
            tokens += parsed.tokens
            unreadable += parsed.unsupported
        }
        return .accounts(tokens, unreadable: unreadable)
    }

    static func add(_ tokens: [ImportedToken], unreadable: Int, to store: OTPStore) -> QuickAddFeedback {
        guard !tokens.isEmpty else {
            guard unreadable > 0 else { return nothingFound }
            let text = ExternalImportError.nothingSupported(unreadable).errorDescription ?? ""
            return QuickAddFeedback(kind: .info, message: text, lockedMessage: text)
        }
        let fresh = store.newAccounts(in: tokens)
        let result = store.addImportedMany(tokens)

        if result.added > 0 {
            let existed = result.duplicates > 0 ? " \(result.duplicates) already existed." : ""
            return QuickAddFeedback(
                kind: .success,
                message: "Added \(addedTitle(added: result.added, fresh: fresh, tokens: tokens))." + existed,
                lockedMessage: "Added \(result.added) account(s)." + existed
            )
        }
        if result.failed > 0 {
            let text = "Couldn't save to the Keychain."
            return QuickAddFeedback(kind: .info, message: text, lockedMessage: text)
        }
        let existing = tokens.count == 1 ? "\(ClipboardReader.title(tokens)) is" : "These accounts are"
        return QuickAddFeedback(kind: .info, message: "\(existing) already in GlassOTP.", lockedMessage: "Already in GlassOTP.")
    }

    private static func addedTitle(added: Int, fresh: [ImportedToken], tokens: [ImportedToken]) -> String {
        let source = fresh.count == added ? fresh : tokens
        guard added == 1, let first = source.first else { return "\(added) new accounts" }
        return ClipboardReader.title([first])
    }

    static func failure(_ message: String) -> QuickAddFeedback {
        QuickAddFeedback(kind: .info, message: message, lockedMessage: message)
    }
}
