import AppKit

enum ClipboardAccess {
    case silent
    case askFirst
    case denied

    static func current(_ pasteboard: NSPasteboard) -> ClipboardAccess {
        guard #available(macOS 15.4, *) else { return .silent }
        switch pasteboard.accessBehavior {
        case .alwaysAllow: return .silent
        case .alwaysDeny: return .denied
        default: return .askFirst
        }
    }
}

enum ClipboardOffer: Equatable {
    case accounts(title: String)
    case check
    case nothingFound
    case added(title: String, cleared: Bool)
}

enum ClipboardReader {
    static func accounts(text: String?, image: NSImage?) -> [ImportedToken] {
        let fromText = (text.map(LinkListImport.links) ?? []).flatMap { link in
            (try? ImportExportService.parseOtpauthOrMigration(link).tokens) ?? []
        }
        guard fromText.isEmpty, let image, let link = try? QRService.scanOtpauth(from: image) else { return fromText }
        return (try? ImportExportService.parseOtpauthOrMigration(link).tokens) ?? []
    }

    static func title(_ accounts: [ImportedToken]) -> String {
        guard accounts.count == 1, let token = accounts.first?.token else { return "\(accounts.count) new accounts" }
        return "“\(token.displayTitle.isEmpty ? OTPStore.unnamedIssuer : token.displayTitle)”"
    }
}

final class ClipboardSuggester: ObservableObject {
    @Published private(set) var offer: ClipboardOffer?

    private static let imageTypes: [NSPasteboard.PasteboardType] = [.tiff, .png]
    private static let feedbackDuration: TimeInterval = 3

    private let pasteboard: NSPasteboard
    private let access: (NSPasteboard) -> ClipboardAccess
    private var scannedChangeCount: Int?
    private var dismissedChangeCount: Int?
    private var found: [ImportedToken] = []

    init(pasteboard: NSPasteboard = .general, access: @escaping (NSPasteboard) -> ClipboardAccess = ClipboardAccess.current) {
        self.pasteboard = pasteboard
        self.access = access
    }

    func refresh(store: OTPStore) {
        let changeCount = pasteboard.changeCount
        guard changeCount != dismissedChangeCount else {
            hide()
            return
        }
        guard changeCount != scannedChangeCount else {
            publish(store, reportEmpty: false)
            return
        }
        scannedChangeCount = changeCount
        found = []
        offer = nil
        switch access(pasteboard) {
        case .denied: return
        case .silent: read(store, changeCount: changeCount, reportEmpty: false)
        case .askFirst: detectCandidate(changeCount)
        }
    }

    func check(store: OTPStore) {
        let changeCount = pasteboard.changeCount
        scannedChangeCount = changeCount
        read(store, changeCount: changeCount, reportEmpty: true)
    }

    @discardableResult
    func accept(store: OTPStore) -> ImportResult {
        let fresh = store.newAccounts(in: found)
        let result = store.addImportedMany(fresh)
        let cleared = result.added > 0 && pasteboard.changeCount == scannedChangeCount
        if cleared { pasteboard.clearContents() }
        dismissedChangeCount = pasteboard.changeCount
        found = []
        offer = result.added > 0 ? .added(title: ClipboardReader.title(fresh), cleared: cleared) : nil
        hideLater()
        return result
    }

    func dismiss() {
        dismissedChangeCount = pasteboard.changeCount
        found = []
        offer = nil
    }

    func hide() {
        offer = nil
    }

    private func read(_ store: OTPStore, changeCount: Int, reportEmpty: Bool) {
        let text = pasteboard.string(forType: .string)
        let hasImage = pasteboard.availableType(from: Self.imageTypes) != nil
        let image = hasImage ? NSImage(pasteboard: pasteboard) : nil
        DispatchQueue.global(qos: .userInitiated).async {
            let accounts = ClipboardReader.accounts(text: text, image: image)
            DispatchQueue.main.async {
                guard self.scannedChangeCount == changeCount else { return }
                self.found = accounts
                self.publish(store, reportEmpty: reportEmpty)
            }
        }
    }

    private func publish(_ store: OTPStore, reportEmpty: Bool) {
        let fresh = store.newAccounts(in: found)
        guard fresh.isEmpty else {
            offer = .accounts(title: ClipboardReader.title(fresh))
            return
        }
        if reportEmpty {
            offer = .nothingFound
            hideLater()
        } else if case .accounts = offer {
            offer = nil
        }
    }

    private func detectCandidate(_ changeCount: Int) {
        if pasteboard.availableType(from: Self.imageTypes) != nil {
            offer = .check
            return
        }
        guard #available(macOS 15.4, *) else { return }
        pasteboard.__detectPatterns(forPatterns: [.__link]) { [weak self] patterns, _ in
            DispatchQueue.main.async {
                guard let self, self.scannedChangeCount == changeCount, patterns?.isEmpty == false else { return }
                self.offer = .check
            }
        }
    }

    private func hideLater() {
        let shown = offer
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.feedbackDuration) { [weak self] in
            guard let self, self.offer == shown else { return }
            self.offer = nil
        }
    }
}
