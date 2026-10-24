import Foundation

extension Notification.Name {
    static let openPopoverFromNotification = Notification.Name("openPopoverFromNotification")
    static let autoClosePopover = Notification.Name("autoClosePopover")
    static let popoverDidShow = Notification.Name("popoverDidShow")
    static let popoverDidClose = Notification.Name("popoverDidClose")
    // Keep the transient popover open while the system auth dialog is up.
    static let lockAuthBegan = Notification.Name("lockAuthBegan")
    static let lockAuthEnded = Notification.Name("lockAuthEnded")
    static let popoverKeyCommand = Notification.Name("popoverKeyCommand")
    static let keyboardCopyDone = Notification.Name("keyboardCopyDone")
    static let quickAddFeedback = Notification.Name("quickAddFeedback")
}

enum PopoverUserInfo {
    static let openedViaHotKey = "openedViaHotKey"
}

enum PopoverKeyCommand {
    case up
    case down
    case enter

    init?(keyCode: UInt16) {
        switch keyCode {
        case 126: self = .up
        case 125: self = .down
        case 36, 76: self = .enter
        default: return nil
        }
    }
}
