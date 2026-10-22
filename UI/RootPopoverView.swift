import SwiftUI
import Combine
import UserNotifications

private struct RenameHandle: Identifiable, Equatable { let id: UUID }

struct RootPopoverView: View {

    @ObservedObject private var store: OTPStore
    @ObservedObject private var appState = AppState.shared

    init(store: OTPStore) {
        _store = ObservedObject(wrappedValue: store)
    }

    // app-wide lock gate (opt-in via appState.requireUnlock).
    // `unlocked` holds only for the current open session: it's reset on every popover close.
    @State private var unlocked: Bool = false
    @State private var authInProgress: Bool = false

    // rename
    @State private var renameHandle: RenameHandle?
    @State private var renameIssuer: String = ""
    @State private var renameAccount: String = ""

    // edit secret
    @State private var editSecretToken: OTPToken?

    // QR
    @State private var qrToken: OTPToken?

    // auth cache
    @State private var lastAuthTime: Date?

    // delete confirm
    @State private var deleteTokenID: UUID?
    @State private var showDeleteAlert: Bool = false

    @State private var notificationsDenied: Bool = false

    @State private var keyboardActive: Bool = false
    @State private var selectedID: UUID?
    @State private var keyboardCopiedID: UUID?

    var body: some View {

        VStack(alignment: .leading, spacing: 8) {

            header
                .padding(.horizontal, 4)   // buttons need clearance from the rounded corners

            warnings

            if showContent {
                searchField

                TokenListView(
                    store: store,
                    timer: store.timer,
                    autoCloseOnCopy: $appState.autoCloseOnCopy,
                    playsCopySound: appState.playSoundOnCopy,
                    selectedID: highlightedID,
                    keyboardCopiedID: keyboardCopiedID,
                    onPin: { id in store.togglePin(id) },
                    onRename: { id in beginRename(id) },
                    onEditSecret: { id in beginEditSecret(id) },
                    onDelete: { id in beginDelete(id) },
                    onShowQR: { id in beginShowQR(id) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                lockView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

        }
        // Snug padding: close to the rounded edges but with a little breathing room.
        .padding(.horizontal, 6)
        .padding(.top, 8)
        // Single rounded card that fills the popover: content + material are clipped to the
        // same shape, so the token area follows the rounded contour instead of square corners,
        // and there's no inset ring doubling the border.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground(material: .hud, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            applyLockOnOpen()
            refreshNotificationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .popoverDidShow)) { note in
            applyLockOnOpen()
            refreshNotificationStatus()
            keyboardActive = note.userInfo?[PopoverUserInfo.openedViaHotKey] as? Bool ?? false
            selectedID = store.filteredTokens().first?.id
        }
        .onReceive(NotificationCenter.default.publisher(for: .popoverKeyCommand)) { note in
            guard let command = note.object as? PopoverKeyCommand else { return }
            handleKey(command)
        }
        .onChange(of: store.query) { query in
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                keyboardActive = true
            }
            selectedID = store.filteredTokens().first?.id
        }
        .onReceive(NotificationCenter.default.publisher(for: .popoverDidClose)) { _ in
            store.query = ""
            keyboardActive = false
            selectedID = nil
            keyboardCopiedID = nil
            // Re-lock whenever the popover closes so the next open requires auth again.
            guard !authInProgress else { return }
            if appState.requireUnlock { unlocked = false }
        }
        .onChange(of: appState.requireUnlock) { enabled in
            // Enabling locks immediately; disabling reveals the content.
            unlocked = !enabled
        }

        .sheet(item: $renameHandle, onDismiss: {
            renameIssuer = ""
            renameAccount = ""
        }) { _ in

            RenameTokenSheet(
                originalIssuer: renameIssuer,
                originalAccount: renameAccount
            ) { newIssuer, newAccount in

                if let id = renameHandle?.id {
                    store.rename(id, issuer: newIssuer, account: newAccount)
                }

            }
        }

        .sheet(item: $editSecretToken) { token in

            EditSecretView(
                token: token,
                store: store
            ) {
                editSecretToken = nil
            }

        }

        .sheet(item: $qrToken) { token in

            TokenQRView(
                token: token,
                store: store
            ) {
                qrToken = nil
            }

        }

        .alert(isPresented: $showDeleteAlert) {

            Alert(
                title: Text("Delete token?"),
                message: Text("This action cannot be undone. The secret will be removed from the keychain."),
                primaryButton: .destructive(Text("Delete")) {

                    if let id = deleteTokenID {
                        store.remove(id)
                    }

                    deleteTokenID = nil
                },
                secondaryButton: .cancel {
                    deleteTokenID = nil
                }
            )

        }
    }

    // MARK: Header

    private var header: some View {

        HStack {

            Image(systemName: "key.fill")
                .imageScale(.medium)
                .foregroundColor(.primary.opacity(0.8))

            Text("GlassOTP")
                .font(.headline)
                .foregroundColor(.primary)

            Spacer()

            Menu {
                Toggle("Close after copy", isOn: $appState.autoCloseOnCopy)
                Toggle("Play sound on copy", isOn: $appState.playSoundOnCopy)
                Toggle("Global shortcut ⌥⌘O", isOn: $appState.globalHotKeyEnabled)
                Toggle("Require Touch ID to view", isOn: requireUnlockBinding)
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .frame(width: 38)
            .help("Settings")

            Button(action: {

                AddTokenWindowController.shared.show { list in
                    return store.addImportedMany(list)
                }

            }) {

                Image(systemName: "plus")

            }
            .buttonStyle(BorderlessButtonStyle())
            .help("Add token")

        }
    }

    @ViewBuilder
    private var warnings: some View {
        if store.vaultCorrupted {
            warningLine(
                icon: "exclamationmark.triangle.fill",
                text: "Secret storage is damaged. Use Delete All in the menu, then import a backup.",
                color: .orange
            )
        }
        if store.keychainUnavailable {
            HStack(spacing: 0) {
                warningLine(
                    icon: "exclamationmark.triangle.fill",
                    text: "No access to the Keychain, so codes can't be shown.",
                    color: .orange
                )
                Button("Retry", action: retryKeychainAccess)
                    .buttonStyle(BorderlessButtonStyle())
                    .font(.footnote)
                    .padding(.trailing, 6)
            }
        }
        if store.tokenListUnreadable {
            warningLine(
                icon: "exclamationmark.triangle.fill",
                text: "Some saved tokens couldn't be read. Restore missing ones from a backup.",
                color: .orange
            )
        }
        if notificationsDenied {
            warningLine(
                icon: "bell.slash",
                text: "Notifications are off — some confirmations won’t appear.",
                color: .secondary
            )
        }
    }

    private func warningLine(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(text)
                .font(.footnote)
            Spacer(minLength: 0)
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
    }

    private func retryKeychainAccess() {
        NotificationCenter.default.post(name: .lockAuthBegan, object: nil)
        store.retryKeychainAccess()
        NotificationCenter.default.post(name: .lockAuthEnded, object: nil)
    }

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let denied = settings.authorizationStatus == .denied
            DispatchQueue.main.async { notificationsDenied = denied }
        }
    }

    // MARK: Lock screen

    private var showContent: Bool {
        !appState.requireUnlock || unlocked
    }

    private var lockView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Locked")
                .font(.headline)
            Text("Authenticate to view your codes.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(action: promptUnlock) {
                Label("Unlock", systemImage: "touchid")
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// Locks on every fresh popover open — the unlocked state never persists across opens.
    /// Does NOT auto-prompt; the user taps Unlock when ready.
    private func applyLockOnOpen() {
        if appState.requireUnlock { unlocked = false }
    }

    private func promptUnlock() {
        runLockAuth { unlocked = true }
    }

    /// Binding for the "Require Touch ID" toggle. Turning it ON is free; turning it OFF
    /// while the screen is locked requires authentication first — otherwise it could be
    /// unticked straight from the lock screen to bypass the lock.
    private var requireUnlockBinding: Binding<Bool> {
        Binding(
            get: { appState.requireUnlock },
            set: { newValue in
                if newValue {
                    appState.requireUnlock = true
                } else if appState.requireUnlock && !unlocked {
                    // defer so the menu dismisses before the system auth dialog appears
                    DispatchQueue.main.async { runLockAuth { appState.requireUnlock = false } }
                } else {
                    appState.requireUnlock = false
                }
            }
        )
    }

    /// Runs the lock authentication: keeps the popover open across the system dialog and
    /// always forces a real prompt (ignores the shared show-secret cache).
    private func runLockAuth(_ onSuccess: @escaping () -> Void) {
        guard !authInProgress else { return }
        authInProgress = true
        NotificationCenter.default.post(name: .lockAuthBegan, object: nil)
        authenticate(force: true) { success in
            authInProgress = false
            NotificationCenter.default.post(name: .lockAuthEnded, object: nil)
            if success { onSuccess() }
        }
    }

    // MARK: Search

    private var searchField: some View {

        HStack(spacing: 8) {

            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search accounts…", text: $store.query)
                .textFieldStyle(PlainTextFieldStyle())
                .disableAutocorrection(true)
                .font(.system(size: 13, weight: .regular, design: .rounded))

        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.08))
        )
    }

    // MARK: Auth helpers

    private func isAuthRecent() -> Bool {
        guard let lastAuthTime else { return false }
        return Date().timeIntervalSince(lastAuthTime) < 30
    }

    private func authenticate(force: Bool = false, _ completion: @escaping (Bool) -> Void) {

        if !force && isAuthRecent() {
            completion(true)
            return
        }

        DeviceAuth.authenticate(reason: "access your protected OTP data") { success in
            if success {
                lastAuthTime = Date()
            }
            completion(success)
        }
    }

    // MARK: Actions

    private var highlightedID: UUID? {
        guard keyboardActive else { return nil }
        let items = store.filteredTokens()
        if let selectedID, items.contains(where: { $0.id == selectedID }) {
            return selectedID
        }
        return items.first?.id
    }

    private func handleKey(_ command: PopoverKeyCommand) {
        guard showContent else {
            if command == .enter { promptUnlock() }
            return
        }
        let items = store.filteredTokens()
        guard !items.isEmpty else { return }
        guard keyboardActive else {
            keyboardActive = true
            selectedID = items.first?.id
            return
        }

        let current = items.firstIndex { $0.id == highlightedID } ?? 0
        switch command {
        case .up:
            selectedID = items[max(current - 1, 0)].id
        case .down:
            selectedID = items[min(current + 1, items.count - 1)].id
        case .enter:
            copyWithKeyboard(items[current])
        }
    }

    private func copyWithKeyboard(_ token: OTPToken) {
        guard let code = store.code(for: token) else { return }
        CodeClipboard.copy(code, playSound: appState.playSoundOnCopy)
        keyboardCopiedID = token.id
        NotificationCenter.default.post(name: .keyboardCopyDone, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if keyboardCopiedID == token.id {
                keyboardCopiedID = nil
            }
        }
    }

    private func beginRename(_ id: UUID) {

        guard let t = store.tokens.first(where: { $0.id == id }) else { return }

        renameIssuer = t.issuer
        renameAccount = t.account
        renameHandle = RenameHandle(id: id)

    }

    private func beginEditSecret(_ id: UUID) {

        authenticate { success in

            guard success else { return }

            if let t = store.tokens.first(where: { $0.id == id }) {
                editSecretToken = t
            }

        }

    }

    private func beginShowQR(_ id: UUID) {

        authenticate { success in

            guard success else { return }

            if let t = store.tokens.first(where: { $0.id == id }) {
                qrToken = t
            }

        }

    }

    private func beginDelete(_ id: UUID) {

        deleteTokenID = id
        showDeleteAlert = true

    }

}
