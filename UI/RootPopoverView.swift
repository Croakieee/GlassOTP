import SwiftUI

private struct RenameHandle: Identifiable, Equatable { let id: UUID }

struct RootPopoverView: View {
    @StateObject private var store = OTPStore.sampleStore()
    @ObservedObject private var appState = AppState.shared

    @State private var autoCloseOnCopy: Bool = true

    // rename
    @State private var renameHandle: RenameHandle?
    @State private var renameIssuer: String = ""
    @State private var renameAccount: String = ""

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
                    onDelete: { id in beginDelete(id) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
            .padding(16)
        }
        .background(Color.clear)
        // РАНЬШЕ здесь был .sheet(isPresented: $showAddSheet) — его удалить!
        // Лист переименования оставляем:
        .sheet(item: $renameHandle, onDismiss: { renameIssuer = ""; renameAccount = "" }) { _ in
            RenameTokenSheet(
                originalIssuer: renameIssuer,
                originalAccount: renameAccount
            ) { newIssuer, newAccount in
                if let id = renameHandle?.id {
                    store.rename(id, issuer: newIssuer, account: newAccount)
                }
            }
        }
        .alert(isPresented: $showDeleteAlert) {
            Alert(
                title: Text("Удалить токен?"),
                message: Text("Действие нельзя отменить. Секрет будет удалён из связки ключей."),
                primaryButton: .destructive(Text("Удалить")) {
                    if let id = deleteTokenID { store.remove(id) }
                    deleteTokenID = nil
                },
                secondaryButton: .cancel { deleteTokenID = nil }
            )
        }
    }

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
                AddTokenWindowController.shared.show { list in
                    store.addImportedMany(list)
                }
            }) {
                Image(systemName: "plus")
            }
            .buttonStyle(BorderlessButtonStyle())
            .help("Добавить токен")
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("Поиск по аккаунтам…", text: $store.query)
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

    private var footer: some View {
        VStack(spacing: 8) {
            HStack {
                Toggle(isOn: $autoCloseOnCopy) {
                    Text("Закрывать после копирования")
                        .font(.footnote).foregroundColor(.secondary)
                }
                .toggleStyle(SwitchToggleStyle())
                Spacer()
            }
            HStack {
                Toggle(isOn: $appState.pinPopover) {
                    Text("Прикрепить поповер")
                        .font(.footnote).foregroundColor(.secondary)
                }
                .toggleStyle(SwitchToggleStyle())
                Spacer()
                Button(action: { NSApplication.shared.terminate(nil) }) { Text("Выход") }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func beginRename(_ id: UUID) {
        guard let t = store.tokens.first(where: { $0.id == id }) else { return }
        renameIssuer = t.issuer
        renameAccount = t.account
        renameHandle = RenameHandle(id: id)
    }

    private func beginDelete(_ id: UUID) {
        deleteTokenID = id
        showDeleteAlert = true
    }
}
