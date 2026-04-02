import AppKit
import SwiftUI
import Combine

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var eventMonitor: Any?
    private var cancellable: AnyCancellable?
    private let appState = AppState.shared

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

            // разделяем ЛКМ и ПКМ
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(handleClick(_:))
        }

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

    @objc private func handleStore(_ note: Notification) {
        if let store = note.object as? OTPStore {
            self.store = store
        }
    }

    // MARK: - Click handling

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover(sender)
        }
    }

    // MARK: - MENU

    private func showMenu() {
        guard let button = statusItem.button else { return }

        let menu = NSMenu()

        func item(_ title: String, _ action: Selector) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self
            return i
        }

        menu.addItem(item("Open", #selector(openApp)))

        menu.addItem(.separator())

        menu.addItem(item("Export", #selector(exportTokens)))
        menu.addItem(item("Import", #selector(importTokens)))

        menu.addItem(.separator())

        menu.addItem(item("Delete All", #selector(deleteAll)))

        menu.addItem(.separator())

        let pinItem = item("Pin popover", #selector(togglePin))
        pinItem.state = appState.pinPopover ? .on : .off
        menu.addItem(pinItem)

        menu.addItem(.separator())

        menu.addItem(item("Exit", #selector(exitApp)))

        // фикс серое меню пкм
        let location = NSPoint(x: button.bounds.midX, y: 0)
        menu.popUp(positioning: nil, at: location, in: button)
    }

    // MARK: - Actions

    @objc private func openApp() {
        togglePopover(nil)
    }

    @objc private func togglePin() {
        appState.pinPopover.toggle()
    }

    @objc private func exitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func deleteAll() {
        guard let store = store else { return }

        let alert = NSAlert()
        alert.messageText = "Delete all tokens?"
        alert.informativeText = "This action cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            store.removeAllTokens()
        }
    }

    @objc private func exportTokens() {
        guard let store = store else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "backup.glassotp"

        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }

            self.askPassword { password in
                do {
                    let data = try BackupService.export(
                        tokens: store.tokens,
                        store: store,
                        password: password
                    )
                    try data.write(to: url)
                } catch {
                    print(error)
                }
            }
        }
    }

    @objc private func importTokens() {
        guard let store = store else { return }

        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["glassotp"]

        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }

            self.askPassword { password in
                do {
                    let data = try Data(contentsOf: url)
                    let tokens = try BackupService.import(data: data, password: password)
                    store.addImportedMany(tokens)
                } catch {
                    print("Import failed")
                }
            }
        }
    }

    private func askPassword(completion: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Enter password"

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = input

        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            completion(input.stringValue)
        }
    }

    // MARK: - Popover

    private func applyPinBehavior(pinned: Bool) {
        popover.behavior = pinned ? .applicationDefined : .transient

        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        if !pinned {
            eventMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                guard let self = self else { return }
                if self.popover.isShown {
                    self.closePopover(sender: nil)
                }
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

        store?.timer.resume()

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closePopover(sender: Any?) {
        popover.performClose(sender)
        store?.timer.pause()
    }
}
