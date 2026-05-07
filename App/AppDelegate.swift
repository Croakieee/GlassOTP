import AppKit
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusController: StatusBarController?
    private var sceneCoordinator: SceneCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {

        NSApp.setActivationPolicy(.accessory)

        DispatchQueue.main.async {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                UNUserNotificationCenter.current().delegate = NotificationService.shared
                NotificationService.shared.requestPermission()
            }
        }

        let rootView = RootPopoverView()
        sceneCoordinator = SceneCoordinator(rootView: rootView)

        if let popover = sceneCoordinator?.popover {
            statusController = StatusBarController(popover: popover)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // no-op
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false
    }
}
