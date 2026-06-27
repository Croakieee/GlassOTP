import Foundation

extension Notification.Name {
    static let storeReady = Notification.Name("storeReady")
    static let openPopoverFromNotification = Notification.Name("openPopoverFromNotification")
    static let autoClosePopover = Notification.Name("autoClosePopover")
    static let popoverDidShow = Notification.Name("popoverDidShow")
    static let popoverDidClose = Notification.Name("popoverDidClose")
    // Keep the transient popover open while the system auth dialog is up.
    static let lockAuthBegan = Notification.Name("lockAuthBegan")
    static let lockAuthEnded = Notification.Name("lockAuthEnded")
}
