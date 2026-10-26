import AppKit
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusController: StatusBarController?
    private var sceneCoordinator: SceneCoordinator?
    private var store: OTPStore?
    private var pendingLinks: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {

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

        let store = OTPStore()
        self.store = store
        ShortcutAccess.store = store

        let rootView = RootPopoverView(store: store)
        sceneCoordinator = SceneCoordinator(rootView: rootView)

        if let popover = sceneCoordinator?.popover {
            statusController = StatusBarController(popover: popover, store: store)
        }
        NSApp.servicesProvider = statusController
        NSUpdateDynamicServices()
        showPendingLinks()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingLinks += urls
            .filter { Self.linkSchemes.contains($0.scheme?.lowercased() ?? "") }
            .map(\.absoluteString)
        showPendingLinks()
    }

    private func showPendingLinks() {
        guard !pendingLinks.isEmpty, let store else { return }
        let link = pendingLinks.joined(separator: "\n")
        pendingLinks = []
        AddTokenWindowController.shared.show(prefill: AddPrefill(link: link)) { list in
            store.addImportedMany(list)
        }
    }

    private static let linkSchemes: Set<String> = ["otpauth", "otpauth-migration"]

    func applicationWillTerminate(_ notification: Notification) {
        // no-op
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false
    }
}
