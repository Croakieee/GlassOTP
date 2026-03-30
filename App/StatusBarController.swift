import AppKit
import SwiftUI
import Combine

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var eventMonitor: Any?
    private var cancellable: AnyCancellable?
    private let appState = AppState.shared

    // добавили store
    private var store: OTPStore?

    init(popover: NSPopover) {
        self.popover = popover
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "key.fill", accessibilityDescription: "GlassOTP") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "OTP"
            }
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        // слушаем store из SwiftUI
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStore(_:)),
            name: .storeReady,
            object: nil
        )

        cancellable = appState.$pinPopover.sink { [weak self] pinned in
            self?.applyPinBehavior(pinned: pinned)
        }

        applyPinBehavior(pinned: appState.pinPopover)
    }

    deinit {
        if let monitor = eventMonitor { NSEvent.removeMonitor(monitor) }
        cancellable?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    // получаем store
    @objc private func handleStore(_ note: Notification) {
        if let store = note.object as? OTPStore {
            self.store = store
        }
    }

    private func applyPinBehavior(pinned: Bool) {
        popover.behavior = pinned ? .applicationDefined : .transient

        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        if !pinned {
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self = self else { return }
                if self.popover.isShown { self.closePopover(sender: nil) }
            }
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover(sender: sender)
        } else {
            showPopover(sender: sender)
        }
    }

    private func showPopover(sender: Any?) {
        guard let button = statusItem.button else { return }

        // вкл таймер
        store?.timer.resume()

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closePopover(sender: Any?) {
        popover.performClose(sender)

        //  выкл таймер
        store?.timer.pause()
    }
}


import Foundation

extension Notification.Name {
    static let storeReady = Notification.Name("storeReady")
}
