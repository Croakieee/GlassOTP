import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusBarController?
    private var sceneCoordinator: SceneCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Скрыть из Dock на всякий случай (дублирует LSUIElement=YES в Info.plist)
        NSApp.setActivationPolicy(.accessory)

        let rootView = RootPopoverView()
        sceneCoordinator = SceneCoordinator(rootView: rootView)

        if let popover = sceneCoordinator?.popover {
            statusController = StatusBarController(popover: popover)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // no-op
    }
}
