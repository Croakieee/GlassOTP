import AppKit
import AppIntents

enum ShortcutAccess {
    static weak var store: OTPStore?
}

@available(macOS 13, *)
enum ShortcutError: Error, CustomLocalizedStringResourceConvertible {
    case disabled
    case unavailable
    case notFound
    case denied
    case noSecret

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .disabled:
            return "Turn on “Allow Shortcuts to read codes” in GlassOTP settings."
        case .unavailable:
            return "GlassOTP isn't ready yet. Try again in a moment."
        case .notFound:
            return "This account is no longer in GlassOTP."
        case .denied:
            return "GlassOTP couldn't confirm it's you."
        case .noSecret:
            return "GlassOTP couldn't read this account from the Keychain."
        }
    }
}

@available(macOS 13, *)
struct GlassOTPAccount: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static let defaultQuery = GlassOTPAccountQuery()

    let id: UUID
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    init(_ token: OTPToken) {
        id = token.id
        title = token.displayTitle
    }
}

@available(macOS 13, *)
struct GlassOTPAccountQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [GlassOTPAccount] {
        try Self.tokens().filter { identifiers.contains($0.id) }.map(GlassOTPAccount.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [GlassOTPAccount] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return try Self.tokens()
            .filter { query.isEmpty || $0.displayTitle.lowercased().contains(query) }
            .map(GlassOTPAccount.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [GlassOTPAccount] {
        try Self.tokens().map(GlassOTPAccount.init)
    }

    @MainActor
    private static func tokens() throws -> [OTPToken] {
        guard AppState.shared.shortcutsReadCodes else { throw ShortcutError.disabled }
        guard let store = ShortcutAccess.store else { throw ShortcutError.unavailable }
        return store.tokens
    }
}

@available(macOS 13, *)
struct GetCodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Get GlassOTP Code"
    static let description = IntentDescription("Returns the current code for an account in GlassOTP.")

    @Parameter(title: "Account")
    var account: GlassOTPAccount

    @Parameter(title: "Copy to Clipboard", default: false)
    var copyToClipboard: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Get the code for \(\.$account)") {
            \.$copyToClipboard
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard AppState.shared.shortcutsReadCodes else { throw ShortcutError.disabled }
        guard let store = ShortcutAccess.store else { throw ShortcutError.unavailable }
        guard let token = store.tokens.first(where: { $0.id == account.id }) else { throw ShortcutError.notFound }

        if AppState.shared.requireUnlock || token.isProtected {
            let confirmed = await withCheckedContinuation { continuation in
                DeviceAuth.authenticate(reason: "get a code for \(token.displayTitle)") { continuation.resume(returning: $0) }
            }
            guard confirmed else { throw ShortcutError.denied }
        }

        guard let code = store.liveCode(for: token) else { throw ShortcutError.noSecret }
        store.recordUse(token.id)
        if copyToClipboard {
            CodeClipboard.copy(code, playSound: false)
        }
        return .result(value: code)
    }
}

@available(macOS 13, *)
struct GlassOTPShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GetCodeIntent(), phrases: ["Get a code in \(.applicationName)"])
    }
}
