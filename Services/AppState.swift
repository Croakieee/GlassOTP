import Foundation
import Combine

final class AppState: ObservableObject {
    static let shared = AppState()

    private let pinKey = "GlassOTP.pinPopover"
    private let autoCloseKey = "GlassOTP.autoCloseOnCopy"
    private let requireUnlockKey = "GlassOTP.requireUnlock"
    private let copySoundKey = "GlassOTP.playSoundOnCopy"
    private let globalHotKeyKey = "GlassOTP.globalHotKey"
    private let sortByUsageKey = "GlassOTP.sortByUsage"
    private let hotpAdvanceKey = "GlassOTP.hotpAdvancesOnCopy"
    private let clipboardKey = "GlassOTP.suggestFromClipboard"
    private let doubleHotKeyKey = "GlassOTP.doubleHotKeyScans"

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

    @Published var playSoundOnCopy: Bool {
        didSet { UserDefaults.standard.set(playSoundOnCopy, forKey: copySoundKey) }
    }

    @Published var globalHotKeyEnabled: Bool {
        didSet { UserDefaults.standard.set(globalHotKeyEnabled, forKey: globalHotKeyKey) }
    }

    @Published var sortByUsage: Bool {
        didSet { UserDefaults.standard.set(sortByUsage, forKey: sortByUsageKey) }
    }

    @Published var hotpAdvancesOnCopy: Bool {
        didSet { UserDefaults.standard.set(hotpAdvancesOnCopy, forKey: hotpAdvanceKey) }
    }

    @Published var suggestFromClipboard: Bool {
        didSet { UserDefaults.standard.set(suggestFromClipboard, forKey: clipboardKey) }
    }

    @Published var doubleHotKeyScans: Bool {
        didSet { UserDefaults.standard.set(doubleHotKeyScans, forKey: doubleHotKeyKey) }
    }

    private init() {
        self.pinPopover = UserDefaults.standard.bool(forKey: pinKey)
        // Default ON to preserve existing behaviour; `object(forKey:)` distinguishes "unset" from "false".
        self.autoCloseOnCopy = UserDefaults.standard.object(forKey: autoCloseKey) as? Bool ?? true
        self.requireUnlock = UserDefaults.standard.object(forKey: requireUnlockKey) as? Bool ?? false
        self.playSoundOnCopy = UserDefaults.standard.object(forKey: copySoundKey) as? Bool ?? true
        self.globalHotKeyEnabled = UserDefaults.standard.object(forKey: globalHotKeyKey) as? Bool ?? true
        self.sortByUsage = UserDefaults.standard.object(forKey: sortByUsageKey) as? Bool ?? true
        self.hotpAdvancesOnCopy = UserDefaults.standard.object(forKey: hotpAdvanceKey) as? Bool ?? true
        self.suggestFromClipboard = UserDefaults.standard.object(forKey: clipboardKey) as? Bool ?? true
        self.doubleHotKeyScans = UserDefaults.standard.object(forKey: doubleHotKeyKey) as? Bool ?? true
    }
}

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

    private static var plistURL: URL? {
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

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
        guard !executable.contains("/AppTranslocation/") else { throw Failure.translocated }

        var plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua"
        ]
        if let bundleID = Bundle.main.bundleIdentifier {
            plist["AssociatedBundleIdentifiers"] = [bundleID]
        }

        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url)
    }
}
