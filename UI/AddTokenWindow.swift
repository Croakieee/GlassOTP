import AppKit
import SwiftUI

final class AddTokenWindowController: NSWindowController, NSWindowDelegate {
    static let shared = AddTokenWindowController()

    private var hosting: NSHostingController<AddTokenSheet>?
    private let kWindowSize = NSSize(width: 600, height: 520)

    private override init(window: NSWindow?) {
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(onAddMany: @escaping ([ImportedToken]) -> Int) {
        // .accessory apps can't properly bring windows to front without switching to .regular.
        NSApp.setActivationPolicy(.regular)

        if let win = window {
            // Reuse the open window, but refresh the callback so a stale closure from an
            // earlier show() can't be invoked.
            hosting?.rootView = AddTokenSheet(
                onAddMany: onAddMany,
                onClose: { [weak self] in self?.window?.close() }
            )
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            return
        }

        let sheetView = AddTokenSheet(
            onAddMany: onAddMany,
            onClose: { [weak self] in self?.window?.close() }
        )

        let host = NSHostingController(rootView: sheetView)
        self.hosting = host

        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: kWindowSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        win.title = "Add Token(s)"
        win.contentViewController = host
        win.isReleasedWhenClosed = false
        win.level = .floating          // above the status-bar popover
        win.setContentSize(kWindowSize)
        win.minSize = kWindowSize
        win.maxSize = kWindowSize
        win.center()
        win.isMovableByWindowBackground = true
        win.collectionBehavior = [.fullScreenNone]
        win.hidesOnDeactivate = false
        win.delegate = self

        self.window = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        hosting = nil
        window = nil
        // Restore menubar-only mode when the window is gone.
        NSApp.setActivationPolicy(.accessory)
    }
}
