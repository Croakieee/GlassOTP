import AppKit
import SwiftUI

final class AddTokenWindowController: NSWindowController {
    static let shared = AddTokenWindowController()
    private var hosting: NSHostingController<AddTokenSheet>?

    private override init(window: NSWindow?) { super.init(window: window) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(onAddMany: @escaping ([ImportedToken]) -> Void) {
        if let win = window {
            win.makeKeyAndOrderFront(nil)
            // ⛔️ не активируем приложение, чтобы не появлялось в Dock
            return
        }

        let sheetView = AddTokenSheet(
            onAddMany: onAddMany,
            onClose: { [weak self] in self?.close() }
        )
        let host = NSHostingController(rootView: sheetView)
        self.hosting = host

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Добавить токены"
        win.contentViewController = host
        win.isReleasedWhenClosed = false
        win.level = .floating   // окно можно двигать, но оно не поверх всего
        win.center()
        win.isMovableByWindowBackground = true
        win.collectionBehavior = [.fullScreenNone]
        self.window = win

        win.makeKeyAndOrderFront(nil)
        //  не активируем приложение
    }

    override func close() {
        super.close()
        hosting = nil
        window = nil
    }
}
