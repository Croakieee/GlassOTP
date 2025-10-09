import AppKit
import SwiftUI

final class AddTokenWindowController: NSWindowController {
    static let shared = AddTokenWindowController()
    private var hosting: NSHostingController<AddTokenSheet>?

    // фиксированный размер окна
    private let kWindowSize = NSSize(width: 600, height: 520)

    private override init(window: NSWindow?) { super.init(window: window) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(onAddMany: @escaping ([ImportedToken]) -> Void) {
        if let win = window {
            win.makeKeyAndOrderFront(nil)
            // не активируем приложение, чтобы не светиться в Dock
            return
        }

        let sheetView = AddTokenSheet(
            onAddMany: onAddMany,
            onClose: { [weak self] in self?.close() }
        )
        let host = NSHostingController(rootView: sheetView)
        self.hosting = host

        // без .resizable — фиксированный размер
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: kWindowSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Добавить токены"
        win.contentViewController = host
        win.isReleasedWhenClosed = false

        // 🔽 Главное изменение: обычный уровень окна
        win.level = .normal

        // фиксируем размеры
        win.setContentSize(kWindowSize)
        win.minSize = kWindowSize
        win.maxSize = kWindowSize

        // поведение/эстетика
        win.center()
        win.isMovableByWindowBackground = true
        win.collectionBehavior = [.fullScreenNone] // можно убрать, не критично
        win.hidesOnDeactivate = false              // при переключении приложений остаётся, но НЕ поверх

        self.window = win

        // показываем, не активируя приложение (чтобы не появляться в Dock)
        win.makeKeyAndOrderFront(nil)
    }

    override func close() {
        super.close()
        hosting = nil
        window = nil
    }
}

