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
