import AppKit
import SwiftUI

final class AddTokenWindowController: NSWindowController, NSWindowDelegate {
    static let shared = AddTokenWindowController()

    private var hosting: NSHostingController<AddTokenSheet>?
    private static func contentSize(for mode: AddMode) -> NSSize {
        switch mode {
        case .otpauth: return NSSize(width: 560, height: 420)
        case .manual: return NSSize(width: 560, height: 340)
        }
    }

    private override init(window: NSWindow?) {
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(onAddMany: @escaping ([ImportedToken]) -> ImportResult) {
        // .accessory apps can't properly bring windows to front without switching to .regular.
        NSApp.setActivationPolicy(.regular)

        if let win = window {
            hosting?.rootView = makeSheet(onAddMany: onAddMany)
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            return
        }

        let host = NSHostingController(rootView: makeSheet(onAddMany: onAddMany))
        self.hosting = host

        let initialSize = Self.contentSize(for: .otpauth)
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        win.title = "Add Token"
        win.contentViewController = host
        win.isReleasedWhenClosed = false
        win.level = .floating          // above the status-bar popover
        win.setContentSize(initialSize)
        win.contentMinSize = initialSize
        win.contentMaxSize = initialSize
        win.center()
        win.isMovableByWindowBackground = true
        win.collectionBehavior = [.fullScreenNone]
        win.hidesOnDeactivate = false
        win.delegate = self

        self.window = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    private func makeSheet(onAddMany: @escaping ([ImportedToken]) -> ImportResult) -> AddTokenSheet {
        AddTokenSheet(
            onAddMany: onAddMany,
            onClose: { [weak self] in self?.window?.close() },
            onModeChange: { [weak self] mode in self?.resize(for: mode) }
        )
    }

    private func resize(for mode: AddMode) {
        guard let win = window else { return }
        let size = Self.contentSize(for: mode)
        var frame = win.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: win.frame.minX, y: win.frame.maxY - frame.height)
        win.contentMinSize = size
        win.contentMaxSize = size
        win.setFrame(frame, display: true, animate: true)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        hosting = nil
        window = nil
        // Restore menubar-only mode when the window is gone.
        NSApp.setActivationPolicy(.accessory)
    }
}
