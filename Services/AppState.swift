import Foundation
import Combine

final class AppState: ObservableObject {
    static let shared = AppState()

    private let pinKey = "GlassOTP.pinPopover"
    private let autoCloseKey = "GlassOTP.autoCloseOnCopy"
    private let requireUnlockKey = "GlassOTP.requireUnlock"

    @Published var pinPopover: Bool {
        didSet { UserDefaults.standard.set(pinPopover, forKey: pinKey) }
    }

    /// Close the popover ~2s after a code is copied.
    @Published var autoCloseOnCopy: Bool {
        didSet { UserDefaults.standard.set(autoCloseOnCopy, forKey: autoCloseKey) }
    }

    /// Require Touch ID / device authentication before codes are shown in the popover.
    @Published var requireUnlock: Bool {
        didSet { UserDefaults.standard.set(requireUnlock, forKey: requireUnlockKey) }
    }

    private init() {
        self.pinPopover = UserDefaults.standard.bool(forKey: pinKey)
        // Default ON to preserve existing behaviour; `object(forKey:)` distinguishes "unset" from "false".
        self.autoCloseOnCopy = UserDefaults.standard.object(forKey: autoCloseKey) as? Bool ?? true
        self.requireUnlock = UserDefaults.standard.object(forKey: requireUnlockKey) as? Bool ?? false
    }
}

// MARK: - Launch at login

/// Launch-at-login via a per-user LaunchAgent plist in ~/Library/LaunchAgents.
///
/// Why this mechanism: it works the same on macOS 11.7 through current releases and needs no
/// helper target or Team-ID signing (SMAppService is 13+, SMLoginItemSetEnabled needs a signed
/// helper bundle). The sandbox allows it through the
/// `temporary-exception.files.home-relative-path.read-write` entitlement for
/// `/Library/LaunchAgents/`. launchd reads the folder at login, so nothing has to be loaded now.
enum LoginItem {

    enum Failure: LocalizedError {
        case noExecutable
        case translocated
        case noHome

        var errorDescription: String? {
            switch self {
            case .noExecutable: return "Couldn't locate the app executable."
            case .translocated: return "Move GlassOTP to the Applications folder and reopen it, then try again."
            case .noHome:       return "Couldn't locate the home folder."
            }
        }
    }

    private static let label = "com.glassotp.loginitem"

    /// The plist lives in the REAL home folder — NSHomeDirectory() is the sandbox container.
    private static var plistURL: URL? {
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    /// Enabled only if the plist exists AND points at this copy of the app, so a moved or
    /// replaced app shows as off and re-enabling rewrites the path.
    static var isEnabled: Bool {
        guard let url = plistURL,
              let dict = NSDictionary(contentsOf: url),
              let args = dict["ProgramArguments"] as? [String] else { return false }
        return args.first == Bundle.main.executablePath
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard let url = plistURL else { throw Failure.noHome }
        let fm = FileManager.default

        guard enabled else {
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
            return
        }

        guard let executable = Bundle.main.executablePath else { throw Failure.noExecutable }
        // A quarantined app run from Downloads executes from a random read-only path that
        // won't exist at the next login.
        guard !executable.contains("/AppTranslocation/") else { throw Failure.translocated }

        var plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua"
        ]
        // Lets macOS 13+ show the entry under the app's name in Login Items (ignored on 11–12).
        if let bundleID = Bundle.main.bundleIdentifier {
            plist["AssociatedBundleIdentifiers"] = [bundleID]
        }

        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        // Non-atomic on purpose: an atomic write stages a temp file outside the one folder the
        // sandbox exception covers.
        try data.write(to: url)
    }
}
