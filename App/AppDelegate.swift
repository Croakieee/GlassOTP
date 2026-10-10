import AppKit
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusController: StatusBarController?
    private var sceneCoordinator: SceneCoordinator?
    private var store: OTPStore?

    func applicationDidFinishLaunching(_ notification: Notification) {

        // The login item runs the executable directly, which bypasses LaunchServices' own
        // single-instance check. If an older copy is already running, quit this one so there
        // is never a second status-bar icon.
        if let bundleID = Bundle.main.bundleIdentifier {
            let me = NSRunningApplication.current
            let olderExists = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID)
                .contains { other in
                    guard other.processIdentifier != me.processIdentifier else { return false }
                    if let a = other.launchDate, let b = me.launchDate, a != b { return a < b }
                    return other.processIdentifier < me.processIdentifier
                }
            if olderExists {
                NSApp.terminate(nil)
                return
            }
        }

        NSApp.setActivationPolicy(.accessory)

        UNUserNotificationCenter.current().delegate = NotificationService.shared
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NotificationService.shared.requestPermission()
        }

        // Single source of truth, created once and shared with both the popover UI and the
        // status-bar menu. Previously the store reached the controller only via .storeReady
        // posted from the popover's onAppear, so the menu's Export/Import/Delete All were
        // dead until the popover had been opened at least once.
        let store = OTPStore()
        self.store = store

        let rootView = RootPopoverView(store: store)
        sceneCoordinator = SceneCoordinator(rootView: rootView)

        if let popover = sceneCoordinator?.popover {
            statusController = StatusBarController(popover: popover, store: store)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // no-op
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false
    }
}
