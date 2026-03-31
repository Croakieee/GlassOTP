import AppKit
import SwiftUI

final class AddTokenWindowController: NSWindowController {
    static let shared = AddTokenWindowController()

    private var hosting: NSHostingController<AddTokenSheet>?

    // активный store
    private var store: OTPStore?

    // фиксированный размер окна
    private let kWindowSize = NSSize(width: 600, height: 520)

    private override init(window: NSWindow?) {
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // j,yjdktyysq show
    func show(store: OTPStore,
              onAddMany: @escaping ([ImportedToken]) -> Void) {

        // сохраняем store
        self.store = store

        if let win = window {
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            return
        }

        let sheetView = AddTokenSheet(
            store: store, // fix
            onAddMany: onAddMany,
            onClose: { [weak self] in self?.close() }
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

        win.level = .normal

        win.setContentSize(kWindowSize)
        win.minSize = kWindowSize
        win.maxSize = kWindowSize

        win.center()
        win.isMovableByWindowBackground = true
        win.collectionBehavior = [.fullScreenNone]
        win.hidesOnDeactivate = false

        self.window = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    override func close() {
        super.close()
        hosting = nil
        window = nil
        store = nil
    }
}
