import AppKit
import SwiftUI
import Combine

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var eventMonitor: Any?
    private var cancellable: AnyCancellable?
    private let appState = AppState.shared

    private let store: OTPStore

    private var autoCloseWork: DispatchWorkItem?
    private static let autoCloseDelay: TimeInterval = 2.0

    init(popover: NSPopover, store: OTPStore) {
        self.popover = popover
        self.store = store
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
            selector: #selector(handleOpenFromNotification),
            name: .openPopoverFromNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAutoClose),
            name: .autoClosePopover,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(suspendAutoClose),
            name: .lockAuthBegan,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(resumeAutoClose),
            name: .lockAuthEnded,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePopoverDidClose),
            name: NSPopover.didCloseNotification,
            object: popover
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

    @objc private func handleAutoClose() {
        guard !appState.pinPopover else { return }
        cancelAutoClose()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.popover.isShown else { return }
            self.closePopover(sender: nil)
        }
        autoCloseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoCloseDelay, execute: work)
    }

    private func cancelAutoClose() {
        autoCloseWork?.cancel()
        autoCloseWork = nil
    }

    // While Touch ID / password auth is on screen, stop the popover from auto-closing
    // (the auth dialog steals focus, which would dismiss a transient popover).
    @objc private func suspendAutoClose() {
        popover.behavior = .applicationDefined
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    @objc private func resumeAutoClose() {
        applyPinBehavior(pinned: appState.pinPopover)
    }

    // Authoritative "popover closed" signal (fires for transient auto-close too, unlike
    // our closePopover). Drives the app lock's re-lock on close.
    @objc private func handlePopoverDidClose() {
        store.timer.pause()
        cancelAutoClose()
        NotificationCenter.default.post(name: .popoverDidClose, object: nil)
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
    
    // Notification on popup - (закрытие после открытия =)
    @objc private func handleOpenFromNotification() {
        showPopover(sender: nil)

        // вернуть приложение обратно в "background"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.setActivationPolicy(.accessory)
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

        let loginItem = item("Launch at login", #selector(toggleLaunchAtLogin))
        loginItem.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(loginItem)

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

    @objc private func toggleLaunchAtLogin() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            showAlert(title: "Couldn't change launch at login", text: error.localizedDescription)
        }
    }

    @objc private func exitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func deleteAll() {
        let alert = NSAlert()
        alert.messageText = "Delete all tokens?"
        alert.informativeText = "This action cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        DeviceAuth.authenticate(reason: "delete all your OTP tokens") { [weak self] granted in
            guard granted else { return }
            self?.performDeleteAll()
        }
    }

    private func performDeleteAll() {
        let count = store.tokens.count
        do {
            try store.removeAllTokens()
        } catch {
            showAlert(
                title: "Couldn't delete tokens",
                text: "The secret storage couldn't be reset: \(error.localizedDescription)"
            )
            return
        }

        NotificationService.shared.show(
            title: "All tokens deleted",
            body: "\(count) tokens removed"
        )
    }

    @objc private func exportTokens() {
        DeviceAuth.authenticate(reason: "export all your OTP secrets to a backup file") { [weak self] granted in
            guard granted else { return }
            self?.performExport()
        }
    }

    private func performExport() {
        let store = self.store
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "backup.glassotp"
        panel.allowedFileTypes = ["glassotp"]
        panel.isExtensionHidden = false

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        askPassword(confirm: true) { password in
            let tokens = store.tokens
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try BackupService.export(
                        tokens: tokens,
                        store: store,
                        password: password
                    )
                    try data.write(to: url)

                    DispatchQueue.main.async {
                        NotificationService.shared.show(
                            title: "Export complete",
                            body: "Backup saved successfully"
                        )
                    }
                } catch {
                    let message = error.localizedDescription
                    DispatchQueue.main.async {
                        NotificationService.shared.show(
                            title: "Export failed",
                            body: message
                        )
                    }
                }
            }
        }
    }

    @objc private func importTokens() {
        let store = self.store
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["glassotp"]

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        askPassword { password in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try Data(contentsOf: url)

                    let imported = try BackupService.import(
                        data: data,
                        password: password
                    )

                    DispatchQueue.main.async {
                        let result = store.addImportedMany(imported)

                        if result.failed > 0 {
                            let hint = store.vaultCorrupted
                                ? " The secret storage is damaged: use Delete All, then import the backup again."
                                : ""
                            self.showAlert(
                                title: "Import incomplete",
                                text: "\(result.failed) token(s) couldn't be saved to the Keychain.\(hint)"
                            )
                        }

                        if result.added > 0 {
                            NotificationService.shared.show(
                                title: "Import complete",
                                body: "\(result.added) new token(s) added, \(result.duplicates) already existed"
                            )
                        } else if result.failed == 0 {
                            NotificationService.shared.show(
                                title: "Import skipped",
                                body: "All tokens already exist"
                            )
                        }
                    }

                } catch {
                    DispatchQueue.main.async {
                        self.showAlert(
                            title: "Import failed",
                            text: "Wrong password or corrupted file."
                        )
                    }
                }
            }
        }
    }

    private func showAlert(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func askPassword(confirm: Bool = false,
                             errorText: String? = nil,
                             completion: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = confirm ? "Set backup password" : "Enter password"
        if let errorText = errorText {
            alert.informativeText = errorText
        }

        let fieldWidth: CGFloat = 240
        let fieldHeight: CGFloat = 24

        let pwField: NSSecureTextField
        let confirmField: NSSecureTextField?
        if confirm {
            let spacing: CGFloat = 8
            let container = NSView(frame: NSRect(x: 0, y: 0, width: fieldWidth, height: fieldHeight * 2 + spacing))

            let top = NSSecureTextField(frame: NSRect(x: 0, y: fieldHeight + spacing, width: fieldWidth, height: fieldHeight))
            top.placeholderString = "Password"

            let bottom = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: fieldWidth, height: fieldHeight))
            bottom.placeholderString = "Repeat password"

            container.addSubview(top)
            container.addSubview(bottom)

            alert.accessoryView = container
            pwField = top
            confirmField = bottom
        } else {
            pwField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: fieldWidth, height: fieldHeight))
            alert.accessoryView = pwField
            confirmField = nil
        }

        alert.window.initialFirstResponder = pwField
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let password = pwField.stringValue

        if confirm {
            if password.isEmpty {
                askPassword(confirm: true, errorText: "Password can't be empty.", completion: completion)
                return
            }
            if password != (confirmField?.stringValue ?? "") {
                askPassword(confirm: true, errorText: "Passwords don't match. Try again.", completion: completion)
                return
            }
            if password.count < 8 {
                let warn = NSAlert()
                warn.messageText = "Weak password"
                warn.informativeText = "This password is shorter than 8 characters. The backup contains all your secrets. Use it anyway?"
                warn.addButton(withTitle: "Change")
                warn.addButton(withTitle: "Use anyway")
                NSApp.activate(ignoringOtherApps: true)
                if warn.runModal() == .alertFirstButtonReturn {
                    askPassword(confirm: true, completion: completion)
                    return
                }
            }
        }

        completion(password)
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

        cancelAutoClose()
        store.timer.resume()

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    //    NSApp.activate(ignoringOtherApps: true)

        // Re-evaluate the lock each time the popover opens (NSPopover doesn't reliably
        // re-fire SwiftUI .onAppear on subsequent shows).
        NotificationCenter.default.post(name: .popoverDidShow, object: nil)
    }

    private func closePopover(sender: Any?) {
        popover.performClose(sender)
        store.timer.pause()
    }
}
