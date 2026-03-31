import SwiftUI
import LocalAuthentication

private struct RenameHandle: Identifiable, Equatable { let id: UUID }

struct RootPopoverView: View {

    @StateObject private var store = OTPStore.sampleStore()
    @ObservedObject private var appState = AppState.shared

    @State private var autoCloseOnCopy: Bool = true

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

    var body: some View {

        ZStack {

            VisualEffectBackground(material: .hud, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(6)

            VStack(alignment: .leading, spacing: 12) {

                header
                searchField

                TokenListView(
                    store: store,
                    timer: store.timer,
                    autoCloseOnCopy: $autoCloseOnCopy,
                    onPin: { id in store.togglePin(id) },
                    onRename: { id in beginRename(id) },
                    onEditSecret: { id in beginEditSecret(id) },
                    onDelete: { id in beginDelete(id) },
                    onShowQR: { id in beginShowQR(id) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
            .padding(16)
        }
        .background(Color.clear)
//новый блок
        .onAppear {
            NotificationCenter.default.post(name: .storeReady, object: store)
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

            Button(action: {

                AddTokenWindowController.shared.show(store: store) { list in
                    store.addImportedMany(list)
                }

            }) {

                Image(systemName: "plus")

            }
            .buttonStyle(BorderlessButtonStyle())
            .help("Add token")

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

    // MARK: Footer

    private var footer: some View {

        VStack(spacing: 8) {

            HStack {

                Toggle(isOn: $autoCloseOnCopy) {
                    Text("Close after copying")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .toggleStyle(SwitchToggleStyle())

                Spacer()

            }

            HStack {

                Toggle(isOn: $appState.pinPopover) {
                    Text("Pin popover")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .toggleStyle(SwitchToggleStyle())

                Spacer()

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Text("Exit")
                }

            }

        }
        .padding(.top, 4)
    }

    // MARK: Auth helpers

    private func isAuthRecent() -> Bool {
        guard let lastAuthTime else { return false }
        return Date().timeIntervalSince(lastAuthTime) < 30
    }

    private func authenticate(_ completion: @escaping (Bool) -> Void) {

        if isAuthRecent() {
            completion(true)
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        let context = LAContext()
        var error: NSError?

        let reason = "Authenticate to access protected OTP data"

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {

            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in

                DispatchQueue.main.async {

                    if success {
                        lastAuthTime = Date()
                    }

                    completion(success)
                }

            }

        } else {
            completion(true)
        }
    }

    // MARK: Actions

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
